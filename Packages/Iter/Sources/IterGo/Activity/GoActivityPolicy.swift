import Foundation
import IterGoActivity

/// What about a snapshot makes the Live Activity update at once (rather than wait for the throttle).
public struct GoActivityMarker: Hashable, Sendable {
    public var phase: GoPhase
    public var nextStopID: UUID?
    public var status: GoLeaveStatus?
    public var hasUndo: Bool

    public init(phase: GoPhase, nextStopID: UUID?, status: GoLeaveStatus?, hasUndo: Bool) {
        self.phase = phase
        self.nextStopID = nextStopID
        self.status = status
        self.hasUndo = hasUndo
    }

    public init(snapshot s: GoSnapshot) {
        self.init(phase: s.phase, nextStopID: s.next?.id, status: s.leave?.status, hasUndo: s.undo != nil)
    }
}

/// When the Live Activity starts, updates and ends (BLUEPRINT §10.5). Pure.
public enum GoActivityPolicy {
    public static let startLead: TimeInterval = 8 * 3600
    public static let staleMargin: TimeInterval = 15 * 60
    public static let fallbackStale: TimeInterval = 30 * 60
    public static let updateInterval: TimeInterval = 60
    public static let powerSavingInterval: TimeInterval = 300
    public static let dismissalDelay: TimeInterval = 3600

    /// The next expected refresh plus 15 minutes; else 30 minutes after the snapshot was built.
    public static func staleDate(for snapshot: GoSnapshot) -> Date {
        if let next = snapshot.freshness.nextRefreshAt { return next.addingTimeInterval(staleMargin) }
        return snapshot.generatedAt.addingTimeInterval(fallbackStale)
    }

    /// Start at `armed` only when the first leave-by is within 8 h; else when the run first gets going.
    public static func shouldStart(_ snapshot: GoSnapshot, now: Date) -> Bool {
        switch snapshot.phase {
        case .driving, .atStop, .betweenStops: return true
        case .armed:
            guard let leaveBy = snapshot.leave?.leaveBy else { return false }
            return leaveBy.timeIntervalSince(now) <= startLead
        case .idle, .paused, .finished: return false
        }
    }

    public static func shouldEnd(_ snapshot: GoSnapshot) -> Bool { snapshot.phase == .finished }

    /// At most one update per minute (five when power saving), except at once on a phase, leave-status, next-stop or undo change.
    public static func shouldUpdate(previous: GoActivityMarker, current: GoActivityMarker, lastUpdateAt: Date?, now: Date,
                                    powerSaving: Bool) -> Bool {
        if previous != current { return true }
        guard let lastUpdateAt else { return true }
        return now.timeIntervalSince(lastUpdateAt) >= (powerSaving ? powerSavingInterval : updateInterval)
    }
}
