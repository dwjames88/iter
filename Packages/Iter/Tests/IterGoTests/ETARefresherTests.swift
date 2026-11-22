import Foundation
import Testing
import IterGo
import IterModel
import IterSources

private enum Step: Sendable { case ok, fail(SourceError), hold }

private final class FakeRouting: RoutingProvider, @unchecked Sendable {
    let descriptor = SourceCatalogue.appleDirections
    private let lock = NSLock()
    private var script: [Step] = []
    private var held: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private(set) var etaCalls = 0
    private(set) var routeCalls = 0
    private(set) var departings: [Date?] = []
    private var running = 0
    private(set) var maxRunning = 0

    func queue(_ steps: Step...) { lock.withLock { script += steps } }
    var calls: Int { lock.withLock { etaCalls + routeCalls } }
    var heldCount: Int { lock.withLock { held.count } }
    func release() { let all = lock.withLock { let h = held; held = [:]; return h }; for c in all.values { c.resume() } }

    private func run(departing: Date?) async throws {
        let step: Step = lock.withLock {
            departings.append(departing)
            running += 1; maxRunning = max(maxRunning, running)
            return script.isEmpty ? .ok : script.removeFirst()
        }
        defer { lock.withLock { running -= 1 } }
        switch step {
        case .ok: return
        case .fail(let e): throw e
        case .hold:
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    lock.withLock { held[id] = c }
                }
            } onCancel: {
                let c = lock.withLock { held.removeValue(forKey: id) }
                c?.resume(throwing: CancellationError())
            }
        }
    }

    func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        lock.withLock { routeCalls += 1 }
        try await run(departing: departing)
        return Route(path: [from, to], seconds: 600, meters: 10_000, departing: departing)
    }

    func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        lock.withLock { etaCalls += 1 }
        try await run(departing: departing)
        return ETA(seconds: 600, arrival: departing.addingTimeInterval(600), departing: departing)
    }
}

private let t0 = Date(timeIntervalSince1970: 2_000_000)
private let origin = Coordinate(latitude: 36, longitude: -118)
private let stopA = (id: UUID(), coordinate: Coordinate(latitude: 36.5, longitude: -118.5))
private let stopB = (id: UUID(), coordinate: Coordinate(latitude: 37, longitude: -119))
private let driving = ETARefreshContext(phase: .driving)

private func fix(at c: Coordinate = origin) -> LocationFix { LocationFix(coordinate: c, accuracyM: 5, timestamp: t0) }

@MainActor private func waitForCalls(_ fake: FakeRouting, _ n: Int) async {
    for _ in 0..<2000 where fake.calls < n { await Task.yield() }
}

@MainActor
@Test func refresherCadenceAndSingleFlight() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    fake.queue(.hold)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await waitForCalls(fake, 1)
    // Rapid calls while one is in flight: none start.
    for _ in 0..<20 {
        clock.advance(by: 200)
        #expect(!r.refreshIfDue(from: fix(), to: stopA, context: driving))
        #expect(!r.forceRefresh(from: fix(), to: stopA, context: driving))
        #expect(!r.requestRoute(from: fix(), to: stopA, context: driving))
    }
    #expect(fake.calls == 1 && r.isInFlight)
    fake.release()
    await r.settle()
    #expect(r.latest?.stopID == stopA.id)
    guard case .eta(let eta)? = r.latest?.result else { Issue.record("no eta"); return }
    #expect(eta.seconds == 600)
    #expect(r.maxConcurrentObserved == 1 && fake.maxRunning == 1)

    // Cadence: 3 minutes after the request started... clock is already far past it, so due now.
    let started = r.requestLog[0].startedAt
    #expect(r.requestLog[0].finishedAt != nil)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(!r.refreshIfDue(from: fix(), to: stopA, context: driving))
    clock.advance(by: 179)
    #expect(!r.refreshIfDue(from: fix(), to: stopA, context: driving))
    clock.advance(by: 1)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(r.requestLog.count == 3)
    #expect(r.requestLog[1].startedAt > started)
    #expect(r.requestLog.allSatisfy { $0.kind == .scheduled })
    // Moved 2 km: due after 60 s.
    let far = Coordinate(latitude: origin.latitude + 0.03, longitude: origin.longitude)
    clock.advance(by: 59)
    #expect(!r.refreshIfDue(from: fix(at: far), to: stopA, context: driving))
    clock.advance(by: 1)
    #expect(r.refreshIfDue(from: fix(at: far), to: stopA, context: driving))
    await r.settle()
}

