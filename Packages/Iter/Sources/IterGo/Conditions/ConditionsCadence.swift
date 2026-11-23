import Foundation
import IterModel

// When each piece of conditions data is due (BLUEPRINT §10.6). Pure: give it the last fetch times and the context.

/// One thing the loop fetches. Declaration order is the order the loop runs them in (the NOAA forecast is slow under its
/// rate cap for far-apart stops, so what the screen needs goes first).
public enum ConditionsItem: String, Codable, Hashable, Sendable, CaseIterable {
    /// Live conditions at the current position (priority `.onScreen`).
    case hereLive
    /// Observation, nowcast and live reading at the next stop (`.onScreen`).
    case nextLive
    /// The next stop's `SkyReport` for its day (`.onScreen`).
    case nextForecast
    /// Reports for the rest of today's stops (`.activeTrip`).
    case todayForecast
    /// The whole-trip offline pack (`.activeTrip`).
    case pack

}

/// What the cadence remembers between calls. Codable: it travels inside `GoConditionsState`.
public struct ConditionsCadenceMemory: Codable, Hashable, Sendable {
    /// Last fetch (attempt) per item, keyed by `ConditionsItem.rawValue`.
    public var lastFetch: [String: Date]
    /// The next stop `nextLive` and `nextForecast` were last fetched for.
    public var nextStopID: UUID?
    /// Where `hereLive` was last fetched.
    public var hereCoordinate: Coordinate?

    public init(lastFetch: [String: Date] = [:], nextStopID: UUID? = nil, hereCoordinate: Coordinate? = nil) {
        self.lastFetch = lastFetch
        self.nextStopID = nextStopID
        self.hereCoordinate = hereCoordinate
    }

    public func lastFetch(_ item: ConditionsItem) -> Date? { lastFetch[item.rawValue] }
    public mutating func setLastFetch(_ item: ConditionsItem, _ date: Date?) { lastFetch[item.rawValue] = date }
}

public enum ConditionsCadence {
    // Intervals tie to the source caches: the service keeps the nowcast 15 min and observations about as long, the composite
    // forecast an hour or more, so asking sooner only re-reads the cache.
    public static let nextLiveInterval: TimeInterval = 15 * 60
    /// Weather where you are while driving: the car moves through it, so a half-hour read is enough and halves the requests.
    public static let hereLiveInterval: TimeInterval = 30 * 60
    public static let savingHereLiveInterval: TimeInterval = 60 * 60
    public static let nextForecastInterval: TimeInterval = 60 * 60
    public static let todayForecastInterval: TimeInterval = 60 * 60
    public static let packInterval: TimeInterval = 3 * 3600
    /// Low Power Mode or battery under 20 %.
    public static let savingLiveInterval: TimeInterval = 30 * 60
    public static let savingForecastInterval: TimeInterval = 120 * 60
    public static let savingPackInterval: TimeInterval = 6 * 3600
    /// Not driving: `hereLive` only refreshes after moving more than this far since the last fetch, metres.
    public static let hereMoveThresholdM: Double = 10_000
    /// A failed pack build is tried again after this long (not after a full pack interval).
    public static let packRetryInterval: TimeInterval = 30 * 60

    /// Phases in which conditions are fetched at all.
    public static func isActive(_ phase: GoPhase) -> Bool {
        switch phase {
        case .armed, .driving, .atStop, .betweenStops: true
        case .idle, .paused, .finished: false
        }
    }

    public static func interval(for item: ConditionsItem, power: PowerState) -> TimeInterval {
        let saving = power.isSaving
        switch item {
        case .hereLive: return saving ? savingHereLiveInterval : hereLiveInterval
        case .nextLive: return saving ? savingLiveInterval : nextLiveInterval
        case .nextForecast, .todayForecast: return saving ? savingForecastInterval : nextForecastInterval
        case .pack: return saving ? savingPackInterval : packInterval
        }
    }

    /// When `item` is next due; a date at or before `now` means due now. nil when it does not apply (no next stop, not
    /// driving and not moved far, inactive phase) or is triggered by position rather than by time.
    public static func dueDate(_ item: ConditionsItem, now: Date, phase: GoPhase, power: PowerState, memory: ConditionsCadenceMemory,
                               nextStopID: UUID?, hasTodayStops: Bool, fix: LocationFix?) -> Date? {
        guard isActive(phase) else { return nil }
        let periodic: Date? = memory.lastFetch(item).map { $0.addingTimeInterval(interval(for: item, power: power)) }
        switch item {
        case .hereLive:
            guard let fix, fix.isUsable() else { return nil }
            if phase == .driving { return periodic ?? now }
            guard let last = memory.hereCoordinate, memory.lastFetch(.hereLive) != nil else { return now }
            return last.distance(to: fix.coordinate) > hereMoveThresholdM ? now : nil
        case .nextLive, .nextForecast:
            guard let nextStopID else { return nil }
            if memory.nextStopID != nextStopID { return now }
            return periodic ?? now
        case .todayForecast:
            guard hasTodayStops else { return nil }
            return periodic ?? now
        case .pack:
            return periodic ?? now
        }
    }

    /// The items due at `now`, in run order.
    public static func due(now: Date, phase: GoPhase, power: PowerState, memory: ConditionsCadenceMemory, nextStopID: UUID?,
                           hasTodayStops: Bool, fix: LocationFix?) -> [ConditionsItem] {
        ConditionsItem.allCases.filter {
            guard let d = dueDate($0, now: now, phase: phase, power: power, memory: memory, nextStopID: nextStopID,
                                  hasTodayStops: hasTodayStops, fix: fix) else { return false }
            return d <= now
        }
    }

    /// When the engine should wake to refresh next: the earliest due date, never before `now`. nil when nothing is scheduled by time.
    public static func nextDue(now: Date, phase: GoPhase, power: PowerState, memory: ConditionsCadenceMemory, nextStopID: UUID?,
                               hasTodayStops: Bool, fix: LocationFix?) -> Date? {
        let dates = ConditionsItem.allCases.compactMap {
            dueDate($0, now: now, phase: phase, power: power, memory: memory, nextStopID: nextStopID, hasTodayStops: hasTodayStops, fix: fix)
        }
        return dates.min().map { max($0, now) }
    }
}
