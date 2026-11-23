import Foundation
import Testing
import IterModel
import IterGo
import IterGoActivity
import IterFeatures
@testable import IterScreens

@Suite("Go flow logic")
struct GoFlowTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-24T22:30:00Z")!
    static let denver = "America/Denver"

    static func stop(_ n: Int, day: Int, name: String = "Stop") -> GoStopInfo {
        GoStopInfo(id: UUID(), number: n, name: "\(name) \(n)", kind: .light, dayIndex: day,
                   coordinate: Coordinate(latitude: 38.5, longitude: -109.5), timeZoneIdentifier: denver,
                   windowKind: .goldenEvening, windowStart: now.addingTimeInterval(3600))
    }

    @Test func screenPerPhase() {
        #expect(GoFlow.screen(for: .idle) == .start)
        #expect(GoFlow.screen(for: .finished) == .finished)
        #expect(GoFlow.screen(for: .finished, finishedDismissed: true) == .start)
        for phase in [GoPhase.armed, .driving, .atStop, .betweenStops, .paused] { #expect(GoFlow.screen(for: phase) == .running) }
    }

    @Test func permissionRowPlacementAndWords() {
        // Idle with everything granted shows nothing; denied location shows the Settings row.
        #expect(GoPermissions(location: .always, notifications: .authorized, runPhase: .idle).nextStep == nil)
        let denied = GoPermissions(location: .denied, notifications: .authorized, runPhase: .idle).nextStep
        #expect(denied == .openSettings(for: .location))
        #expect(GoFlow.permissionCopy(denied!).action == .openSettings)
        // Location not asked leads; everything else waits below the hero.
        #expect(GoFlow.permissionPlacement(.locationWhenInUse) == .aboveHero)
        #expect(GoFlow.permissionPlacement(.notifications) == .belowHero)
        #expect(GoFlow.permissionPlacement(.liveActivitiesOff) == .belowHero)
        // When In Use while driving asks for Always with the shared reason.
        let always = GoPermissions(location: .whenInUse, notifications: .authorized, runPhase: .driving).nextStep
        #expect(always == .locationAlways(reason: GoPermissions.alwaysReason))
        #expect(GoFlow.permissionCopy(always!).sentence == GoPermissions.alwaysReason)
        #expect(GoFlow.permissionCopy(always!).action == .allowAlways)
        // Every step has one sentence and one button.
        let steps: [GoPermissionStep] = [.locationWhenInUse, .locationAlways(reason: "r"), .notifications, .openSettings(for: .location),
                                         .openSettings(for: .notifications), .liveActivitiesOff]
        for step in steps {
            let copy = GoFlow.permissionCopy(step)
            #expect(!copy.sentence.isEmpty && !copy.button.isEmpty && !copy.symbol.isEmpty)
        }
    }

    @Test func undoVisibility() {
        let live = GoUndoInfo(toPhase: .atStop, stopID: nil, stopName: "Mesa Arch", expiresAt: Self.now.addingTimeInterval(100))
        #expect(GoFlow.undoIsVisible(live, now: Self.now))
        #expect(!GoFlow.undoIsVisible(live, now: Self.now.addingTimeInterval(100)))
        #expect(!GoFlow.undoIsVisible(live, now: Self.now.addingTimeInterval(500)))
        #expect(!GoFlow.undoIsVisible(nil, now: Self.now))
        #expect(GoFlow.undoSecondsLeft(live, now: Self.now) == 100)
        #expect(GoFlow.undoSecondsLeft(live, now: Self.now.addingTimeInterval(500)) == 0)
        #expect(GoFlow.clockText(seconds: 100) == "1:40")
        #expect(GoFlow.clockText(seconds: 5) == "0:05")
        #expect(GoFlow.undoSentence(live) == "Arrived at Mesa Arch")
    }

    @Test func scheduleGroupsByDay() {
        let items = [GoScheduleItem(stop: Self.stop(1, day: 0)), GoScheduleItem(stop: Self.stop(2, day: 0)),
                     GoScheduleItem(stop: Self.stop(3, day: 1)), GoScheduleItem(stop: Self.stop(4, day: 2))]
        let days = GoFlow.groupByDay(items)
        #expect(days.map(\.dayIndex) == [0, 1, 2])
        #expect(days.map { $0.items.count } == [2, 1, 1])
        #expect(GoFlow.groupByDay([]).isEmpty)
    }

    @Test func scheduleFallsBackToNext() {
        var snapshot = GoSnapshot.idle(at: Self.now)
        #expect(GoFlow.scheduleItems(snapshot).isEmpty)
        snapshot.next = Self.stop(2, day: 0)
        snapshot.leave = GoLeaveInfo(leaveBy: Self.now, status: .late)
        let items = GoFlow.scheduleItems(snapshot)
        #expect(items.count == 1 && items[0].status == .late && items[0].leaveBy == Self.now)
        snapshot.schedule = [GoScheduleItem(stop: Self.stop(2, day: 0)), GoScheduleItem(stop: Self.stop(3, day: 0))]
        #expect(GoFlow.scheduleItems(snapshot).count == 2)
    }

    @Test func dayHeadings() {
        let items = [GoScheduleItem(stop: Self.stop(1, day: 0)), GoScheduleItem(stop: Self.stop(2, day: 1))]
        let days = GoFlow.groupByDay(items)
        let en = Locale(identifier: "en_US")
        #expect(GoFlow.dayHeading(group: days[0], first: days[0], now: Self.now, locale: en) == "Today")
        #expect(GoFlow.dayHeading(group: days[1], first: days[0], now: Self.now, locale: en) == "Tomorrow")
    }

    @Test func tripStartChoices() {
        let trip = GoTripChoice(id: UUID(), name: "T", startDay: LocalDay(year: 2026, month: 10, day: 14), dayCount: 2, stops: [
            .init(id: UUID(), number: 2, name: "B", dayIndex: 0, windowKind: nil),
            .init(id: UUID(), number: 1, name: "A", dayIndex: 0, windowKind: nil),
            .init(id: UUID(), number: 3, name: "C", dayIndex: 1, windowKind: nil),
        ])
        let days = GoFlow.stopsByDay(trip)
        #expect(days.map(\.dayIndex) == [0, 1])
        #expect(days[0].stops.map(\.name) == ["A", "B"])
        let first = trip.stops.first { $0.number == 1 }!.id
        let third = trip.stops.first { $0.number == 3 }!.id
        #expect(GoFlow.startStopID(selected: nil, in: trip) == nil)
        #expect(GoFlow.startStopID(selected: first, in: trip) == nil)
        #expect(GoFlow.startStopID(selected: third, in: trip) == third)
        #expect(GoFlow.dateSpan(trip, locale: Locale(identifier: "en_US")) == "Wed, Oct 14 – Thu, Oct 15")
    }
}
