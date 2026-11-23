import Foundation
import Synchronization
import IterAI
import IterModel
import IterSources
import IterStore
import IterDiscovery

/// The named states a Find screen is drawn in. Deterministic: fixed places around Canyonlands, a fixed location (Moab), no network.
public enum FindPreviewState: String, CaseIterable, Sendable {
    /// Nothing searched.
    case empty
    /// Mid-run: plan and area known, OpenStreetMap still searching and slow, Apple Maps just started, two partial places.
    case searching
    /// Finished with the on-device model: citations, a photo with its licence, confirmed and single-source results, real drive times.
    case results
    /// Finished, but the router has not answered: every time says "straight-line".
    case driveTimesPending
    /// Finished without Apple Intelligence: "Basic search: AI unavailable (Apple Intelligence is turned off)".
    case basicSearch
    /// Finished with OpenStreetMap down (HTTP 504): Apple Maps results only, the source shown as down.
    case sourceDown
}

/// A clock the preview moves by hand.
final class PreviewClock: Sendable {
    private let value = Mutex(100.0)
    var now: Double { value.withLock { $0 } }
    func set(_ t: Double) { value.withLock { $0 = t } }
}

/// Wraps an engine and rewrites its events (to show the model-planned state without a model).
struct TransformingRunner: DiscoveryRunning {
    let engine: DiscoveryEngine
    let transform: @Sendable (DiscoveryEvent) -> DiscoveryEvent
    func run(_ request: DiscoveryRequest) -> AsyncStream<DiscoveryEvent> {
        let source = engine.run(request)
        let map = transform
        return AsyncStream { continuation in
            let task = Task {
                for await e in source { continuation.yield(map(e)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// A runner fed by hand.
final class HeldRunner: DiscoveryRunning, Sendable {
    private let continuation = Mutex<AsyncStream<DiscoveryEvent>.Continuation?>(nil)
    func run(_ request: DiscoveryRequest) -> AsyncStream<DiscoveryEvent> {
        let (stream, c) = AsyncStream<DiscoveryEvent>.makeStream()
        continuation.withLock { $0 = c }
        return stream
    }
    func send(_ e: DiscoveryEvent) { _ = continuation.withLock { $0 }?.yield(e) }
}

@MainActor
public enum FindPreviewData {
    /// A model in `state`, run to that state (it awaits the run, so call it from a task).
    public static func model(_ state: FindPreviewState) async throws -> FindModel {
        let library = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer())
        let clock = PreviewClock()
        let config = FindConfiguration(slowAfter: .seconds(6), tick: .seconds(3600), monotonic: { clock.now })
        let routing = FindFixtures.Routing(hangs: state == .driveTimesPending)
        func make(_ runner: any DiscoveryRunning) -> FindModel {
            FindModel(discovery: runner, placeSearch: FindFixtures.PlaceSearch(), geocoder: FindFixtures.FixtureGeocoder(), routing: routing,
                      streetLevel: FindFixtures.StreetLevel(), magnetic: PreviewMagnetic(), gridReference: PreviewGrid(), library: library,
                      preferences: Preferences.ephemeral(), location: FixedLocationProvider(FindFixtures.moab),
                      now: { FindFixtures.retrievedAt }, configuration: config)
        }
        switch state {
        case .empty:
            return make(HeldRunner())
        case .searching:
            let held = HeldRunner()
            let m = make(held)
            m.text = FindFixtures.query
            m.askIter()
            let engine = FindFixtures.engine()
            let result = await engine.discover(DiscoveryRequest(text: FindFixtures.query, currentLocation: FindFixtures.moab))
            held.send(.planReady(result.plan, .basicNoModel))
            if let area = result.area { held.send(.areaResolved(area)) }
            held.send(.statusChanged(SourceStatus(source: FindFixtures.osm, name: "OpenStreetMap (Overpass)", role: .gazetteer, state: .searching)))
            _ = await settle { m.chips.count >= 1 }
            clock.set(107)
            held.send(.statusChanged(SourceStatus(source: .appleSearch, name: "Apple Maps", role: .placeSearch, state: .searching)))
            held.send(.statusChanged(SourceStatus(source: .appleGeocoder, name: "Apple Maps", role: .geocoder, state: .found(1))))
            held.send(.partial(Array(result.places.prefix(2))))
            held.send(.statusChanged(SourceStatus(source: FixedSources.reddit, name: "Reddit", role: .text, state: .unavailable(FixedSources.redditReason))))
            held.send(.statusChanged(SourceStatus(source: FixedSources.google, name: "Google", role: .text, state: .unavailable(FixedSources.googleReason))))
            _ = await settle { m.chips.count >= 5 && m.rows.count == 2 }
            return m
        case .results, .driveTimesPending:
            let m = make(TransformingRunner(engine: FindFixtures.engine(), transform: modelPlanned))
            await run(m)
            if state == .results { _ = await settle { m.rows.allSatisfy { $0.drive?.basis == .drive } } }
            else { _ = await settle { routing.calls >= 2 } }
            return m
        case .basicSearch:
            let m = make(TransformingRunner(engine: FindFixtures.engine()) { e in
                switch e {
                case .planReady(let p, _): .planReady(p, .basic(reason: .appleIntelligenceNotEnabled))
                case .finished(var r): { r.planOrigin = .basic(reason: .appleIntelligenceNotEnabled); return .finished(r) }()
                default: e
                }
            })
            await run(m)
            return m
        case .sourceDown:
            let m = make(FindFixtures.engine(gazetteer: .init(error: .http(status: 504, excerpt: "Gateway Timeout"))))
            await run(m)
            return m
        }
    }

    private static func run(_ m: FindModel) async {
        m.text = FindFixtures.query
        m.askIter()
        _ = await settle { m.phase == .finished }
    }

    @Sendable nonisolated static func modelPlanned(_ e: DiscoveryEvent) -> DiscoveryEvent {
        let ai = SourceStatus(source: FixedSources.ai, name: "Apple Intelligence", role: .ai, state: .found(1))
        switch e {
        case .planReady(let p, _): return .planReady(p, .ai)
        case .statusChanged(let s) where s.source == FixedSources.ai: return .statusChanged(ai)
        case .finished(var r):
            r.planOrigin = .ai
            r.statuses = r.statuses.map { $0.source == FixedSources.ai ? ai : $0 }
            if !r.places.isEmpty {
                r.places[0].why = PlaceExplanation(text: "A confirmed viewpoint with an arch that frames the sunrise, listed by two sources.", isModelWritten: true)
            }
            return .finished(r)
        default: return e
        }
    }

    private static func settle(_ limit: Duration = .seconds(30), _ condition: @MainActor () -> Bool) async -> Bool {
        let end = ContinuousClock.now + limit
        while ContinuousClock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// Fixed on-device answers so previews never depend on the model files.
struct PreviewMagnetic: MagneticModelProvider {
    let descriptor = SourceCatalogue.worldMagneticModel
    func field(at coordinate: Coordinate, elevationM: Double, on date: Date) throws -> Sourced<MagneticField> {
        Sourced(value: MagneticField(declinationDegrees: 8.4, inclinationDegrees: 63.1, totalIntensityNT: 51_200, date: date, nearMagneticPole: false),
                provenance: descriptor.provenance(fetchedAt: date))
    }
}

struct PreviewGrid: GridReferenceProvider {
    let descriptor = SourceCatalogue.mgrs
    func mgrs(for coordinate: Coordinate, precision: Int) throws -> Sourced<String> {
        Sourced(value: "12SWH5432187654", provenance: descriptor.provenance(fetchedAt: Date(timeIntervalSince1970: 1_791_806_400)))
    }
    func coordinate(fromMGRS text: String) throws -> Coordinate { throw SourceError.noSource }
}
