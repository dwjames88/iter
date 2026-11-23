import Foundation
import IterGo
import IterModel
import IterSources

/// How the app wires Go's engine: the real adapters (location, notifications, Live Activity, App Group snapshot, background
/// refresh) or fakes that can never prompt or post.
public enum GoWiringMode: Equatable, Sendable {
    /// The real app on its real data: every adapter is the system one.
    case live
    /// Tests, render copies, sample data and fixed locations. `location` is where the scripted device sits, if one was given.
    case fake(location: Coordinate?)
}

public enum GoWiring {
    /// Live only for the real app outside a test host with no `-IterLocation` and no sample data; anything else gets fakes, so a
    /// render or a test can never show a permission dialog or post a notification.
    public static func mode(bundleID: String?, environment: [String: String], options: LaunchOptions) -> GoWiringMode {
        let real = StorePlacement.isRealProcess(bundleID: bundleID, environment: environment)
        if real, options.fixedLocation == nil, !options.sampleData { return .live }
        return .fake(location: options.fixedLocation)
    }

    /// `-IterGoSampleRun YES`: start the seeded sample trip at its first stop on launch. Honoured only with fakes.
    public static func wantsSampleRun(options: LaunchOptions, mode: GoWiringMode) -> Bool {
        guard case .fake = mode else { return false }
        let args = options.arguments
        guard let i = args.firstIndex(of: "-IterGoSampleRun"), i + 1 < args.count else { return false }
        return ["yes", "true", "1"].contains(args[i + 1].lowercased())
    }
}

/// An `iter://go...` link, parsed.
public enum GoLink: Equatable, Sendable {
    /// `iter://go`: show Go.
    case open
    /// `iter://go/navigate[?stop=<uuid>]`: show Go and navigate to the stop (the next one when nil).
    case navigate(stopID: UUID?)

    /// nil when the URL is not a Go link.
    public static func parse(_ url: URL) -> GoLink? {
        guard url.scheme?.lowercased() == "iter", url.host?.lowercased() == "go" else { return nil }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        guard parts.first == "navigate" else { return .open }
        let stop = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "stop" }?.value.flatMap(UUID.init(uuidString:))
        return .navigate(stopID: stop)
    }
}

/// The fakes behind a non-live `GoModel`, kept so tests can ask what was (not) touched. None of them reaches a system API.
@MainActor
public final class GoFakeKit {
    public let clock: any SourceClock
    public let location: ScriptedLocation
    public let notifications: FakeNotificationScheduler
    public let activity: FakeLiveActivityController
    public let snapshotStore: InMemorySnapshotStore
    public let widgetReloader: FakeWidgetReloader
    public let engineState: InMemoryEngineStateStore
    public let power: FixedPower
    public let background: FakeBackgroundScheduler
    /// Where the scripted device sits.
    public private(set) var position: Coordinate?

    /// Authorization is `.always` and notifications `.authorized`, so nothing in Go ever asks.
    public init(position: Coordinate?, clock: any SourceClock = SystemSourceClock()) {
        self.clock = clock
        self.position = position
        location = ScriptedLocation(clock: clock, authorization: .always)
        notifications = FakeNotificationScheduler(authorization: .authorized)
        activity = FakeLiveActivityController()
        snapshotStore = InMemorySnapshotStore()
        widgetReloader = FakeWidgetReloader()
        engineState = InMemoryEngineStateStore()
        power = FixedPower()
        background = FakeBackgroundScheduler()
    }

    /// Moves the scripted device and sends a fresh fix there (a stationary one, so the run never reads it as driving).
    public func place(at coordinate: Coordinate?) {
        position = coordinate
        emitFix()
    }

    /// A fresh fix at the current position, so the engine never sees the location as stale. No-op without a position.
    public func emitFix() {
        guard let position else { return }
        location.send(.fix(LocationFix(coordinate: position, accuracyM: 10, speedMs: 0, courseDeg: nil, timestamp: clock.now)))
    }

    public func dependencies(routing: any RoutingProvider, conditions: any TripConditionsProviding,
                             persistence: any RunPersisting) -> GoEngineDependencies {
        GoEngineDependencies(clock: clock, routing: routing, conditions: conditions, location: location, notifications: notifications,
                             activity: activity, snapshotStore: snapshotStore, widgetReloader: widgetReloader, persistence: persistence,
                             engineState: engineState, power: power, background: background)
    }
}
