import Foundation
import Testing
import IterGo

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func backgroundIdentifierIsFixed() {
    #expect(GoBackground.refreshTaskIdentifier == "com.dwjames.iter.go.refresh")
}

@Test func backgroundNextRefreshRules() {
    // Nothing ahead, or already past: no request.
    #expect(GoBackground.nextRefresh(now: t0, leaveBy: nil) == nil)
    #expect(GoBackground.nextRefresh(now: t0, leaveBy: t0.addingTimeInterval(-10)) == nil)
    // Far ahead: just before the leave-soon time.
    let far = t0.addingTimeInterval(6 * 3600)
    #expect(GoBackground.nextRefresh(now: t0, leaveBy: far) == far.addingTimeInterval(-16 * 60))
    // Within two hours: every 30 minutes, but not later than before leave-soon.
    let near = t0.addingTimeInterval(100 * 60)
    #expect(GoBackground.nextRefresh(now: t0, leaveBy: near) == t0.addingTimeInterval(30 * 60))
    let close = t0.addingTimeInterval(40 * 60)
    #expect(GoBackground.nextRefresh(now: t0, leaveBy: close) == close.addingTimeInterval(-16 * 60))
    // Inside the leave-soon lead: soon, not never.
    let imminent = t0.addingTimeInterval(10 * 60)
    let d = GoBackground.nextRefresh(now: t0, leaveBy: imminent)
    #expect(d != nil && d! > t0 && d! < imminent)
}

@Test func fakeBackgroundSchedulerRecords() {
    let fake = FakeBackgroundScheduler()
    fake.scheduleRefresh(earliest: t0)
    fake.scheduleRefresh(earliest: t0.addingTimeInterval(60))
    fake.cancel()
    #expect(fake.calls == [.schedule(t0), .schedule(t0.addingTimeInterval(60)), .cancel])
    #expect(fake.lastRequest == t0.addingTimeInterval(60))
}
