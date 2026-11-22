import Foundation
import IterModel
import IterSky
import IterPlan
import IterConditions

/// A stop's conditions moved enough to tell the traveller (D9). The lead maps it to the notification planner's input.
public struct ConditionsChange: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Hashable, Sendable { case scoreMoved, bandChanged }

    public var stopID: UUID
    public var stopName: String
    public var windowKind: LightWindowKind?
    public var previous: Int
    public var current: Int
    public var previousBand: GoBand
    public var currentBand: GoBand
    public var reason: Reason
    /// "high cloud moving in", "clearing" or "forecast updated".
    public var cause: String
    public var raisedAt: Date

    public var improved: Bool { current > previous }

    public init(stopID: UUID, stopName: String, windowKind: LightWindowKind?, previous: Int, current: Int, previousBand: GoBand,
                currentBand: GoBand, reason: Reason, cause: String, raisedAt: Date) {
        self.stopID = stopID
        self.stopName = stopName
        self.windowKind = windowKind
        self.previous = previous
        self.current = current
        self.previousBand = previousBand
        self.currentBand = currentBand
        self.reason = reason
        self.cause = cause
        self.raisedAt = raisedAt
    }
}

public enum ConditionsChangeDetector {
    /// Points of high cloud (rise) or total cloud (fall) across the six-hour strip that name the cause.
    public static let causeThreshold = 0.20

    /// Feeds `score` to the alert state; returns the change to raise, if any.
    public static func observe(state: inout ConditionsAlertState, stop: Stop, score: Int, live: LiveConditions?, now: Date) -> ConditionsChange? {
        guard let alert = state.observe(stopID: stop.id, score: score, now: now) else { return nil }
        return ConditionsChange(stopID: stop.id, stopName: stop.place.name, windowKind: stop.session, previous: alert.previous,
                                current: alert.current, previousBand: GoBand(alert.previousBand), currentBand: GoBand(alert.currentBand),
                                reason: alert.reason == .scoreMoved ? .scoreMoved : .bandChanged, cause: cause(live: live), raisedAt: now)
    }

    /// What moved, read from the strip: high cloud up 20 points or more, else total cloud down 20 points or more.
    public static func cause(live: LiveConditions?) -> String {
        let strip = live?.strip ?? []
        if let first = strip.first?.conditions, let last = strip.last?.conditions, strip.count > 1 {
            if let a = first.cloudHigh, let b = last.cloudHigh, b - a >= causeThreshold - 1e-9 { return "high cloud moving in" }
            if let a = first.cloudTotal, let b = last.cloudTotal, a - b >= causeThreshold - 1e-9 { return "clearing" }
        }
        return "forecast updated"
    }
}
