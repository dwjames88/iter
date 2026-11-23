import Foundation
import Observation
import IterGo
import IterGoActivity
import IterFeatures
import IterModel
import IterPlan
import IterScreens
import IterSources
import IterStore

// OWNER: W2 (Go). CONTRACT members are used by the shell (W1); keep their names and signatures.

/// Owns trip mode for the app: the one `GoModel` on the live engine (or fakes in tests, render copies and sample runs), the
/// trips Go offers, starting and restoring runs, deep links and notification actions.
@MainActor @Observable
final class GoController {
    /// The one Go model. Views read its snapshot, permissions and pending navigation.
    @ObservationIgnored let model: GoModel
    /// How the engine is wired (decided once, in `GoWiring.mode`).
    @ObservationIgnored let mode: GoWiringMode
    /// The fakes behind the engine when `mode` is not live; nil when live.
    @ObservationIgnored let fakes: GoFakeKit?

    @ObservationIgnored private let container: AppContainer
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let wantsSampleRun: Bool
    @ObservationIgnored private lazy var lightEngine = GoTripInputBuilder.defaultLightEngine()

    convenience init(container: AppContainer, library: LibraryModel) {
        self.init(container: container, library: library, bundleID: Bundle.main.bundleIdentifier,
                  environment: ProcessInfo.processInfo.environment)
    }

    /// `bundleID` and `environment` decide live versus fakes (tests pass a render bundle id). `fakeDirectory` is where a fake-wired
    /// controller keeps its run files (tests reuse one to simulate a relaunch).
    init(container: AppContainer, library: LibraryModel, bundleID: String?, environment: [String: String], fakeDirectory: URL? = nil) {
        self.container = container
        self.library = library
        let options = container.options
        let mode = GoWiring.mode(bundleID: bundleID, environment: environment, options: options)
        self.mode = mode
        wantsSampleRun = GoWiring.wantsSampleRun(options: options, mode: mode)
        switch mode {
        case .live:
            fakes = nil
            model = GoModel(dependencies: Self.liveDependencies(container: container))
        case .fake(let location):
            let position = location ?? (GoWiring.wantsSampleRun(options: options, mode: mode) ? Self.sampleStartPosition(container.library) : nil)
            let kit = GoFakeKit(position: position)
            fakes = kit
            let persistence = StoreRunPersistence(store: container.library, directory: fakeDirectory ?? Self.temporaryDirectory())
            model = GoModel(dependencies: kit.dependencies(routing: container.routing, conditions: container.conditionsService,
                                                           persistence: persistence))
        }
    }

    // MARK: Wiring

    private static func liveDependencies(container: AppContainer) -> GoEngineDependencies {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("Go", isDirectory: true)
        let snapshotStore: any GoSnapshotStoring = AppGroupSnapshotStore().map { $0 as any GoSnapshotStoring }
            ?? InMemorySnapshotStore()
        return GoEngineDependencies(
            clock: SystemSourceClock(), routing: container.routing, conditions: container.conditionsService,
            location: CoreLocationLiveLocation(), notifications: UserNotificationScheduler(), activity: ActivityKitController(),
            snapshotStore: snapshotStore, widgetReloader: WidgetKitReloader(),
            persistence: StoreRunPersistence(store: container.library, directory: directory),
            engineState: FileEngineStateStore(directory: directory), power: DevicePowerMonitor(), background: BackgroundTaskScheduler())
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iter-go-\(UUID().uuidString)", isDirectory: true)
    }

    /// Where the scripted device sits for a sample run: about 11 km south of the sample trip's first stop, so the hero card has a
    /// real drive time and leave-by.
    private static func sampleStartPosition(_ store: LibraryStore) -> Coordinate? {
        guard let trip = sampleTrip(in: store), let first = Self.ordered(trip.stops).first else { return nil }
        return Coordinate(latitude: first.place.coordinate.latitude - 0.1, longitude: first.place.coordinate.longitude)
    }

    private static func sampleTrip(in store: LibraryStore) -> Trip? {
        let trips = store.trips.values()
        return trips.first { $0.name == SampleLibrary.tripName } ?? trips.first
    }

    // MARK: CONTRACT

    /// CONTRACT: a run is going (the shell shows the Go tab first while true).
    var isRunning: Bool { model.isRunning }

    /// CONTRACT: the trips Go offers to start, from the library.
    var trips: [GoTripChoice] { library.trips.compactMap { row in library.trip(id: row.id).map(Self.choice) } }

