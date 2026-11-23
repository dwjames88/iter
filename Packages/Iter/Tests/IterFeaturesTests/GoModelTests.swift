import Foundation
import Testing
import IterGo
import IterModel
@testable import IterFeatures

@MainActor
@Suite("GoModel")
struct GoModelTests {
    @Test func startAsksAlwaysOnlyFromWhenInUse() async throws {
        let whenInUse = try GoRig(location: .whenInUse)
        let m1 = whenInUse.model()
        await m1.start(whenInUse.world.input)
        #expect(whenInUse.location.authorizationRequests.contains(.always))
        #expect(!whenInUse.location.authorizationRequests.contains(.whenInUse))
        #expect(m1.permissions.nextStep == .locationAlways(reason: GoPermissions.alwaysReason))
        m1.stop()

        let always = try GoRig(location: .always)
        let m2 = always.model()
        await m2.start(always.world.input)
        #expect(always.location.authorizationRequests.isEmpty)
        #expect(m2.permissions.nextStep == nil)
        m2.stop()

        let fresh = try GoRig(location: .notDetermined, notifications: .notDetermined)
        let m3 = fresh.model()
        await m3.start(fresh.world.input)
        #expect(fresh.location.authorizationRequests.first == .whenInUse)
        #expect(fresh.notifications.calls.contains(.requestAuthorization))
        #expect(fresh.notifications.calls.contains(.registerCategories))
        m3.stop()
    }

    @Test func startDoesNotPromptNotificationsAlreadyAnswered() async throws {
        let rig = try GoRig(location: .always, notifications: .denied)
        let model = rig.model()
        await model.start(rig.world.input)
        #expect(!rig.notifications.calls.contains(.requestAuthorization))
        #expect(model.permissions.nextStep == .openSettings(for: .notifications))
        model.stop()
    }

    @Test func startPublishesTheSnapshotAndForwardsActions() async throws {
        let rig = try GoRig()
        let model = rig.model()
        let w = rig.world
        #expect(!model.isRunning)
        #expect(model.activeTripID == nil)
        await model.start(w.input)
        #expect(model.isRunning)
        #expect(model.activeTripID == w.trip.id)
        #expect(model.snapshot.phase == .armed)
        #expect(model.navigation?.name == "S1")
        #expect(model.lastError == nil)

        await model.leaveNow()
        #expect(model.snapshot.phase == .driving)
        #expect(model.snapshot.next?.id == w.stops[0].id)
        await model.arrived()
        #expect(model.snapshot.phase == .atStop)
        #expect(model.navigation?.name == "S2")
        await model.pause()
        #expect(model.snapshot.phase == .paused)
        await model.resume()
        #expect(model.snapshot.phase == .atStop)
        await model.doneHere()
        #expect(model.snapshot.phase == .betweenStops)
        await model.skip()
        #expect(model.snapshot.phase == .finished)
        #expect(rig.snapshotStore.read()?.phase == model.snapshot.phase)
        model.stop()
    }

    @Test func endFinishesAndClears() async throws {
        let rig = try GoRig()
        let model = rig.model()
        await model.start(rig.world.input)
        await model.leaveNow()
        #expect(model.isRunning)
        await model.end()
        #expect(model.snapshot.phase == .finished)
        #expect(!model.isRunning)
        #expect(model.activeTripID == nil)
        #expect(model.navigation == nil)
        #expect(model.pendingNavigation == nil)
        #expect(model.permissions.runPhase == .finished)
        #expect(rig.persistence.activeRun(tripID: rig.world.trip.id) == nil)
    }

