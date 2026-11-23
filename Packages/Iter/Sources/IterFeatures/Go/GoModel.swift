import Foundation
import Observation
import IterGo
import IterModel

/// The view model the iPhone Go screen binds to: one engine, the permissions it needs, and the user's actions (BLUEPRINT §3, §10).
/// It never touches the store (persistence is `StoreRunPersistence`, behind the engine) and imports no SwiftUI.
@MainActor @Observable
public final class GoModel {
    // MARK: Published state

    public private(set) var snapshot: GoSnapshot
    public private(set) var permissions: GoPermissions
    public private(set) var lastError: String?
    /// Set by the notification "Navigate" action. The UI opens it (Apple Maps) and then calls `consumeNavigation()`.
    public private(set) var pendingNavigation: NavigationHandoff?

    /// A run exists and has not ended.
    public var isRunning: Bool { snapshot.phase != .idle && snapshot.phase != .finished }
    public var activeTripID: UUID? { isRunning ? snapshot.tripID : nil }

    /// Where "Navigate" goes: the stop you are heading to, else the one you are at.
    public var navigation: NavigationHandoff? {
        guard isRunning, let stop = snapshot.next ?? snapshot.current else { return nil }
        return NavigationHandoff(destination: stop.coordinate, name: stop.name)
    }

    // MARK: Internals

    @ObservationIgnored private let engine: GoEngine
    @ObservationIgnored private let location: any LiveLocation
    @ObservationIgnored private let notifications: any NotificationScheduling
    @ObservationIgnored private let activity: any LiveActivityControlling
    @ObservationIgnored private let startsRunLoop: Bool
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var tripInput: GoTripInput?

    /// `dependencies.location`, `.notifications` and `.activity` are the instances the model asks about permissions, so they are
    /// the same ones the engine uses. `startsRunLoop: false` keeps tests deterministic (they drive the engine by hand).
    public init(dependencies: GoEngineDependencies, startsRunLoop: Bool = true) {
        engine = GoEngine(dependencies)
        location = dependencies.location
        notifications = dependencies.notifications
        activity = dependencies.activity
        self.startsRunLoop = startsRunLoop
        snapshot = engine.snapshot
        permissions = GoPermissions(location: dependencies.location.authorization, liveActivitiesEnabled: dependencies.activity.areActivitiesEnabled)
        engine.onSnapshot = { [weak self] snap in self?.apply(snap) }
    }

    // MARK: Start and restore

    /// Asks for what Go needs, then starts the run and its loop. Always is asked only when When In Use is all there is (the
    /// reason is `GoPermissions.alwaysReason`); nothing is asked twice.
    public func start(_ input: GoTripInput, at stopID: UUID? = nil, alreadyThere: Bool = false) async {
        lastError = nil
        guard !input.trip.stops.isEmpty else {
            lastError = "Add a stop before starting trip mode."
            return
        }
        cancelLoop()
        tripInput = input
        switch location.authorization {
        case .notDetermined: location.requestWhenInUse()
        case .whenInUse: location.requestAlways()
        case .always, .denied, .restricted: break
        }
        if await notifications.authorization() == .notDetermined { _ = await notifications.requestAuthorization() }
        await notifications.registerCategories()
        await engine.start(input, at: stopID, alreadyThere: alreadyThere)
        apply(engine.snapshot)
        launchLoop()
        await refreshPermissions()
    }

    /// Relaunch: resumes the trip's unfinished run. False when there is none.
    public func restoreIfRunning(_ input: GoTripInput) async -> Bool {
        tripInput = input
        guard await engine.restore(input) else { return false }
        apply(engine.snapshot)
        await notifications.registerCategories()
        launchLoop()
        await refreshPermissions()
        return true
    }

    // MARK: Actions

    public func leaveNow() async { await perform(.leaveNow) }
    public func arrived() async { await perform(.arrived) }
    public func doneHere() async { await perform(.doneHere) }
    /// nil skips the next stop.
    public func skip(_ stopID: UUID? = nil) async { await perform(.skip(stopID)) }
    /// Undoes the last automatic transition.
    public func notYet() async { await perform(.notYet) }
    public func pause() async { await perform(.pause) }
    public func resume() async { await perform(.resume) }
    /// Ends the run for good.
    public func end() async {
        await perform(.end)
        cancelLoop()
        pendingNavigation = nil
    }

    private func perform(_ action: RunUserAction) async {
        await engine.perform(action)
        apply(engine.snapshot)
        await refreshPermissions()
    }

    // MARK: Lifecycle

    public func foreground() async {
        await engine.foreground()
        apply(engine.snapshot)
        await refreshPermissions()
    }

    /// For the BGAppRefreshTask handler.
    public func backgroundRefresh() async {
        await engine.backgroundRefresh()
        apply(engine.snapshot)
    }

    /// Stops observing without ending the run (the scene is going away). A later `restoreIfRunning` picks it up.
    public func stop() { cancelLoop(); engine.stop() }

    // MARK: Permissions

    public func refreshPermissions() async {
        permissions = GoPermissions(location: location.authorization, notifications: await notifications.authorization(),
                                    liveActivitiesEnabled: activity.areActivitiesEnabled, runPhase: snapshot.phase)
    }

    public func requestLocationWhenInUse() {
        location.requestWhenInUse()
        permissions.location = location.authorization
    }

    public func requestLocationAlways() {
        location.requestAlways()
        permissions.location = location.authorization
    }

    public func requestNotifications() async {
        _ = await notifications.requestAuthorization()
        await notifications.registerCategories()
        await refreshPermissions()
    }

    // MARK: Notification actions

    /// The app's `UNUserNotificationCenterDelegate` forwards the action identifier and the request's `userInfo` here.
    public func handleNotificationAction(identifier: String, userInfo: [String: String]) async {
        switch identifier {
        case GoNotificationCategory.navigateAction:
            pendingNavigation = handoff(stopID: userInfo["stopID"].flatMap(UUID.init(uuidString:))) ?? navigation
        case GoNotificationCategory.notYetAction:
            await notYet()
        default:
            break
        }
    }

    public func consumeNavigation() { pendingNavigation = nil }

    // MARK: Private

    private func handoff(stopID: UUID?) -> NavigationHandoff? {
        guard let stopID else { return nil }
        if let stop = tripInput?.trip.stops.first(where: { $0.id == stopID }) {
            return NavigationHandoff(destination: stop.place.coordinate, name: stop.place.name)
        }
        for info in [snapshot.next, snapshot.current] {
            if let info, info.id == stopID { return NavigationHandoff(destination: info.coordinate, name: info.name) }
        }
        return nil
    }

    private func apply(_ snap: GoSnapshot) {
        snapshot = snap
        permissions.runPhase = snap.phase
        permissions.location = location.authorization
    }

    private func launchLoop() {
        guard startsRunLoop else { return }
        runTask = Task { @MainActor [engine] in await engine.runLoop() }
    }

    private func cancelLoop() {
        runTask?.cancel()
        runTask = nil
    }
}
