import Foundation
import Testing
import IterGo
import IterModel
import IterPlan

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let trip = UUID()
private let mesa = UUID()
private let arch2 = UUID()
private let utc = TimeZone(identifier: "UTC")!

private func alarm(_ stop: UUID, _ kind: AlarmKind, at: Date, leaveBy: Date, name: String = "Mesa Arch", drive: TimeInterval = 2880) -> PlannedAlarm {
    makeAlarm(stop, kind, at: at, leaveBy: leaveBy, name: name, drive: drive)
}

private func facts(_ id: UUID = mesa, status: GoLeaveStatus = .early, leaveBy: Date? = nil, late: TimeInterval? = nil, alt: String? = nil) -> NotificationStopFacts {
    NotificationStopFacts(stopID: id, name: "Mesa Arch", status: status, leaveBy: leaveBy, lateBySeconds: late, windowKind: .goldenEvening,
                          windowStart: t0.addingTimeInterval(7200), driveSeconds: 2880, alternativeName: alt, timeZone: utc,
                          projectedArrival: t0.addingTimeInterval(3000), setUpBy: t0.addingTimeInterval(2500))
}

private func input(now: Date = t0, phase: GoPhase = .armed, alarms: [PlannedAlarm] = [], next: NotificationStopFacts? = nil, stay: GoStayInfo? = nil,
                   target: UUID? = nil, conditions: [ConditionsAlertNotice] = [], arrival: ArrivalNotice? = nil) -> NotificationPlanInput {
    NotificationPlanInput(now: now, tripID: trip, tripName: "Utah", phase: phase, alarms: alarms, nextStop: next, stay: stay, targetStopID: target,
                          conditionsAlerts: conditions, arrival: arrival, timeZones: [mesa: utc, arch2: utc])
}

private func standardAlarms(leaveBy: Date) -> [PlannedAlarm] {
    [alarm(mesa, .leaveSoon, at: leaveBy.addingTimeInterval(-900), leaveBy: leaveBy), alarm(mesa, .leaveNow, at: leaveBy, leaveBy: leaveBy)]
}

@Test func alarmIdsMatchAlarmPlan() {
    #expect(GoNotificationKind.leaveSoon.id(for: mesa) == AlarmPlan.id(for: mesa, kind: .leaveSoon))
    #expect(GoNotificationKind.leaveNow.id(for: mesa) == AlarmPlan.id(for: mesa, kind: .leaveNow))
    #expect(GoNotificationKind.kind(ofID: GoNotificationKind.stayCheck.id(for: mesa)) == .stayCheck)
}

@Test func futureAlarmsBecomePendingWithText() {
    let leaveBy = t0.addingTimeInterval(3600)
    let plan = NotificationPlanner.plan(input(alarms: standardAlarms(leaveBy: leaveBy)), ledger: NotificationLedger())
    #expect(plan.pending.map(\.id) == [AlarmPlan.id(for: mesa, kind: .leaveSoon), AlarmPlan.id(for: mesa, kind: .leaveNow)])
    let soon = plan.pending[0], now = plan.pending[1]
    #expect(soon.body.hasPrefix("Leave by "))
    #expect(soon.body.contains("for Mesa Arch: 48 min drive, sunset "))
    #expect(soon.categoryID == GoNotificationCategory.info)
    #expect(now.categoryID == GoNotificationCategory.navigate)
    #expect(now.threadID == trip.uuidString)
    #expect(plan.immediate.isEmpty)
    #expect(plan.ledger.scheduled.count == 2)
}

@Test func textUsesStopZoneAndRoundsDrive() {
    let leaveBy = Date(timeIntervalSince1970: 1_800_000_000 + 3600) // 09:20 UTC -> 02:20 in Denver? check via explicit zone
    var a = standardAlarms(leaveBy: leaveBy)
    a[0] = alarm(mesa, .leaveSoon, at: leaveBy.addingTimeInterval(-900), leaveBy: leaveBy, drive: 2880 + 20)
    var inp = input(alarms: a)
    inp.timeZones[mesa] = TimeZone(identifier: "Asia/Tokyo")!
    let body = NotificationPlanner.plan(inp, ledger: NotificationLedger()).pending[0].body
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Tokyo"); f.dateFormat = "HH:mm"
    #expect(body.contains(f.string(from: leaveBy)))
    #expect(body.contains("48 min drive"))
}

