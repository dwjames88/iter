import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let trip = UUID()
private let stopA = UUID()
private let stopB = UUID()

private func stop(_ id: UUID, _ name: String = "Mesa Arch") -> GoStopInfo {
    GoStopInfo(id: id, number: 1, name: name, kind: .light, dayIndex: 0, coordinate: Coordinate(latitude: 38.6, longitude: -109.6),
               timeZoneIdentifier: "UTC", windowKind: .goldenEvening, windowStart: t0.addingTimeInterval(9000))
}

private func snap(_ phase: GoPhase = .driving, at: Date = t0, next: UUID? = stopA, status: GoLeaveStatus = .early, leaveBy: Date? = nil,
                  nextRefresh: Date? = nil, arrival: Date? = nil, undo: Bool = false, power: Bool = false) -> GoSnapshot {
    GoSnapshot(generatedAt: at, tripID: trip, tripName: "Utah", runID: UUID(), phase: phase, next: next.map { stop($0) },
               leave: GoLeaveInfo(leaveBy: leaveBy, status: status), drive: arrival.map { GoDriveInfo(arrival: $0, driveSeconds: 1800, driveMeters: nil, source: .live, asOf: at) },
               freshness: GoFreshness(isPowerSaving: power, nextRefreshAt: nextRefresh),
               undo: undo ? GoUndoInfo(toPhase: phase, stopID: nil, stopName: nil, expiresAt: at.addingTimeInterval(120)) : nil)
}

// MARK: policy

@Test func staleDateRules() {
    #expect(GoActivityPolicy.staleDate(for: snap(nextRefresh: t0.addingTimeInterval(120))) == t0.addingTimeInterval(120 + 900))
    #expect(GoActivityPolicy.staleDate(for: snap()) == t0.addingTimeInterval(1800))
}

