import Foundation
import IterModel
import IterSky

/// When a stop's conditions have changed enough to tell the traveller (blueprint D9): the score moved 15 points or more, or it
/// crossed into another band, and no alert for that stop went out in the last hour. Pure.
public enum ConditionsAlertPolicy {
    public static let scoreDelta = 15
    public static let quietPeriod: TimeInterval = 3600

    /// `previous` is the baseline score (nil when there is none yet: never an alert). `lastAlertAt` is the last alert sent for
    /// this stop. Bands come from IterSky's `LightBand(score:)`.
    public static func evaluate(stopID: UUID, previous: Int?, current: Int, lastAlertAt: Date?, now: Date) -> Bool {
        guard let previous else { return false }
        if let lastAlertAt, now.timeIntervalSince(lastAlertAt) < quietPeriod { return false }
        return abs(current - previous) >= scoreDelta || LightBand(score: current) != LightBand(score: previous)
    }
}

/// An alert trip mode should raise.
public struct ConditionsAlert: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Hashable, Sendable {
        /// The score moved by at least `ConditionsAlertPolicy.scoreDelta`.
        case scoreMoved
        /// The score crossed into another band (and moved by less than the delta).
        case bandChanged
    }

    public var stopID: UUID
    public var previous: Int
    public var current: Int
    public var previousBand: LightBand
    public var currentBand: LightBand
    public var reason: Reason
    public var improved: Bool { current > previous }
}

/// What trip mode remembers between score updates, so it can just feed scores in. Persist it as it is (Codable).
///
/// The baseline is the score at the last alert (or the first score seen), not the last score seen: a slow drift still adds up to
/// an alert, and a change held back by the quiet hour is still compared with what the traveller last heard.
public struct ConditionsAlertState: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var baseline: Int
        public var lastAlertAt: Date?
    }

    public private(set) var entries: [UUID: Entry] = [:]

    public init() {}

    /// Feeds a new score for a stop; returns the alert to raise, if any.
    public mutating func observe(stopID: UUID, score: Int, now: Date) -> ConditionsAlert? {
        guard let entry = entries[stopID] else {
            entries[stopID] = Entry(baseline: score, lastAlertAt: nil)
            return nil
        }
        guard ConditionsAlertPolicy.evaluate(stopID: stopID, previous: entry.baseline, current: score, lastAlertAt: entry.lastAlertAt, now: now)
        else { return nil }
        let moved = abs(score - entry.baseline) >= ConditionsAlertPolicy.scoreDelta
        let alert = ConditionsAlert(stopID: stopID, previous: entry.baseline, current: score, previousBand: LightBand(score: entry.baseline),
                                    currentBand: LightBand(score: score), reason: moved ? .scoreMoved : .bandChanged)
        entries[stopID] = Entry(baseline: score, lastAlertAt: now)
        return alert
    }

    /// Forget a stop (visited or skipped).
    public mutating func forget(stopID: UUID) { entries[stopID] = nil }
}
