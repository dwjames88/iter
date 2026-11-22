import Foundation
import Synchronization

/// Time for the sources layer: the current instant and a sleep. Tests use `ManualSourceClock`.
public protocol SourceClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

/// Wall clock and `Task.sleep`.
public struct SystemSourceClock: SourceClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

/// A clock that only moves when told. `sleep` advances the clock by the duration at once (and records it), so code
/// that waits (spacing, backoff) runs instantly in tests while its timing stays checkable.
public final class ManualSourceClock: SourceClock {
    private struct State { var now: Date; var sleeps: [Duration] = [] }
    private let state: Mutex<State>

    public init(now: Date) { state = Mutex(State(now: now)) }

    public var now: Date { state.withLock { $0.now } }

    /// Every sleep requested so far, in order.
    public var sleeps: [Duration] { state.withLock { $0.sleeps } }

    public func advance(by duration: Duration) {
        state.withLock { $0.now = $0.now.addingTimeInterval(duration.timeInterval) }
    }

    public func set(_ date: Date) { state.withLock { $0.now = date } }

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        state.withLock {
            $0.sleeps.append(duration)
            $0.now = $0.now.addingTimeInterval(duration.timeInterval)
        }
        await Task.yield()
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`.
    public var timeInterval: TimeInterval {
        let c = components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }

    public static func interval(_ t: TimeInterval) -> Duration { .milliseconds(Int64((t * 1000).rounded())) }
}
