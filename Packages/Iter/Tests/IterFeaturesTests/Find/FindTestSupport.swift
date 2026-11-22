import Foundation
import Synchronization
import Testing
import IterModel
import IterSources
import IterStore
import IterDiscovery
import IterSourcesLive
@testable import IterFeatures

/// Waits (polling the main actor) until `condition` holds or `limit` passes.
@MainActor
func waitUntil(_ limit: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let end = ContinuousClock.now + limit
    while ContinuousClock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A runner the test drives by hand: each `run` hands back a stream the test feeds, and records the request.
final class ControlledRunner: DiscoveryRunning, @unchecked Sendable {
    private struct State {
        var requests: [DiscoveryRequest] = []
        var continuations: [AsyncStream<DiscoveryEvent>.Continuation] = []
    }
    private let state = Mutex(State())

    func run(_ request: DiscoveryRequest) -> AsyncStream<DiscoveryEvent> {
        let (stream, continuation) = AsyncStream<DiscoveryEvent>.makeStream()
        state.withLock { $0.requests.append(request); $0.continuations.append(continuation) }
        return stream
    }

    var requests: [DiscoveryRequest] { state.withLock { $0.requests } }
    func send(_ event: DiscoveryEvent, to run: Int) { _ = state.withLock { $0.continuations[run] }.yield(event) }
    func finish(_ run: Int) { state.withLock { $0.continuations[run] }.finish() }
}

/// The real engine, counting how many searches went to it.
final class CountingRunner: DiscoveryRunning, @unchecked Sendable {
    let engine: DiscoveryEngine
    private let count = Mutex(0)
    init(_ engine: DiscoveryEngine) { self.engine = engine }
    var runs: Int { count.withLock { $0 } }
    func run(_ request: DiscoveryRequest) -> AsyncStream<DiscoveryEvent> {
        count.withLock { $0 += 1 }
        return engine.run(request)
    }
}

@MainActor
struct Rig {
    let library: LibraryStore
    let undo = UndoManager()
    let preferences = Preferences.ephemeral()
    let routing: FindFixtures.Routing
    let model: FindModel
    let runner: any DiscoveryRunning

    static let fastFind = FindConfiguration(slowAfter: .milliseconds(150), tick: .milliseconds(20), driveTimeCount: 10, driveTimeConcurrency: 2,
                                            lookupTimeout: .seconds(2))

    init(runner: (any DiscoveryRunning)? = nil, location: Coordinate? = FindFixtures.moab, routing: FindFixtures.Routing = .init(),
         placeSearch: any PlaceSearchProvider = FindFixtures.PlaceSearch(), geocoder: any IterSources.Geocoder = FindFixtures.FixtureGeocoder(),
         streetLevel: (any StreetLevelImageryProvider)? = FindFixtures.StreetLevel(coveredNear: FindFixtures.mesaArch),
         configuration: FindConfiguration = Rig.fastFind, undoable: Bool = false) throws {
        library = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer())
        undo.groupsByEvent = false
        if undoable { library.undoManager = undo }
        library.actionName = { $0.rawValue }
        self.routing = routing
        let used = runner ?? FindFixtures.engine()
        self.runner = used
        let provider: any LocationProviding = location.map { FixedLocationProvider($0) as any LocationProviding } ?? InertLocationProvider()
        model = FindModel(discovery: used, placeSearch: placeSearch, geocoder: geocoder, routing: routing, streetLevel: streetLevel,
                          magnetic: WorldMagneticModelProvider(), gridReference: MGRSProvider(), library: library, preferences: preferences,
                          location: provider, now: { FindFixtures.retrievedAt }, configuration: configuration)
    }

    /// One user action = one undo group (the app gets this from the run loop).
    func act<T>(_ body: () -> T) -> T {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        return body()
    }

    func search() async {
        model.text = FindFixtures.query
        model.askIter()
        _ = await waitUntil { model.phase == .finished }
    }
}
