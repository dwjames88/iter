import Foundation

/// Polite per-key (host) limiting: a minimum gap between request starts, a cap on requests in flight, and an optional
/// cap per rolling minute. Time comes from the injected clock so tests are instant and exact.
///
/// Start times are reserved up front in order of arrival, so two callers never get the same slot. A waiter that is
/// cancelled gives its place up and never holds a concurrency slot.
public actor RateLimiter {
    /// Proof of a held slot; pass it to `release(_:)`.
    public struct Permit: Sendable, Hashable {
        let key: String
        let id: UInt64
    }

    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Lane {
        var inFlight = 0
        var nextStart: Date?
        var starts: [Date] = []
        var waiters: [Waiter] = []
    }

    private let clock: any SourceClock
    private var lanes: [String: Lane] = [:]
    private var counter: UInt64 = 0

    public init(clock: any SourceClock = SystemSourceClock()) { self.clock = clock }

    /// Waits for a concurrency slot, then for the start time the policy allows, and returns the held slot.
    public func acquire(key: String, policy: RequestPolicy) async throws -> Permit {
        try Task.checkCancellation()
        counter += 1
        let id = counter
        let limit = max(1, policy.maxConcurrent)
        var lane = lanes[key] ?? Lane()
        if lane.inFlight < limit && lane.waiters.isEmpty {
            lane.inFlight += 1
            lanes[key] = lane
        } else {
            lanes[key] = lane
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    if Task.isCancelled {
                        c.resume(throwing: CancellationError())
                    } else {
                        lanes[key, default: Lane()].waiters.append(Waiter(id: id, continuation: c))
                    }
                }
            } onCancel: {
                Task { await self.cancelWaiter(key: key, id: id) }
            }
            // The slot was handed over by `release`. A cancel that raced with the hand-over must give it back.
            if Task.isCancelled {
                release(Permit(key: key, id: id))
                throw CancellationError()
            }
        }
        let permit = Permit(key: key, id: id)
        let wait = reserveStart(key: key, policy: policy)
        if wait > .zero {
            do { try await clock.sleep(for: wait) } catch {
                release(permit)
                throw error
            }
        }
        return permit
    }

    /// Returns a slot and lets the next waiter in.
    public func release(_ permit: Permit) {
        guard var lane = lanes[permit.key], lane.inFlight > 0 else { return }
        if lane.waiters.isEmpty {
            lane.inFlight -= 1
            lanes[permit.key] = lane
        } else {
            let next = lane.waiters.removeFirst()
            lanes[permit.key] = lane
            next.continuation.resume()
        }
    }

    /// Runs `body` holding a slot, releasing it however `body` ends.
    public func withPermit<T: Sendable>(key: String, policy: RequestPolicy,
                                        _ body: @Sendable () async throws -> T) async throws -> T {
        let permit = try await acquire(key: key, policy: policy)
        let result: T
        do { result = try await body() } catch {
            release(permit)
            throw error
        }
        release(permit)
        return result
    }

    /// Requests currently holding a slot for `key` (tests).
    public func inFlight(for key: String) -> Int { lanes[key]?.inFlight ?? 0 }

    private func cancelWaiter(key: String, id: UInt64) {
        guard var lane = lanes[key], let i = lane.waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = lane.waiters.remove(at: i)
        lanes[key] = lane
        w.continuation.resume(throwing: CancellationError())
    }

    /// Reserves the next start time for the lane and returns how long to wait for it.
    private func reserveStart(key: String, policy: RequestPolicy) -> Duration {
        var lane = lanes[key] ?? Lane()
        let now = clock.now
        var start = now
        if let next = lane.nextStart, next > start { start = next }
        if let cap = policy.perMinute, cap > 0 {
            while true {
                let window = lane.starts.filter { $0 > start.addingTimeInterval(-60) }
                if window.count >= cap {
                    start = window[window.count - cap].addingTimeInterval(60)
                } else {
                    break
                }
            }
            lane.starts = lane.starts.filter { $0 > start.addingTimeInterval(-60) } + [start]
            lane.starts.sort()
        }
        lane.nextStart = start.addingTimeInterval(policy.spacing.timeInterval)
        lanes[key] = lane
        let delay = start.timeIntervalSince(now)
        return delay > 0 ? .interval(delay) : .zero
    }
}