@Test func idlePausedFinishedPlanNothing() {
    let leaveBy = t0.addingTimeInterval(3600)
    var ledger = NotificationLedger(scheduled: ["x-leaveNow": .init(fireAt: leaveBy, contentHash: "h")], delivered: ["y-late": t0])
    for phase in [GoPhase.idle, .paused, .finished] {
        let plan = NotificationPlanner.plan(input(phase: phase, alarms: standardAlarms(leaveBy: leaveBy), next: facts(status: .late, late: 900)), ledger: ledger)
        #expect(plan.pending.isEmpty && plan.immediate.isEmpty && plan.removeAll)
        #expect(plan.ledger.scheduled.isEmpty)
    }
    ledger = NotificationPlanner.plan(input(phase: .paused), ledger: ledger).ledger
    #expect(ledger.delivered["y-late"] != nil)
    #expect(NotificationPlanner.plan(input(phase: .finished), ledger: ledger).ledger.delivered.isEmpty)
}

@Test func dropsAlarmsForStopBeingDrivenTo() {
    let leaveBy = t0.addingTimeInterval(3600)
    let alarms = standardAlarms(leaveBy: leaveBy) + [alarm(arch2, .leaveSoon, at: t0.addingTimeInterval(9000), leaveBy: t0.addingTimeInterval(9900), name: "Other")]
    let plan = NotificationPlanner.plan(input(phase: .driving, alarms: alarms, next: facts(), target: mesa), ledger: NotificationLedger())
    #expect(plan.pending.map(\.stopID) == [arch2])
}

@Test func capsAtFiftyEarliest() {
    let alarms = (0..<70).map { i in alarm(UUID(), .leaveNow, at: t0.addingTimeInterval(Double(i + 1) * 100), leaveBy: t0.addingTimeInterval(Double(i + 1) * 100)) }
    let plan = NotificationPlanner.plan(input(alarms: alarms.reversed()), ledger: NotificationLedger())
    #expect(plan.pending.count == 50)
    #expect(plan.pending.last?.fireAt == t0.addingTimeInterval(5000))
}

@Test func leaveByMovingEarlierReplacesWithSameId() {
    let first = NotificationPlanner.plan(input(alarms: standardAlarms(leaveBy: t0.addingTimeInterval(3600))), ledger: NotificationLedger())
    let second = NotificationPlanner.plan(input(now: t0.addingTimeInterval(60), alarms: standardAlarms(leaveBy: t0.addingTimeInterval(3000))), ledger: first.ledger)
    #expect(second.pending.map(\.id) == first.pending.map(\.id))
    #expect(second.pending[1].fireAt == t0.addingTimeInterval(3000))
    #expect(second.ledger.scheduled[second.pending[1].id]?.fireAt == t0.addingTimeInterval(3000))
}

@Test func smallMovesKeepPendingUntouched() {
    let first = NotificationPlanner.plan(input(alarms: standardAlarms(leaveBy: t0.addingTimeInterval(3600 + 5))), ledger: NotificationLedger())
    let second = NotificationPlanner.plan(input(now: t0.addingTimeInterval(30), alarms: standardAlarms(leaveBy: t0.addingTimeInterval(3600 + 5 + 30))), ledger: first.ledger)
    #expect(second.pending[1].fireAt == first.pending[1].fireAt)
}

@Test func leaveByIntoThePastGivesOneImmediateLeaveNow() {
    let n = facts(status: .leaveNow, leaveBy: t0.addingTimeInterval(-120))
    let first = NotificationPlanner.plan(input(phase: .betweenStops, next: n), ledger: NotificationLedger())
    #expect(first.immediate.map(\.id) == [AlarmPlan.id(for: mesa, kind: .leaveNow)])
    #expect(first.immediate[0].fireAt == nil)
    #expect(first.immediate[0].body.hasPrefix("Leave now for Mesa Arch: 48 min drive"))
    let again = NotificationPlanner.plan(input(now: t0.addingTimeInterval(600), phase: .betweenStops, next: n), ledger: first.ledger)
    #expect(again.immediate.isEmpty)
}

@Test func noImmediateLeaveNowWhenAlarmStillAhead() {
    let n = facts(status: .leaveNow, leaveBy: t0.addingTimeInterval(30))
    let plan = NotificationPlanner.plan(input(phase: .betweenStops, alarms: [alarm(mesa, .leaveNow, at: t0.addingTimeInterval(30), leaveBy: t0.addingTimeInterval(30))], next: n), ledger: NotificationLedger())
    #expect(plan.immediate.isEmpty)
}

@Test func firedScheduledLeaveNowCountsAsDelivered() {
    let first = NotificationPlanner.plan(input(alarms: standardAlarms(leaveBy: t0.addingTimeInterval(600))), ledger: NotificationLedger())
    let later = NotificationPlanner.plan(input(now: t0.addingTimeInterval(700), phase: .betweenStops, next: facts(status: .leaveNow)), ledger: first.ledger)
    #expect(later.immediate.isEmpty)
    #expect(later.pending.isEmpty)
}

