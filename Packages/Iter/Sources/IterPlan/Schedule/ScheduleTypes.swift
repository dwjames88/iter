import Foundation
import IterModel

/// Identifies a drive between two stops by id. The first leg of a trip uses the start place's `id` as `from`.
public struct LegKey: Hashable, Sendable, Codable {
    public let from: UUID
    public let to: UUID

    public init(from: UUID, to: UUID) {
        self.from = from
        self.to = to
    }

    public init(_ from: UUID, _ to: UUID) {
        self.from = from
        self.to = to
    }
}

/// Each light stop's session window on its own day at its own place, by stop id. A stop with no entry has no window
/// that day (polar day or night). Lodging and waypoint stops never have one.
public typealias SessionWindows = [UUID: TimeSpan]

/// One problem with a stop's schedule.
public enum ScheduleIssue: Codable, Hashable, Sendable {
    /// You would have to leave the previous stop before you are free of it. `shortBySeconds` is how much time is missing.
    case driveDoesNotFit(shortBySeconds: TimeInterval)
    /// This stop's window starts before the previous stop's window on the same day: the order is backwards.
    case outOfOrder
    /// A light stop's session window does not occur that day (polar day or night).
    case windowMissing
    /// The drive time is a straight-line estimate, not a road route. A note, not a conflict.
    case driveEstimated
}

/// One stop's schedule: "leave by 4:10 to be set up for the 6:12 sunrise".
public struct StopSchedule: Codable, Hashable, Sendable, Identifiable {
    public var stopID: UUID
    public var kind: StopKind
    /// The session window (light stops only); nil when the sun does not produce it, and always nil for lodging and waypoints.
    public var window: TimeSpan?
    /// Window start minus the set-up buffer (light stops with a window only).
    public var setUpBy: Date?
    /// When you must be at the place: set-up time minus the walk-in (equal to `setUpBy` when the walk-in is unknown; see
    /// `walkInKnown`); or the stop's fixed arrival; or, for a lodging or waypoint with neither, an estimate (the previous
    /// stop's `departAt` plus the drive), which is not a constraint.
    public var arriveBy: Date?
    /// Arrival minus the drive into this stop. nil for the first stop when the trip has no start place.
    public var leaveBy: Date?
    /// When you are free to leave this stop: window start plus dwell, the window end for a light stop with no dwell, arrival
    /// plus dwell for lodging and waypoints. nil for an overnight lodging (dwell 0) and when no time is known.
    public var departAt: Date?
    /// The drive into this stop from the previous stop (or from the start place, see `fromStart`).
    public var legFromPrevious: Leg?
    /// The leg came from the trip's start place rather than a previous stop.
    public var fromStart: Bool
    public var walkInKnown: Bool
    public var issues: [ScheduleIssue]
    /// Which timing applied to the drive from the previous stop when that stop is on an earlier day; nil for a same-day drive
    /// and for the first stop. For `.eveningBefore`, `leaveBy` is when the previous stop frees you.
    public var transferTiming: TransferTiming?

    public var id: UUID { stopID }

    public init(stopID: UUID, kind: StopKind = .light, window: TimeSpan?, setUpBy: Date?, arriveBy: Date?, leaveBy: Date?,
                departAt: Date? = nil, legFromPrevious: Leg?, fromStart: Bool = false, walkInKnown: Bool, issues: [ScheduleIssue],
                transferTiming: TransferTiming? = nil) {
        self.stopID = stopID
        self.kind = kind
        self.window = window
        self.setUpBy = setUpBy
        self.arriveBy = arriveBy
        self.leaveBy = leaveBy
        self.departAt = departAt
        self.legFromPrevious = legFromPrevious
        self.fromStart = fromStart
        self.walkInKnown = walkInKnown
        self.issues = issues
        self.transferTiming = transferTiming
    }

    /// How many seconds the drive into this stop is short of fitting, if it does not fit.
    public var shortBySeconds: TimeInterval? {
        for issue in issues {
            if case .driveDoesNotFit(let seconds) = issue { return seconds }
        }
        return nil
    }

    /// Issues that count as conflicts (everything but a drive estimate).
    public var conflicts: [ScheduleIssue] { issues.filter { $0 != .driveEstimated } }
}

/// The whole trip's schedule, in stop order.
public struct TripSchedule: Codable, Hashable, Sendable {
    public var stops: [StopSchedule]

    public init(stops: [StopSchedule]) { self.stops = stops }

    public func schedule(for stopID: UUID) -> StopSchedule? { stops.first { $0.stopID == stopID } }
    /// Conflicts across the trip; a drive estimate is not counted.
    public var issueCount: Int { stops.reduce(0) { $0 + $1.conflicts.count } }
}

/// A proposed reordering the user can accept or ignore. Never applied automatically.
public struct OrderingSuggestion: Codable, Hashable, Sendable {
    public var dayIndex: Int
    /// Stop IDs in the suggested order for that day.
    public var order: [UUID]
    /// Conflicts in the current order and in the suggested one (the suggestion is only made when it has fewer).
    public var issuesBefore: Int
    public var issuesAfter: Int

    public init(dayIndex: Int, order: [UUID], issuesBefore: Int, issuesAfter: Int) {
        self.dayIndex = dayIndex
        self.order = order
        self.issuesBefore = issuesBefore
        self.issuesAfter = issuesAfter
    }
}
