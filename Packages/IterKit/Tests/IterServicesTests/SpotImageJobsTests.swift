import Foundation
import Testing
import IterCore
@testable import IterServices

private let request = SpotImageRequest(spotID: "a", coordinate: Coordinate(latitude: 1, longitude: 2),
                                       pointSize: CGSize(width: 100, height: 50), scale: 2)

/// A job that runs until it is cancelled and says whether it was.
private final class Probe: Sendable {
    private let state = Mutex<(started: Bool, cancelled: Bool)>((false, false))
    var started: Bool { state.withLock { $0.started } }
    var cancelled: Bool { state.withLock { $0.cancelled } }
    func run() async -> [SpotImage] {
        state.withLock { $0.started = true }
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
        state.withLock { $0.cancelled = true }
        return []
    }
}

import Synchronization

@Suite struct SpotImageJobsTests {
    @Test func theLastWaiterLeavingCancelsTheJob() async {
        let jobs = SpotImageJobs()
        let probe = Probe()
        let a = await jobs.join(request) { await probe.run() }
        let b = await jobs.join(request) { await probe.run() }
        #expect(a.task == b.task)
        while !probe.started { try? await Task.sleep(for: .milliseconds(2)) }
        await jobs.abandon(request, waiter: a.id)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!probe.cancelled)          // b still wants it
        await jobs.abandon(request, waiter: b.id)
        _ = await a.task.value
        #expect(probe.cancelled)
        await jobs.release(request, waiter: a.id)
        await jobs.release(request, waiter: b.id)
        #expect(await jobs.count == 0)
    }

    @Test func aFinishedJobIsForgottenAndARepeatRunsAgain() async {
        let jobs = SpotImageJobs()
        let first = await jobs.join(request) { [] }
        _ = await first.task.value
        await jobs.release(request, waiter: first.id)
        #expect(await jobs.count == 0)
        let second = await jobs.join(request) { [] }
        #expect(second.task != first.task)
        await jobs.release(request, waiter: second.id)
    }

    @Test func aLateAbandonAfterReleaseIsHarmless() async {
        let jobs = SpotImageJobs()
        let w = await jobs.join(request) { [] }
        _ = await w.task.value
        await jobs.release(request, waiter: w.id)
        await jobs.abandon(request, waiter: w.id)
        #expect(await jobs.count == 0)
    }
}
