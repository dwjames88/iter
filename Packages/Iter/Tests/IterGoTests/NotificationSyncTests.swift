import Foundation
import Testing
import IterGo
import IterModel
import IterPlan

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let trip = UUID()
private let a = UUID()
private let b = UUID()
private let utc = TimeZone(identifier: "UTC")!

private func alarm(_ stop: UUID, _ kind: AlarmKind, at: Date, leaveBy: Date) -> PlannedAlarm {
    makeAlarm(stop, kind, at: at, leaveBy: leaveBy, name: "Stop", drive: 1800)
}

private func input(now: Date = t0, phase: GoPhase = .armed, alarms: [PlannedAlarm], next: NotificationStopFacts? = nil) -> NotificationPlanInput {
    NotificationPlanInput(now: now, tripID: trip, tripName: "T", phase: phase, alarms: alarms, nextStop: next, timeZones: [a: utc, b: utc])
}

@Test func syncAddsThenKeepsThenReplacesThenRemoves() async {
    let fake = FakeNotificationScheduler()
    let sync = NotificationSync(scheduler: fake)
    let lb = t0.addingTimeInterval(3600)
    let both = [alarm(a, .leaveSoon, at: lb.addingTimeInterval(-900), leaveBy: lb), alarm(a, .leaveNow, at: lb, leaveBy: lb)]

    let r1 = await sync.sync(input(alarms: both))
    #expect(Set(r1.added) == Set(both.map(\.id)))
    #expect(fake.pending.count == 2)

    let r2 = await sync.sync(input(now: t0.addingTimeInterval(10), alarms: both))
    #expect(r2.added.isEmpty && r2.removed.isEmpty && r2.kept.count == 2)

    let earlier = lb.addingTimeInterval(-600)
    let moved = [alarm(a, .leaveSoon, at: earlier.addingTimeInterval(-900), leaveBy: earlier), alarm(a, .leaveNow, at: earlier, leaveBy: earlier)]
    let r3 = await sync.sync(input(now: t0.addingTimeInterval(20), alarms: moved))
    #expect(Set(r3.added) == Set(moved.map(\.id)))
    #expect(fake.pending.count == 2)
    #expect(fake.pending[moved[1].id]?.fireAt == earlier)

    let r4 = await sync.sync(input(now: t0.addingTimeInterval(30), alarms: [moved[1]]))
    #expect(r4.removed == [moved[0].id])
    #expect(fake.pending.count == 1)
}

@Test func syncPausedRemovesEverything() async {
    let fake = FakeNotificationScheduler()
    let sync = NotificationSync(scheduler: fake)
    let lb = t0.addingTimeInterval(3600)
    await sync.sync(input(alarms: [alarm(a, .leaveNow, at: lb, leaveBy: lb)]))
    let r = await sync.sync(input(phase: .paused, alarms: [alarm(a, .leaveNow, at: lb, leaveBy: lb)]))
    #expect(r.removedAll)
    #expect(fake.pending.isEmpty)
    #expect(fake.calls.contains(.removeAllPending))
}

@Test func syncReaddsWhatTheSystemDropped() async {
    let fake = FakeNotificationScheduler()
    let sync = NotificationSync(scheduler: fake)
    let lb = t0.addingTimeInterval(3600)
    let al = [alarm(a, .leaveNow, at: lb, leaveBy: lb)]
    await sync.sync(input(alarms: al))
    await fake.removeAllPending()
    let r = await sync.sync(input(now: t0.addingTimeInterval(5), alarms: al))
    #expect(r.added == [al[0].id])
}

@Test func syncDeliversImmediatesInOrderAfterScheduling() async {
    let fake = FakeNotificationScheduler()
    let sync = NotificationSync(scheduler: fake)
    let lb = t0.addingTimeInterval(3600)
    let n = NotificationStopFacts(stopID: b, name: "B", status: .missed, timeZone: utc)
    let r = await sync.sync(input(phase: .betweenStops, alarms: [alarm(a, .leaveNow, at: lb, leaveBy: lb)], next: n))
    #expect(r.delivered == [GoNotificationKind.missed.id(for: b)])
    #expect(fake.delivered.count == 1)
    guard case .add(let first) = fake.calls.first, case .add(let last) = fake.calls.last else { Issue.record("calls"); return }
    #expect(first.fireAt != nil && last.fireAt == nil)
    // A repeat plan does not deliver again.
    let again = await sync.sync(input(now: t0.addingTimeInterval(300), phase: .betweenStops, alarms: [alarm(a, .leaveNow, at: lb, leaveBy: lb)], next: n))
    #expect(again.delivered.isEmpty)
}

@Test func syncDoesNothingWhenDenied() async {
    let fake = FakeNotificationScheduler(authorization: .denied)
    let sync = NotificationSync(scheduler: fake)
    let lb = t0.addingTimeInterval(3600)
    let r = await sync.sync(input(alarms: [alarm(a, .leaveNow, at: lb, leaveBy: lb)]))
    #expect(r.skippedDenied)
    #expect(fake.calls.isEmpty)
}

@Test func syncRecordsFailuresAndRetries() async {
    let fake = FakeNotificationScheduler()
    let lb = t0.addingTimeInterval(3600)
    let al = alarm(a, .leaveNow, at: lb, leaveBy: lb)
    fake.failingIDs = [al.id]
    let sync = NotificationSync(scheduler: fake)
    let r1 = await sync.sync(input(alarms: [al]))
    #expect(r1.failed == [al.id])
    fake.failingIDs = []
    let r2 = await sync.sync(input(now: t0.addingTimeInterval(5), alarms: [al]))
    #expect(r2.added == [al.id])
}