@MainActor
@Test func refresherUsesDepartureAndIdlePhasesNeverAsk() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    let leaveBy = t0.addingTimeInterval(5400)
    let armed = ETARefreshContext(phase: .armed, leaveBy: leaveBy)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: armed))
    await r.settle()
    #expect(fake.departings == [leaveBy])
    #expect(r.latest?.departing == leaveBy)
    #expect(!r.refreshIfDue(from: fix(), to: stopA, context: armed))
    clock.advance(by: 899)
    #expect(!r.refreshIfDue(from: fix(), to: stopA, context: armed))
    clock.advance(by: 1)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: armed))
    await r.settle()
    for phase in [GoPhase.idle, .paused, .finished] {
        clock.advance(by: 100_000)
        #expect(!r.refreshIfDue(from: fix(), to: stopA, context: ETARefreshContext(phase: phase)))
        #expect(!r.forceRefresh(from: fix(), to: stopA, context: ETARefreshContext(phase: phase)))
    }
    #expect(fake.calls == 2)
}

@MainActor
@Test func refresherForceSpacing() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    #expect(r.forceRefresh(from: fix(), to: stopA, context: driving))
    await r.settle()
    clock.advance(by: 29)
    #expect(!r.forceRefresh(from: fix(), to: stopA, context: driving))
    clock.advance(by: 1)
    #expect(r.forceRefresh(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(r.requestLog.map(\.kind) == [.forced, .forced])
}

@MainActor
@Test func refresherRateLimitBackoffSequence() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    fake.queue(.fail(.rateLimited(retryAfter: nil)), .fail(.rateLimited(retryAfter: nil)), .fail(.rateLimited(retryAfter: nil)),
               .fail(.rateLimited(retryAfter: nil)), .fail(.rateLimited(retryAfter: nil)), .fail(.rateLimited(retryAfter: nil)))
    var gaps: [TimeInterval] = []
    for _ in 0..<6 {
        clock.advance(by: 1000)
        #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
        await r.settle()
        gaps.append(r.backoffUntil!.timeIntervalSince(clock.now))
        #expect(r.latest?.result == .failed(.rateLimited(retryAfter: nil)))
        // Inside the backoff nothing starts, even forced.
        clock.advance(by: gaps.last! - 1)
        #expect(!r.refreshIfDue(from: fix(), to: stopA, context: driving))
        #expect(!r.forceRefresh(from: fix(), to: stopA, context: driving))
        #expect(!r.requestRoute(from: fix(), to: stopA, context: driving))
    }
    #expect(gaps == [60, 120, 240, 480, 600, 600])
    clock.advance(by: 700)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(r.backoffUntil == nil)
    #expect(!r.isOffline)
    // Streak is reset: the next rate limit starts at 60 again.
    fake.queue(.fail(.rateLimited(retryAfter: nil)))
    clock.advance(by: 1000)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(r.backoffUntil!.timeIntervalSince(clock.now) == 60)
}

@MainActor
@Test func refresherOfflineFlag() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    fake.queue(.fail(.offline), .ok)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(r.isOffline && r.backoffUntil == nil)
    #expect(r.latest?.result == .failed(.offline))
    // Normal cadence applies while offline.
    #expect(!r.refreshIfDue(from: fix(), to: stopA, context: driving))
    clock.advance(by: 180)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(!r.isOffline)
}

@MainActor
@Test func refresherCancelsOnTargetChange() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    fake.queue(.hold)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    await waitForCalls(fake, 1)
    // New target: the old request is dropped and a new one starts at once.
    #expect(r.refreshIfDue(from: fix(), to: stopB, context: driving))
    await r.settle()
    #expect(fake.calls == 2)
    #expect(r.latest?.stopID == stopB.id)
    #expect(r.maxConcurrentObserved == 1)
    #expect(r.requestLog.count == 2 && r.requestLog[0].finishedAt == nil && r.requestLog[1].finishedAt != nil)
    #expect(fake.heldCount == 0)
}

@MainActor
@Test func refresherCancelledResultIsIgnored() async {
    // A provider that ignores cancellation and returns late must not publish a stale outcome.
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    fake.queue(.ok)
    #expect(r.refreshIfDue(from: fix(), to: stopA, context: driving))
    r.cancel()
    #expect(!r.isInFlight)
    for _ in 0..<50 { await Task.yield() }
    #expect(r.latest == nil)
}

@MainActor
@Test func refresherRouteRequest() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    #expect(r.requestRoute(from: fix(), to: stopA, context: driving))
    await r.settle()
    guard case .route(let route)? = r.latest?.result else { Issue.record("no route"); return }
    #expect(route.path.count == 2 && fake.routeCalls == 1 && fake.etaCalls == 0)
    clock.advance(by: 29)
    #expect(!r.requestRoute(from: fix(), to: stopA, context: driving))
    clock.advance(by: 1)
    #expect(r.requestRoute(from: fix(), to: stopA, context: driving))
    await r.settle()
    #expect(r.requestLog.map(\.kind) == [.route, .route])
}

@MainActor
@Test func refresherPublishesOutcomesOnStream() async {
    let clock = ManualClock(t0), fake = FakeRouting()
    let r = ETARefresher(routing: fake, clock: clock)
    #expect(r.forceRefresh(from: fix(), to: stopA, context: driving))
    await r.settle()
    var it = r.outcomes.makeAsyncIterator()
    let first = await it.next()
    #expect(first == r.latest)
    #expect(first?.requestedAt == t0)
}