@Test func noLeaveNowWhileDrivingToIt() {
    let plan = NotificationPlanner.plan(input(phase: .driving, next: facts(status: .leaveNow), target: mesa), ledger: NotificationLedger())
    #expect(plan.immediate.isEmpty)
}

@Test func lateFiresOnceEvenWhileDrivingAndIncludesAlternative() {
    let n = facts(status: .late, late: 8 * 60, alt: "Delicate Arch")
    let first = NotificationPlanner.plan(input(phase: .driving, next: n, target: mesa), ledger: NotificationLedger())
    #expect(first.immediate.count == 1)
    let body = first.immediate[0].body
    #expect(body.hasPrefix("Running 8 min late for Mesa Arch: arrive "))
    #expect(body.contains("set-up "))
    #expect(body.contains("Delicate Arch"))
    #expect(first.immediate[0].categoryID == GoNotificationCategory.navigate)
    let again = NotificationPlanner.plan(input(now: t0.addingTimeInterval(300), phase: .driving, next: n, target: mesa), ledger: first.ledger)
    #expect(again.immediate.isEmpty)
}

@Test func lateUnderFiveMinutesIsQuiet() {
    let plan = NotificationPlanner.plan(input(phase: .driving, next: facts(status: .late, late: 200), target: mesa), ledger: NotificationLedger())
    #expect(plan.immediate.isEmpty)
}

@Test func missedFiresOnceWithAlternative() {
    let n = facts(status: .missed, alt: "Delicate Arch")
    let first = NotificationPlanner.plan(input(phase: .betweenStops, next: n), ledger: NotificationLedger())
    #expect(first.immediate.first?.kind == .missed)
    #expect(first.immediate.first?.body.contains("Delicate Arch") == true)
    #expect(NotificationPlanner.plan(input(now: t0.addingTimeInterval(500), phase: .betweenStops, next: n), ledger: first.ledger).immediate.isEmpty)
}

private func conflictStay(latest: Date, planned: Date) -> GoStayInfo {
    GoStayInfo(plannedDeparture: planned, latestDeparture: latest, cutsShortBySeconds: 12 * 60, nextStopName: "Mesa Arch", nextWindowKind: .blueEvening)
}

@Test func stayConflictSchedulesOneStayCheckAndSuppressesNext() {
    let latest = t0.addingTimeInterval(3600)
    let alarms = standardAlarms(leaveBy: latest)
    let n = facts(status: .late, late: 900)
    let plan = NotificationPlanner.plan(input(phase: .atStop, alarms: alarms, next: n, stay: conflictStay(latest: latest, planned: latest.addingTimeInterval(720))), ledger: NotificationLedger())
    #expect(plan.pending.map(\.kind) == [.stayCheck])
    #expect(plan.pending[0].fireAt == latest.addingTimeInterval(-900))
    #expect(plan.pending[0].body.hasPrefix("Leave by "))
    #expect(plan.pending[0].body.contains("to make blue hour at Mesa Arch: 12 min before this window ends."))
    #expect(plan.immediate.isEmpty)
}

@Test func stayCheckImmediateWhenLeadPassedButNotRepeated() {
    let latest = t0.addingTimeInterval(600)
    let stay = conflictStay(latest: latest, planned: latest.addingTimeInterval(720))
    let first = NotificationPlanner.plan(input(phase: .atStop, next: facts(), stay: stay), ledger: NotificationLedger())
    #expect(first.immediate.map(\.kind) == [.stayCheck])
    #expect(first.pending.isEmpty)
    let again = NotificationPlanner.plan(input(now: t0.addingTimeInterval(200), phase: .atStop, next: facts(), stay: stay), ledger: first.ledger)
    #expect(again.immediate.isEmpty && again.pending.isEmpty)
}

@Test func stayCheckSilentOncePastLatestDeparture() {
    let stay = conflictStay(latest: t0.addingTimeInterval(-60), planned: t0.addingTimeInterval(600))
    let plan = NotificationPlanner.plan(input(phase: .atStop, next: facts(), stay: stay), ledger: NotificationLedger())
    #expect(plan.immediate.isEmpty && plan.pending.isEmpty)
}

@Test func firedStayCheckIsNotRepeated() {
    let latest = t0.addingTimeInterval(3600)
    let stay = conflictStay(latest: latest, planned: latest.addingTimeInterval(720))
    let first = NotificationPlanner.plan(input(phase: .atStop, next: facts(), stay: stay), ledger: NotificationLedger())
    let fired = NotificationPlanner.plan(input(now: latest.addingTimeInterval(-600), phase: .atStop, next: facts(), stay: stay), ledger: first.ledger)
    #expect(fired.immediate.isEmpty && fired.pending.isEmpty)
}

