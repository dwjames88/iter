import Foundation
import Testing
import IterCore
import IterLight
import IterData
import IterServices
@testable import IterFeatures

/// A sleep a test controls: each call waits until `fire()` (or is cancelled), and the requested durations are recorded.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var cancelledEarly: Set<UUID> = []
    private var recorded: [Duration] = []

    var requested: [Duration] { lock.withLock { recorded } }
    var waiting: Int { lock.withLock { waiters.count } }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let early = lock.withLock { () -> Bool in
                    recorded.append(duration)
                    if cancelledEarly.remove(id) != nil { return true }
                    waiters[id] = continuation
                    return false
                }
                if early { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
                if let c = waiters.removeValue(forKey: id) { return c }
                cancelledEarly.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Ends every sleep that is waiting, as if its time had passed.
    func fire() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        for c in all { c.resume() }
    }
}

/// Lets the main actor and the drive actor run until `condition` holds (no real time passes).
@MainActor private func settle(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<5_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

@MainActor
@Suite struct TripDriveRetryTests {
    private func seconds(_ values: [Double]) -> [Duration] { values.map { .seconds($0) } }

    @Test func backoffDoublesFromThirtySecondsAndStopsAtFiveMinutes() {
        let backoff = DriveRetryBackoff.standard
        #expect((0..<8).map { backoff.delay(forAttempt: $0) } == [30, 60, 120, 240, 300, 300, 300, 300])
        #expect(backoff.delay(forAttempt: 10_000) == 300)
        #expect(backoff.delay(forAttempt: -1) == 30)
    }

    @Test func consecutiveFailingPassesWaitLongerEachTime() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        #expect(sleeper.requested == seconds([30]))
        for expected in [60.0, 120, 240, 300, 300] {
            let before = sleeper.requested.count
            sleeper.fire()
            #expect(await settle { sleeper.requested.count == before + 1 })
            #expect(sleeper.requested.last == .seconds(expected))
        }
    }

    @Test func aTransientFailureIsRetriedByTheTimerWithoutARefresh() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        #expect(model.legs.isEmpty)

        await drives.set(error: nil)
        sleeper.fire()
        #expect(await settle { !model.legs.isEmpty && !model.isLoadingLegs })
        #expect(model.legs.values.allSatisfy { !$0.isEstimate })
        #expect(!model.days[0].hasEstimatedDrive)
        #expect(sleeper.waiting == 0, "everything arrived: no further timer")
        #expect(sleeper.requested == seconds([30]))
    }

    @Test func aSuccessfulRetryResetsTheBackoff() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        sleeper.fire()
        #expect(await settle { sleeper.requested.count == 2 })
        #expect(sleeper.requested.last == .seconds(60))

        await drives.set(error: nil)
        sleeper.fire()
        #expect(await settle { !model.legs.isEmpty && !model.isLoadingLegs })

        // A later trouble (a stop is added, the service fails again) starts from 30 s once more.
        await drives.set(error: MapServiceError.throttled)
        _ = model.addStop(h.spot("mesa-arch"), toDay: 1, defaultBufferMinutes: 30)
        model.refresh()
        #expect(await settle { sleeper.requested.count == 3 })
        #expect(sleeper.requested.last == .seconds(30))
    }

    @Test func noRouteIsNotRetried() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.noRoute)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        let calls = await drives.calls
        #expect(sleeper.requested.isEmpty)
        sleeper.fire()
        for _ in 0..<50 { await Task.yield() }
        #expect(await drives.calls == calls)
    }

    @Test func disappearingCancelsTheTimer() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        let calls = await drives.calls
        #expect(sleeper.waiting == 1)

        model.viewDisappeared()
        #expect(await settle { sleeper.waiting == 0 })
        sleeper.fire()
        for _ in 0..<50 { await Task.yield() }
        #expect(await drives.calls == calls, "no drive request after the view is gone")
        #expect(sleeper.requested == seconds([30]))
    }

    @Test func aFailureWhileHiddenSchedulesNothing() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        await model.waitForLegs()
        #expect(sleeper.requested.isEmpty)
    }

    @Test func appearingAgainAsksAtOnceWhenTheWaitIsOver() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let clock = TestClock()
        let model = h.model(for: h.makeTrip(), drives: drives, now: { clock.date }, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        model.viewDisappeared()
        #expect(await settle { sleeper.waiting == 0 })

        await drives.set(error: nil)
        clock.date.addTimeInterval(31)
        model.viewAppeared()
        #expect(await settle { !model.legs.isEmpty && !model.isLoadingLegs })
        #expect(sleeper.requested == seconds([30]), "no new timer: the retry ran straight away")
    }

    @Test func appearingAgainBeforeTheDeadlineWaitsForTheRest() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let clock = TestClock()
        let model = h.model(for: h.makeTrip(), drives: drives, now: { clock.date }, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        let calls = await drives.calls
        model.viewDisappeared()
        #expect(await settle { sleeper.waiting == 0 })

        clock.date.addTimeInterval(10)
        model.viewAppeared()
        #expect(await settle { sleeper.waiting == 1 })
        #expect(sleeper.requested == seconds([30, 20]))
        #expect(await drives.calls == calls)
    }

    @Test func refreshBeforeTheDeadlineDoesNotAskAgain() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        let calls = await drives.calls
        model.refresh()
        await model.waitForLegs()
        #expect(await drives.calls == calls)
        #expect(sleeper.waiting == 1, "the timer from the first pass is still the one")
        #expect(sleeper.requested == seconds([30]))
    }

    @Test func deletingTheTripCancelsTheTimer() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        let calls = await drives.calls
        model.deleteTrip()
        #expect(await settle { sleeper.waiting == 0 })
        sleeper.fire()
        for _ in 0..<50 { await Task.yield() }
        #expect(await drives.calls == calls)
    }

    @Test func changingThePairsRestartsTheBackoff() async {
        let h = TripHarness()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let sleeper = ManualSleeper()
        let model = h.model(for: h.makeTrip(), drives: drives, sleep: sleeper.sleep)
        model.viewAppeared()
        await model.waitForLegs()
        #expect(await settle { sleeper.waiting == 1 })
        sleeper.fire()
        #expect(await settle { sleeper.requested.count == 2 })
        #expect(sleeper.requested.last == .seconds(60))

        _ = model.addStop(h.spot("mesa-arch"), toDay: 1, defaultBufferMinutes: 30)
        model.refresh()
        #expect(await settle { sleeper.requested.count == 3 })
        #expect(sleeper.requested.last == .seconds(30), "a changed trip starts again at the first wait")
        #expect(sleeper.waiting == 1, "the old timer was cancelled, only the new one waits")
    }
}
