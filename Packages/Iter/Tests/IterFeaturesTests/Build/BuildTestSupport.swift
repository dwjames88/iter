import Foundation
import Observation
import Testing
import IterAstro
import IterConditions
import IterModel
import IterPlan
import IterSky
import IterSources
import IterStore
@testable import IterFeatures

// Fakes and a harness for the Build tests: an in-memory library, routing that answers from a formula and can fail or hold,
// a conditions source that records what was asked, a sleeper the test fires, and a pack builder that records builds.

/// A sleep a test controls. Durations `holds` accepts wait until `fire`; every other sleep returns at once. Each requested
/// duration is recorded in order.
final class TestSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: (duration: Duration, continuation: CheckedContinuation<Void, any Error>)] = [:]
    private var cancelledEarly: Set<UUID> = []
    private var recorded: [Duration] = []
    private let holds: @Sendable (Duration) -> Bool

    init(holds: @escaping @Sendable (Duration) -> Bool = { _ in false }) { self.holds = holds }

    var requested: [Duration] { lock.withLock { recorded } }
    var waiting: [Duration] { lock.withLock { waiters.values.map(\.duration) } }

    func sleep(_ duration: Duration) async throws {
        lock.withLock { recorded.append(duration) }
        // Long waits (retry backoff) always suspend until cancelled or fired, so a model left behind can never spin.
        guard holds(duration) || duration >= .seconds(30) else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let early = lock.withLock { () -> Bool in
                    if cancelledEarly.remove(id) != nil { return true }
                    waiters[id] = (duration, continuation)
                    return false
                }
                if early { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
                if let w = waiters.removeValue(forKey: id) { return w.continuation }
                cancelledEarly.insert(id)
                return nil
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// Ends every waiting sleep `matching` accepts, as if its time had passed.
    func fire(where matching: @Sendable (Duration) -> Bool = { _ in true }) {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            let ids = waiters.filter { matching($0.value.duration) }.map(\.key)
            return ids.compactMap { waiters.removeValue(forKey: $0)?.continuation }
        }
        for c in ready { c.resume() }
    }
}

/// Routing from a formula (straight-line distance x 1.3 at 25 m/s), recording calls, with optional failure and a gate.
final class FakeRouting: RoutingProvider, @unchecked Sendable {
    struct Call: Equatable, Sendable { var from: Coordinate; var to: Coordinate; var departing: Date? }

    let descriptor = SourceCatalogue.appleDirections
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var current = 0
    private var peakValue = 0
    private var failure: (any Error)?
    private var held = false
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var scale = 1.0
    private var pathPoints = 2

    var calls: [Call] { lock.withLock { recorded } }
    var inFlight: Int { lock.withLock { current } }
    var peak: Int { lock.withLock { peakValue } }

    func setFailure(_ error: (any Error)?) { lock.withLock { failure = error } }
    func setScale(_ factor: Double) { lock.withLock { scale = factor } }
    func setPathPoints(_ n: Int) { lock.withLock { pathPoints = n } }

    /// While held, every call waits (and counts as in flight).
    func hold() { lock.withLock { held = true } }

    func release() {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            held = false
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        for c in ready { c.resume() }
    }

    func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        lock.withLock {
            recorded.append(Call(from: from, to: to, departing: departing))
            current += 1
            peakValue = max(peakValue, current)
        }
        defer { lock.withLock { current -= 1 } }
        let id = UUID()
        if lock.withLock({ held }) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    let wait = lock.withLock { () -> Bool in
                        if !held { return false }
                        waiters[id] = c
                        return true
                    }
                    if !wait { c.resume() }
                }
            } onCancel: {
                let c = lock.withLock { waiters.removeValue(forKey: id) }
                c?.resume(throwing: CancellationError())
            }
        }
        let (error, factor, points) = lock.withLock { (failure, scale, pathPoints) }
        if let error { throw error }
        let meters = from.distance(to: to) * 1.3
        let path = (0..<max(2, points)).map { i -> Coordinate in
            let t = Double(i) / Double(max(1, points - 1))
            return Coordinate(latitude: from.latitude + (to.latitude - from.latitude) * t,
                              longitude: from.longitude + (to.longitude - from.longitude) * t)
        }
        return Route(path: path, seconds: meters / 25 * factor, meters: meters, departing: departing,
                     isTrafficAware: departing != nil)
    }

    func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        let r = try await route(from: from, to: to, departing: departing)
        return ETA(seconds: r.seconds, arrival: departing.addingTimeInterval(r.seconds), departing: departing)
    }
}

/// A conditions source that records what the model asked for and serves the samples a test sets.
@MainActor @Observable
final class FakeConditions: BuildConditionsSource {
    struct Request: Equatable { var name: String; var day: LocalDay; var priority: ConditionsPriority }
    struct Key: Hashable { var placeID: UUID; var day: LocalDay }

