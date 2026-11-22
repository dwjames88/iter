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
    /// A note about the drive INTO this stop (the drive row above it, or the transfer card when it is the first stop of a
    /// day after an earlier stop). It is stored on the arriving stop, so when stops are reordered the note travels with
    /// the stop it was written for, not with the drive.
    public var driveNote: String

    public init(id: UUID = UUID(), spot: Spot, dayIndex: Int, session: LightWindowKind, setUpBufferMinutes: Int = 20, note: String = "",
                driveNote: String = "") {
        self.id = id
        self.spot = spot
        self.dayIndex = dayIndex
        self.session = session
        self.setUpBufferMinutes = setUpBufferMinutes
        self.note = note
        self.driveNote = driveNote
    }

    // Files written before drive notes existed have no `driveNote` key.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        spot = try c.decode(Spot.self, forKey: .spot)
        dayIndex = try c.decode(Int.self, forKey: .dayIndex)
        session = try c.decode(LightWindowKind.self, forKey: .session)
        setUpBufferMinutes = try c.decode(Int.self, forKey: .setUpBufferMinutes)
        note = try c.decode(String.self, forKey: .note)
        driveNote = try c.decodeIfPresent(String.self, forKey: .driveNote) ?? ""
    }
}

/// When the overnight drive into a new area happens, chosen per transfer (keyed by the arriving day).
public enum TransferTiming: String, Codable, Sendable, CaseIterable {
    /// Drive on the day of the shoot; leave-by is worked backward from the first stop's arrival.
    case morning
    /// Drive after the previous stop's session ends, and sleep near the destination.
    case eveningBefore
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
    /// Timing of the transfer into each arriving day (a day after the first). Only non-morning entries need be stored.
    public var transferTimings: [Int: TransferTiming]

    public init(id: UUID = UUID(), name: String, startDay: LocalDay, dayCount: Int, stops: [TripStopPlan] = [], notes: String = "",
                transferTimings: [Int: TransferTiming] = [:]) {
        self.id = id
        self.name = name
        self.startDay = startDay
        self.dayCount = max(1, dayCount)
        self.stops = stops
        self.notes = notes
        self.transferTimings = transferTimings
    }

    // Files written before transfer timings existed have no `transferTimings` key.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        startDay = try c.decode(LocalDay.self, forKey: .startDay)
        dayCount = max(1, try c.decode(Int.self, forKey: .dayCount))
        stops = try c.decode([TripStopPlan].self, forKey: .stops)
        notes = try c.decode(String.self, forKey: .notes)
        transferTimings = try c.decodeIfPresent([Int: TransferTiming].self, forKey: .transferTimings) ?? [:]
    }

    /// The timing of the transfer into `day`: morning when absent, and always morning for the first day.
    public func transferTiming(intoDay day: Int) -> TransferTiming {
        day > 0 ? (transferTimings[day] ?? .morning) : .morning
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
    /// Which timing applied to the drive from the previous stop when that stop is on an earlier day; nil for a same-day
    /// drive and for the first stop. For `.eveningBefore`, `leaveBy` is the previous stop's window end.
    public var transferTiming: TransferTiming?

    public var id: UUID { stopID }

    public init(stopID: UUID, window: TimeSpan?, setUpBy: Date?, arriveBy: Date?, leaveBy: Date?, legFromPrevious: DriveLeg?,
                walkInKnown: Bool, issues: [ScheduleIssue], transferTiming: TransferTiming? = nil) {
        self.transferTiming = transferTiming
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