@Test func noConflictKeepsNormalAlarmsAtStop() {
    let stay = GoStayInfo(plannedDeparture: t0, latestDeparture: t0.addingTimeInterval(3600), cutsShortBySeconds: nil, nextStopName: "Mesa Arch", nextWindowKind: nil)
    let plan = NotificationPlanner.plan(input(phase: .atStop, alarms: standardAlarms(leaveBy: t0.addingTimeInterval(3600)), next: facts(), stay: stay), ledger: NotificationLedger())
    #expect(plan.pending.count == 2)
    #expect(plan.pending.allSatisfy { $0.kind != .stayCheck })
}

private func notice(_ stop: UUID = mesa, was: Int = 45, now: Int = 72) -> ConditionsAlertNotice {
    ConditionsAlertNotice(stopID: stop, stopName: "Mesa Arch", windowKind: .goldenEvening, previous: was, current: now, cause: "high cloud moving in")
}

@Test func conditionsTextAndHourlyCap() {
    let first = NotificationPlanner.plan(input(phase: .driving, conditions: [notice()]), ledger: NotificationLedger())
    #expect(first.immediate.first?.body == "Sunset at Mesa Arch now 72 (was 45): high cloud moving in")
    let soon = NotificationPlanner.plan(input(now: t0.addingTimeInterval(1800), phase: .driving, conditions: [notice()]), ledger: first.ledger)
    #expect(soon.immediate.isEmpty)
    let later = NotificationPlanner.plan(input(now: t0.addingTimeInterval(3601), phase: .driving, conditions: [notice()]), ledger: first.ledger)
    #expect(later.immediate.count == 1)
    let other = NotificationPlanner.plan(input(now: t0.addingTimeInterval(1800), phase: .driving, conditions: [notice(arch2)]), ledger: first.ledger)
    #expect(other.immediate.count == 1)
}

@Test func arrivalImmediateWithNotYetCategory() {
    let exp = t0.addingTimeInterval(120)
    let plan = NotificationPlanner.plan(input(phase: .atStop, arrival: ArrivalNotice(stopID: mesa, stopName: "Mesa Arch", undoExpiresAt: exp)), ledger: NotificationLedger())
    #expect(plan.immediate.first?.kind == .arrival)
    #expect(plan.immediate.first?.categoryID == GoNotificationCategory.arrival)
    #expect(plan.immediate.first?.userInfo["undoExpiresAt"] != nil)
}

@Test func ninetySecondGapAndFold() {
    let n = facts(status: .late, late: 600)
    let all = input(phase: .atStop, next: n, conditions: [notice()], arrival: ArrivalNotice(stopID: arch2, stopName: "Arch Two"))
    let first = NotificationPlanner.plan(all, ledger: NotificationLedger())
    #expect(first.immediate.count == 1)
    #expect(first.immediate[0].kind == .arrival)
    #expect(first.immediate[0].body.contains("\n"))
    #expect(first.immediate[0].body.contains("late for Mesa Arch"))
    #expect(first.immediate[0].body.contains("Mesa Arch now 72"))
    // The folded ones count as delivered.
    let after = NotificationPlanner.plan(input(now: t0.addingTimeInterval(200), phase: .atStop, next: n, conditions: [notice()]), ledger: first.ledger)
    #expect(after.immediate.isEmpty)

    // A new one inside 90 s waits; after 90 s it goes.
    let solo = NotificationPlanner.plan(input(phase: .driving, conditions: [notice()]), ledger: NotificationLedger())
    let blocked = NotificationPlanner.plan(input(now: t0.addingTimeInterval(60), phase: .driving, next: facts(status: .missed), conditions: []), ledger: solo.ledger)
    #expect(blocked.immediate.isEmpty)
    let open = NotificationPlanner.plan(input(now: t0.addingTimeInterval(91), phase: .driving, next: facts(status: .missed)), ledger: blocked.ledger)
    #expect(open.immediate.first?.kind == .missed)
}

@Test func atStopConflictSuppressesLate() {
    let stay = conflictStay(latest: t0.addingTimeInterval(3600), planned: t0.addingTimeInterval(4300))
    let plan = NotificationPlanner.plan(input(phase: .atStop, next: facts(status: .late, late: 900), stay: stay), ledger: NotificationLedger())
    #expect(plan.immediate.isEmpty)
}

@Test func ledgerRoundTripsAsJSON() throws {
    let plan = NotificationPlanner.plan(input(alarms: standardAlarms(leaveBy: t0.addingTimeInterval(3600)), conditions: [notice()]), ledger: NotificationLedger())
    let data = try JSONEncoder().encode(plan.ledger)
    #expect(try JSONDecoder().decode(NotificationLedger.self, from: data) == plan.ledger)
}
