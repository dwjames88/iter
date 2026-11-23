import Testing
import IterGo
@testable import IterFeatures

@Suite("GoPermissions")
struct GoPermissionsTests {
    typealias L = LocationAuthorization
    typealias N = NotificationAuthorization

    private func step(_ l: L, _ n: N = .authorized, live: Bool = true, _ phase: GoPhase = .idle) -> GoPermissionStep? {
        GoPermissions(location: l, notifications: n, liveActivitiesEnabled: live, runPhase: phase).nextStep
    }

    @Test func locationFirst() {
        #expect(step(.notDetermined, .notDetermined) == .locationWhenInUse)
        #expect(step(.denied, .notDetermined) == .openSettings(for: .location))
        #expect(step(.restricted) == .openSettings(for: .location))
    }

    @Test func alwaysOnlyWhenARunIsStartingOrActive() {
        let always = GoPermissionStep.locationAlways(reason: "Always lets Iter notice when you arrive at a stop while your phone is locked.")
        #expect(step(.whenInUse, .authorized, .idle) == nil)
        #expect(step(.whenInUse, .authorized, .finished) == nil)
        for phase in [GoPhase.armed, .driving, .atStop, .betweenStops, .paused] { #expect(step(.whenInUse, .authorized, phase) == always) }
        #expect(step(.always, .authorized, .driving) == nil)
    }

    @Test func notificationsAfterLocation() {
        #expect(step(.always, .notDetermined) == .notifications)
        #expect(step(.always, .denied) == .openSettings(for: .notifications))
        #expect(step(.always, .provisional) == nil)
        #expect(step(.whenInUse, .notDetermined, .driving) == .locationAlways(reason: GoPermissions.alwaysReason))
    }

    @Test func liveActivitiesAreLast() {
        #expect(step(.always, .authorized, live: false) == .liveActivitiesOff)
        #expect(step(.always, .denied, live: false) == .openSettings(for: .notifications))
        #expect(step(.notDetermined, .authorized, live: false) == .locationWhenInUse)
    }
}