    @Test func notificationActions() async throws {
        let rig = try GoRig()
        let model = rig.model()
        let w = rig.world
        await model.start(w.input)
        await model.leaveNow()

        await model.handleNotificationAction(identifier: GoNotificationCategory.navigateAction, userInfo: ["stopID": w.stops[1].id.uuidString])
        #expect(model.pendingNavigation?.name == "S2")
        #expect(model.pendingNavigation?.destination == w.stops[1].place.coordinate)
        model.consumeNavigation()
        #expect(model.pendingNavigation == nil)
        // No stop id: falls back to where Go is heading.
        await model.handleNotificationAction(identifier: GoNotificationCategory.navigateAction, userInfo: [:])
        #expect(model.pendingNavigation?.name == "S1")

        // "Not yet" undoes the last automatic transition; with none pending the run is left as it was.
        await model.handleNotificationAction(identifier: GoNotificationCategory.notYetAction, userInfo: [:])
        #expect(model.snapshot.phase == .driving)
        await model.handleNotificationAction(identifier: "something.else", userInfo: [:])
        #expect(model.pendingNavigation?.name == "S1")
        model.stop()
    }

    @Test func notYetUndoesAnAutomaticArrival() async throws {
        let rig = try GoRig()
        let model = GoModel(dependencies: rig.dependencies())   // the run loop is on: it ingests the location events
        let w = rig.world
        await model.start(w.input)
        await model.leaveNow()
        #expect(model.snapshot.phase == .driving)
        // Two slow fixes inside the geofence, 30 s apart: the engine arrives on its own.
        let at = w.stops[0].place.coordinate
        rig.location.send(.fix(LocationFix(coordinate: at, accuracyM: 5, speedMs: 0, timestamp: rig.clock.now)))
        rig.clock.advance(by: 30)
        rig.location.send(.fix(LocationFix(coordinate: at, accuracyM: 5, speedMs: 0, timestamp: rig.clock.now)))
        for _ in 0..<2000 where model.snapshot.phase != .atStop { await Task.yield() }
        #expect(model.snapshot.phase == .atStop)
        #expect(model.snapshot.undo != nil)
        await model.handleNotificationAction(identifier: GoNotificationCategory.notYetAction, userInfo: [:])
        #expect(model.snapshot.phase == .driving)
        model.stop()
    }

    @Test func restoreIfRunning() async throws {
        let rig = try GoRig()
        let w = rig.world
        let first = rig.model()
        #expect(await first.restoreIfRunning(w.input) == false)
        #expect(!first.isRunning)
        await first.start(w.input)
        await first.leaveNow()
        first.stop()

        let second = rig.model()
        #expect(!second.isRunning)
        #expect(await second.restoreIfRunning(w.input))
        #expect(second.isRunning)
        #expect(second.snapshot.phase == .driving)
        #expect(second.snapshot.runID == first.snapshot.runID)
        #expect(second.activeTripID == w.trip.id)
        second.stop()
    }

    @Test func emptyTripIsAnError() async throws {
        let rig = try GoRig()
        let model = rig.model()
        var input = rig.world.input
        input.trip.stops = []
        await model.start(input)
        #expect(model.lastError != nil)
        #expect(!model.isRunning)
    }

    @Test func permissionRequestsAndRefresh() async throws {
        let rig = try GoRig(location: .notDetermined, notifications: .notDetermined)
        let model = rig.model()
        await model.refreshPermissions()
        #expect(model.permissions.nextStep == .locationWhenInUse)
        model.requestLocationWhenInUse()
        model.requestLocationAlways()
        #expect(rig.location.authorizationRequests == [.whenInUse, .always])
        await model.requestNotifications()
        #expect(rig.notifications.authorizationState == .authorized)
        rig.activity.areActivitiesEnabled = false
        rig.location.grantOnRequest = true
        rig.location.setAuthorization(.always)
        await model.refreshPermissions()
        #expect(model.permissions.nextStep == .liveActivitiesOff)
    }

    @Test func runLoopStartsAndStops() async throws {
        let rig = try GoRig()
        let model = GoModel(dependencies: rig.dependencies())
        await model.start(rig.world.input)
        #expect(model.isRunning)
        model.stop()
        #expect(model.isRunning)   // stopping observation does not end the run
        let relaunched = rig.model()
        #expect(await relaunched.restoreIfRunning(rig.world.input))
        relaunched.stop()
    }
}