@Test func startRules() {
    #expect(GoActivityPolicy.shouldStart(snap(.armed, leaveBy: t0.addingTimeInterval(7 * 3600)), now: t0))
    #expect(!GoActivityPolicy.shouldStart(snap(.armed, leaveBy: t0.addingTimeInterval(9 * 3600)), now: t0))
    #expect(!GoActivityPolicy.shouldStart(snap(.armed, leaveBy: nil), now: t0))
    for phase in [GoPhase.driving, .atStop, .betweenStops] { #expect(GoActivityPolicy.shouldStart(snap(phase), now: t0)) }
    for phase in [GoPhase.idle, .paused, .finished] { #expect(!GoActivityPolicy.shouldStart(snap(phase), now: t0)) }
    #expect(GoActivityPolicy.shouldEnd(snap(.finished)) && !GoActivityPolicy.shouldEnd(snap(.driving)))
}

@Test func throttleAndImmediateTriggers() {
    let base = GoActivityMarker(snapshot: snap(.driving, status: .early))
    #expect(!GoActivityPolicy.shouldUpdate(previous: base, current: base, lastUpdateAt: t0, now: t0.addingTimeInterval(59), powerSaving: false))
    #expect(GoActivityPolicy.shouldUpdate(previous: base, current: base, lastUpdateAt: t0, now: t0.addingTimeInterval(60), powerSaving: false))
    #expect(!GoActivityPolicy.shouldUpdate(previous: base, current: base, lastUpdateAt: t0, now: t0.addingTimeInterval(299), powerSaving: true))
    #expect(GoActivityPolicy.shouldUpdate(previous: base, current: base, lastUpdateAt: t0, now: t0.addingTimeInterval(300), powerSaving: true))
    for changed in [snap(.atStop), snap(.driving, status: .late), snap(.driving, next: stopB), snap(.driving, undo: true)] {
        #expect(GoActivityPolicy.shouldUpdate(previous: base, current: GoActivityMarker(snapshot: changed), lastUpdateAt: t0, now: t0.addingTimeInterval(1), powerSaving: true))
    }
}

// MARK: coordinator

@MainActor
private func rig() -> (LiveActivityCoordinator, FakeLiveActivityController) {
    let fake = FakeLiveActivityController()
    return (LiveActivityCoordinator(controller: fake), fake)
}

@MainActor @Test func coordinatorFullRunSequence() async {
    let (c, fake) = rig()
    // Armed far out: nothing.
    await c.apply(snapshot: snap(.armed, leaveBy: t0.addingTimeInterval(12 * 3600)), power: .normal, now: t0)
    #expect(fake.calls.isEmpty)
    // Armed within 8 h: start.
    await c.apply(snapshot: snap(.armed, leaveBy: t0.addingTimeInterval(3600)), power: .normal, now: t0.addingTimeInterval(10))
    guard case .start(let tid, let name, _, _)? = fake.calls.first else { Issue.record("no start"); return }
    #expect(tid == trip && name == "Utah" && fake.calls.count == 1)
    // Same content: skipped.
    await c.apply(snapshot: snap(.armed, leaveBy: t0.addingTimeInterval(3600)), power: .normal, now: t0.addingTimeInterval(200))
    #expect(fake.calls.count == 1)
    // Phase change: immediate.
    await c.apply(snapshot: snap(.driving, leaveBy: t0.addingTimeInterval(3600)), power: .normal, now: t0.addingTimeInterval(201))
    #expect(fake.calls.count == 2)
    // Drift inside a minute: throttled; after a minute: update.
    await c.apply(snapshot: snap(.driving, leaveBy: t0.addingTimeInterval(3660), arrival: t0.addingTimeInterval(5000)), power: .normal, now: t0.addingTimeInterval(230))
    #expect(fake.calls.count == 2)
    await c.apply(snapshot: snap(.driving, leaveBy: t0.addingTimeInterval(3660), arrival: t0.addingTimeInterval(5000)), power: .normal, now: t0.addingTimeInterval(262))
    #expect(fake.calls.count == 3)
    // Status change: immediate even inside the throttle.
    await c.apply(snapshot: snap(.driving, status: .late, leaveBy: t0.addingTimeInterval(3660), arrival: t0.addingTimeInterval(5000)), power: .normal, now: t0.addingTimeInterval(263))
    #expect(fake.calls.count == 4)
    // Finished: end with dismissal one hour later.
    let end = t0.addingTimeInterval(400)
    await c.apply(snapshot: snap(.finished, next: nil), power: .normal, now: end)
    guard case .end(let final, let dismiss)? = fake.calls.last else { Issue.record("no end"); return }
    #expect(final.phase == .finished && dismiss == end.addingTimeInterval(3600))
    #expect(!fake.isActive)
    await c.apply(snapshot: snap(.finished, next: nil), power: .normal, now: end.addingTimeInterval(5))
    #expect(fake.calls.count == 5)
}

@MainActor @Test func coordinatorPowerSavingStretchesThrottle() async {
    let (c, fake) = rig()
    let low = PowerState(isLowPowerMode: true)
    await c.apply(snapshot: snap(.driving), power: .normal, now: t0)
    await c.apply(snapshot: snap(.driving, arrival: t0.addingTimeInterval(100)), power: low, now: t0.addingTimeInterval(100))
    #expect(fake.calls.count == 1)
    await c.apply(snapshot: snap(.driving, arrival: t0.addingTimeInterval(100)), power: low, now: t0.addingTimeInterval(301))
    #expect(fake.calls.count == 2)
    guard case .update(let content, _)? = fake.calls.last else { Issue.record("no update"); return }
    #expect(content.isPowerSaving)
}

@MainActor @Test func coordinatorSkipsWhenActivitiesDisabledAndRetriesFailedStart() async {
    let (c, fake) = rig()
    fake.areActivitiesEnabled = false
    await c.apply(snapshot: snap(.driving), power: .normal, now: t0)
    #expect(fake.calls.isEmpty)
    fake.areActivitiesEnabled = true
    fake.failNextStart = true
    await c.apply(snapshot: snap(.driving), power: .normal, now: t0)
    #expect(fake.calls.count == 1 && c.lastStartError != nil)
    await c.apply(snapshot: snap(.driving), power: .normal, now: t0.addingTimeInterval(10))
    #expect(fake.calls.count == 1)
    await c.apply(snapshot: snap(.driving), power: .normal, now: t0.addingTimeInterval(61))
    #expect(fake.calls.count == 2 && fake.isActive)
}

@MainActor @Test func coordinatorPassesStaleDateAndEndsIdleImmediately() async {
    let (c, fake) = rig()
    await c.apply(snapshot: snap(.driving, nextRefresh: t0.addingTimeInterval(300)), power: .normal, now: t0)
    guard case .start(_, _, _, let stale)? = fake.calls.first else { Issue.record("no start"); return }
    #expect(stale == t0.addingTimeInterval(1200))
    await c.apply(snapshot: .idle(at: t0.addingTimeInterval(5)), power: .normal, now: t0.addingTimeInterval(5))
    guard case .end(_, let dismiss)? = fake.calls.last else { Issue.record("no end"); return }
    #expect(dismiss == nil)
}

// MARK: publisher

@MainActor @Test func publisherReloadsOnlyOnVisibleChange() throws {
    let store = InMemorySnapshotStore()
    let reloader = FakeWidgetReloader()
    let p = SnapshotPublisher(store: store, reloader: reloader)
    let lb = t0.addingTimeInterval(3600)
    #expect(p.publish(snap(.armed, leaveBy: lb)))
    #expect(!p.publish(snap(.armed, at: t0.addingTimeInterval(30), leaveBy: lb.addingTimeInterval(1))))   // same minute
    #expect(!p.publish(snap(.armed, at: t0.addingTimeInterval(30), status: .leaveSoon, leaveBy: lb)))     // status alone: no reload
    #expect(p.publish(snap(.armed, leaveBy: lb.addingTimeInterval(120))))                                // leave-by moved
    #expect(p.publish(snap(.driving, leaveBy: lb.addingTimeInterval(120))))                              // phase
    #expect(p.publish(snap(.driving, next: stopB, leaveBy: lb.addingTimeInterval(120))))                 // next stop
    #expect(reloader.reloadedKinds == Array(repeating: "IterGoNext", count: 4))
    #expect(store.writeCount == 6)
    #expect(store.read()?.next?.id == stopB)
}

private struct ThrowingStore: GoSnapshotStoring {
    struct Boom: Error {}
    func write(_ s: GoSnapshot) throws { throw Boom() }
    func read() -> GoSnapshot? { nil }
}

@MainActor @Test func publisherSurvivesWriteFailure() {
    let reloader = FakeWidgetReloader()
    let p = SnapshotPublisher(store: ThrowingStore(), reloader: reloader)
    #expect(!p.publish(snap()))
    #expect(p.lastWriteError != nil && reloader.reloadedKinds.isEmpty)
}
