import Foundation

/// A stop in a trip, as a value: one spot, one day, one light session.
public struct TripStopPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var spot: Spot
    /// 0-based day within the trip.
    public var dayIndex: Int
    /// The window this stop is for. Every stop has one (assigned by default from the spot's best light).
    public var session: LightWindowKind
    /// Minutes before the window starts that you want to be set up (default 20).
    public var setUpBufferMinutes: Int
    public var note: String

    public init(id: UUID = UUID(), spot: Spot, dayIndex: Int, session: LightWindowKind, setUpBufferMinutes: Int = 20, note: String = "") {
        self.id = id
        self.spot = spot
        self.dayIndex = dayIndex
        self.session = session
        self.setUpBufferMinutes = setUpBufferMinutes
        self.note = note
    }
}

/// A trip as a value: what the scheduler, the exporter and tests work on. The SwiftData `TripRecord` converts to this.
public struct TripPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var startDay: LocalDay
    public var dayCount: Int
    /// Ordered within each day; the array order across days is day-major.
    public var stops: [TripStopPlan]
    public var notes: String

    public init(id: UUID = UUID(), name: String, startDay: LocalDay, dayCount: Int, stops: [TripStopPlan] = [], notes: String = "") {
        self.id = id
        self.name = name
        self.startDay = startDay
        self.dayCount = max(1, dayCount)
        self.stops = stops
        self.notes = notes
    }

    public func stops(onDay index: Int) -> [TripStopPlan] { stops.filter { $0.dayIndex == index } }
    public func day(_ index: Int) -> LocalDay { startDay.adding(days: index) }
}

// MARK: - Driving

/// A drive between two points. `isEstimate` is true when no road route was available and the time is a straight-line guess.
public struct DriveLeg: Codable, Hashable, Sendable {
    public var from: Coordinate
    public var to: Coordinate
    public var seconds: TimeInterval
    public var meters: Double
    public var isEstimate: Bool
    /// The road geometry for drawing, if known.
    public var path: [Coordinate]

    public init(from: Coordinate, to: Coordinate, seconds: TimeInterval, meters: Double, isEstimate: Bool, path: [Coordinate] = []) {
        self.from = from
        self.to = to
        self.seconds = seconds
        self.meters = meters
        self.isEstimate = isEstimate
        self.path = path
    }

    /// Straight-line distance × 1.3 at 70 km/h: an honest, labelled fallback.
    public static func estimate(from a: Coordinate, to b: Coordinate) -> DriveLeg {
        let meters = a.distance(to: b) * 1.3
        return DriveLeg(from: a, to: b, seconds: meters / (70_000.0 / 3600.0), meters: meters, isEstimate: true, path: [a, b])
    }
}

public protocol DriveTimeProviding: Sendable {
    /// A driving route from `a` to `b`. Throws if no route can be found; callers fall back to `DriveLeg.estimate`.
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg

    /// A real route for this pair that is already known (cached or seeded), answered without a request or a suspension.
    /// Never an estimate. Providers without a cache keep the default, nil.
    func cachedLeg(from a: Coordinate, to b: Coordinate) -> DriveLeg?
}

extension DriveTimeProviding {
    public func cachedLeg(from a: Coordinate, to b: Coordinate) -> DriveLeg? { nil }
}

// MARK: - Schedule

/// One stop's backward schedule: "leave by 4:10 to be set up for 6:12 sunrise".
public struct StopSchedule: Codable, Hashable, Sendable, Identifiable {
    public var stopID: UUID
    /// The session window on the stop's day; nil if the sun does not produce it (polar day or night).
    public var window: TimeSpan?
    /// Window start minus the set-up buffer.
    public var setUpBy: Date?
    /// Set-up time minus the walk-in (equal to `setUpBy` when walk-in is unknown; see `walkInKnown`).
    public var arriveBy: Date?
    /// Arrival minus the drive from the previous stop (nil for the first stop of the trip).
    public var leaveBy: Date?
    /// The drive from the previous stop, if any.
    public var legFromPrevious: DriveLeg?
    public var walkInKnown: Bool
    public var issues: [ScheduleIssue]

    public var id: UUID { stopID }

    public init(stopID: UUID, window: TimeSpan?, setUpBy: Date?, arriveBy: Date?, leaveBy: Date?, legFromPrevious: DriveLeg?,
                walkInKnown: Bool, issues: [ScheduleIssue]) {
        self.stopID = stopID
        self.window = window
        self.setUpBy = setUpBy
        self.arriveBy = arriveBy
        self.leaveBy = leaveBy
        self.legFromPrevious = legFromPrevious
        self.walkInKnown = walkInKnown
        self.issues = issues
    }
}

public enum ScheduleIssue: Codable, Hashable, Sendable {
    /// You would have to leave the previous stop before its window ends. `shortBySeconds` is how much time is missing.
    case driveDoesNotFit(shortBySeconds: TimeInterval)
    /// This stop's window starts before the previous stop's window on the same day: the order is backwards.
    case outOfOrder
    /// The session's window does not occur that day (polar day or night).
    case windowMissing
    /// The drive time is a straight-line estimate, not a road route.
    case driveEstimated
}

/// The whole trip's schedule, in stop order.
public struct TripSchedule: Codable, Hashable, Sendable {
    public var stops: [StopSchedule]

    public init(stops: [StopSchedule]) { self.stops = stops }

    public func schedule(for stopID: UUID) -> StopSchedule? { stops.first { $0.stopID == stopID } }
    public var issueCount: Int { stops.reduce(0) { $0 + $1.issues.filter { $0 != .driveEstimated }.count } }
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
