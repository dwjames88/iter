import Foundation

/// Whether data fetched at some time may still be presented as current. An old cached forecast is never presented as fresh.
public enum Freshness: Codable, Hashable, Sendable {
    case fresh(age: TimeInterval)
    case stale(age: TimeInterval)

    /// The default time-to-live of a forecast: three hours.
    public static let defaultTTL: TimeInterval = 3 * 3600

    /// `age` is `now - fetchedAt` (never negative: a fetch time in the future counts as age 0). The data is stale when
    /// `now` is strictly after `fetchedAt + ttl`; at exactly the ttl it is still fresh.
    public static func evaluate(fetchedAt: Date, ttl: TimeInterval, now: Date) -> Freshness {
        let age = max(0, now.timeIntervalSince(fetchedAt))
        return now > fetchedAt.addingTimeInterval(ttl) ? .stale(age: age) : .fresh(age: age)
    }

    public var age: TimeInterval {
        switch self {
        case .fresh(let age), .stale(let age): age
        }
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
