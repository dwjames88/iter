import Foundation

/// How long a drive that failed for a passing reason (throttled, offline) waits before it is asked for again: 30 seconds,
/// then 1, 2 and 4 minutes, then every 5 minutes. "No route" is final and never retried. Ported from the old builder.
public struct DriveRetryBackoff: Sendable, Equatable {
    public var first: TimeInterval
    public var cap: TimeInterval

    public init(first: TimeInterval = 30, cap: TimeInterval = 300) {
        self.first = first
        self.cap = cap
    }

    public static let standard = DriveRetryBackoff()

    /// The wait after the `attempt`th failure in a row (0 is the first failure). Doubles from `first`, never past `cap`.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let n = max(0, min(attempt, 30))
        return min(cap, first * pow(2, Double(n)))
    }
}