    /// CONTRACT: starts trip mode for a trip (from Build's "Start Trip" or Go's own picker).
    func start(tripID: UUID, stopID: UUID? = nil, alreadyThere: Bool = false) async {
        guard let input = input(forTrip: tripID) else { return }
        fakes?.emitFix()
        await model.start(input, at: stopID, alreadyThere: alreadyThere)
    }

    /// CONTRACT: at launch, resumes an unfinished run if the library has one. True when it did (or one is already going).
    /// Idempotent. A sample run (`-IterGoSampleRun YES`, fakes only) starts the seeded trip at its first stop instead.
    func restoreAtLaunch() async -> Bool {
        if model.isRunning { return true }
        fakes?.emitFix()
        for row in library.trips {
            guard container.library.runs.activeRun(forTrip: row.id) != nil, let input = input(forTrip: row.id) else { continue }
            if await model.restoreIfRunning(input) { return true }
        }
        guard wantsSampleRun, let trip = Self.sampleTrip(in: container.library) else { return false }
        await start(tripID: trip.id, stopID: Self.ordered(trip.stops).first?.id)
        return model.isRunning
    }

    /// CONTRACT: the scene became active (foreground + permissions refresh).
    func sceneBecameActive() async {
        fakes?.emitFix()
        await model.foreground()
        await model.refreshPermissions()
    }

    /// CONTRACT: handles `iter://go...` links. True when the URL was Go's (the shell then shows the Go tab).
    func handle(url: URL) -> Bool {
        guard let link = GoLink.parse(url) else { return false }
        if case .navigate(let stopID) = link {
            let info = stopID.map { ["stopID": $0.uuidString] } ?? [:]
            let model = model
            Task { await model.handleNotificationAction(identifier: GoNotificationCategory.navigateAction, userInfo: info) }
        }
        return true
    }

    // MARK: Inputs

    /// The engine's input for a trip: its start place, session windows and the drives Build worked out for it (kept beside the
    /// offline pack, see `PlannedLegStoring`), so Go starts from planned leave-by and arrival times and routes only a leg that is
    /// missing or no longer fits the trip's places.
    func input(forTrip tripID: UUID) -> GoTripInput? {
        guard let trip = library.trip(id: tripID) else { return nil }
        let startPlaces = trip.startPlaceID.flatMap { container.library.places.value(id: $0) }.map { [$0] } ?? []
        let start = GoTripInputBuilder.startPlace(for: trip, in: startPlaces)
        let legs = container.plannedLegStore.load(tripID: tripID)?.legs(for: trip, start: start) ?? [:]
        var input = GoTripInputBuilder.make(trip: trip, start: start, engine: lightEngine, plannedLegs: legs)
        input.isSampleData = container.dataMode == .sample
        return input
    }

    /// Stops in day order, then trip order within the day (the numbers Go and the map use).
    static func ordered(_ stops: [Stop]) -> [Stop] {
        stops.enumerated().sorted { a, b in
            a.element.dayIndex != b.element.dayIndex ? a.element.dayIndex < b.element.dayIndex : a.offset < b.offset
        }.map(\.element)
    }

    /// A trip as Go's start screen lists it.
    static func choice(_ trip: Trip) -> GoTripChoice {
        GoTripChoice(id: trip.id, name: trip.name, startDay: trip.startDay, dayCount: trip.dayCount,
                     stops: ordered(trip.stops).enumerated().map { index, stop in
            GoTripChoice.StopChoice(id: stop.id, number: index + 1, name: stop.place.name, dayIndex: stop.dayIndex,
                                    windowKind: stop.kind == .light ? stop.session : nil)
        })
    }

    // MARK: Actions for the views

    /// Every Go action bound to the model; `navigate` and `openSettings` are the view's (it owns `openURL`).
    func actions(navigate: @escaping (NavigationHandoff) -> Void, openSettings: @escaping () -> Void) -> GoActions {
        let model = model
        return GoActions(
            leaveNow: { await model.leaveNow() }, arrived: { await model.arrived() }, doneHere: { await model.doneHere() },
            skip: { await model.skip($0) }, notYet: { await model.notYet() }, pause: { await model.pause() },
            resume: { await model.resume() }, end: { await model.end() }, navigate: navigate,
            requestLocationWhenInUse: { model.requestLocationWhenInUse() }, requestLocationAlways: { model.requestLocationAlways() },
            requestNotifications: { await model.requestNotifications() }, openSettings: openSettings,
            start: { [weak self] tripID, stopID, there in await self?.start(tripID: tripID, stopID: stopID, alreadyThere: there) })
    }
}