    var samples: [Key: ConditionsSample] = [:]
    @ObservationIgnored var requests: [Request] = []
    @ObservationIgnored var activeTrip: Set<UUID> = []
    @ObservationIgnored var visible: Set<UUID> = []

    func setActiveTrip(_ placeIDs: Set<UUID>) { activeTrip = placeIDs }
    func setVisible(_ placeIDs: Set<UUID>) { visible = placeIDs }
    func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) {
        requests.append(Request(name: place.name, day: day, priority: priority))
    }
    func sample(placeID: UUID, day: LocalDay) -> ConditionsSample { samples[Key(placeID: placeID, day: day)] ?? .empty }
}

/// Records pack builds; `existing` is what a stored pack's age answers.
final class FakePacks: OfflinePackBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var built: [Trip] = []
    private var stored: Date?
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date, existing: Date? = nil) {
        self.clock = clock
        stored = existing
    }

    var builds: [Trip] { lock.withLock { built } }

    func buildOfflinePack(for trip: Trip) async throws -> Date {
        let at = clock()
        lock.withLock { built.append(trip); stored = at }
        return at
    }

    func packBuiltAt(tripID: UUID) async -> Date? { lock.withLock { stored } }
}

/// 2026-10-05 16:00 UTC: Monday 10:00 in Denver, the day before the sample trip starts.
let testNow = Date(timeIntervalSince1970: 1_791_216_000)

@MainActor
final class BuildHarness {
    let library: LibraryStore
    let undo = UndoManager()
    let routing = FakeRouting()
    let conditions = FakeConditions()
    let sleeper: TestSleeper
    let packs: FakePacks
    let trip: TripRecord
    let day = LocalDay(year: 2026, month: 10, day: 6)

    /// A library with the four-day Canyon Country template starting 2026-10-06 (6 stops, 5 legs).
    init(sleeper: TestSleeper = TestSleeper(), packExisting: Date? = nil, template: Bool = true, undoable: Bool = false) throws {
        library = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer(), clock: { testNow })
        undo.groupsByEvent = false
        self.sleeper = sleeper
        packs = FakePacks(clock: { testNow }, existing: packExisting)
        let start = LocalDay(year: 2026, month: 10, day: 6)
        if template {
            trip = library.trips.create(from: TripTemplates.template(id: "canyon-country")!, startDay: start)
        } else {
            trip = library.trips.create(name: "Empty", startDay: start, dayCount: 3)
        }
        if undoable { library.undoManager = undo }
    }

    private var made: [BuildModel] = []

    /// Every model the harness made is closed when the test ends, so nothing outlives it.
    isolated deinit { for model in made { model.close() } }

    func model(timing: BuildTiming? = nil) -> BuildModel {
        let sleeper = self.sleeper
        let timing = timing ?? BuildTiming(sleep: { try await sleeper.sleep($0) })
        let model = BuildModel(tripID: trip.id, library: library, conditions: conditions, packs: packs, routing: routing,
                               now: { testNow }, engine: LightEngine(ephemeris: MemoizedEphemeris.shared), timing: timing)
        made.append(model)
        return model
    }

    /// One user action is one undo group (the app gets this from the run loop).
    func act<T>(_ body: () -> T) -> T {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        return body()
    }

    func spot(_ slug: String) -> Place { CuratedSpots.spot(id: slug)! }

    func ownPlace(_ name: String = "Home Base") -> UUID {
        library.places.createUserSpot(name: name, coordinate: Coordinate(latitude: 40.76, longitude: -111.89),
                                      timeZoneIdentifier: "America/Denver").id
    }
}

extension BuildModel {
    var stopRows: [BuildStop] { rows.compactMap { if case .stop(let s) = $0.kind { s } else { nil } } }
    var driveRows: [BuildDrive] {
        rows.compactMap {
            switch $0.kind {
            case .drive(let d): d
            case .transfer(let t): t.drive
            default: nil
            }
        }
    }
    var transferRows: [BuildTransfer] { rows.compactMap { if case .transfer(let t) = $0.kind { t } else { nil } } }
    func stop(named name: String) -> BuildStop? { stopRows.first { $0.name == name } }
}

/// Lets the main actor and the drive tasks run until `condition` holds. A few yields first, then 1 ms naps (never a spin, so
/// parallel suites keep the main actor), for up to five seconds.
@MainActor func settle(_ condition: () -> Bool) async -> Bool {
    for i in 0..<5_000 {
        if condition() { return true }
        if i < 40 { await Task.yield() } else { try? await Task.sleep(for: .milliseconds(1)) }
    }
    return condition()
}
