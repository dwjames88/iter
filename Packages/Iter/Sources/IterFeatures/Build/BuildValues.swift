import Foundation
import IterModel
import IterPlan
import IterSky

// The plain values the Trip Builder shows. Every one is `Equatable` and `Sendable`, carries no view type and no localized
// string except the few `message` helpers (English by default, locale-aware), so a view maps them straight onto the
// IterUI components (`StopCard`, `DriveSegmentRow`, `DayCardHeader`, `DaySelectorItem`, ...) and a row that did not change
// does not redraw.

// MARK: Issues

/// One problem with a stop's schedule, as a message the card can print.
public enum BuildIssue: Equatable, Sendable {
    /// The drive into the stop arrives after you need to be there (or you would have to leave before you are free).
    case driveDoesNotFit(shortBySeconds: TimeInterval)
    /// This stop's window starts before the one above it on the same day.
    case outOfOrder
    /// The sun does not make this window on this day (polar day or night).
    case windowMissing

    init?(_ issue: ScheduleIssue) {
        switch issue {
        case .driveDoesNotFit(let s): self = .driveDoesNotFit(shortBySeconds: s)
        case .outOfOrder: self = .outOfOrder
        case .windowMissing: self = .windowMissing
        case .driveEstimated: return nil
        }
    }

    public func message(locale: Locale = .current) -> String {
        switch self {
        case .driveDoesNotFit(let seconds):
            "Drive doesn't fit: \(BuildText.duration(max(seconds, 60), locale: locale)) short"
        case .outOfOrder:
            "This window starts before the stop above it"
        case .windowMissing:
            "The sun doesn't make this window on this day"
        }
    }
}

enum BuildText {
    /// "25 min", "1 hr, 5 min": whole minutes, rounded up.
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated,
                                                                maximumUnitCount: 2).locale(locale))
    }
}

// MARK: Light windows

/// One window the sun makes at a stop that day, with its score (nil until a forecast has one).
/// The same fields as `LightWindowPicker.Option`.
public struct BuildWindowOption: Equatable, Sendable, Identifiable {
    public var kind: LightWindowKind
    public var start: Date
    public var end: Date
    public var score: Int?
    public var id: LightWindowKind { kind }

    public init(kind: LightWindowKind, start: Date, end: Date, score: Int? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.score = score
    }
}

/// The best light of a day: the stop whose session scores highest (the earliest stop wins a tie; with no score anywhere, the
/// first stop's session).
public struct BuildBestWindow: Equatable, Sendable {
    public var stopID: UUID
    public var kind: LightWindowKind
    public var score: Int?
    public var start: Date
    public var end: Date
    public var timeZone: TimeZone

    public init(stopID: UUID, kind: LightWindowKind, score: Int?, start: Date, end: Date, timeZone: TimeZone) {
        self.stopID = stopID
        self.kind = kind
        self.score = score
        self.start = start
        self.end = end
        self.timeZone = timeZone
    }
}

// MARK: Header and day selector

/// The header card's facts.
public struct BuildHeader: Equatable, Sendable {
    public var name: String
    public var startDay: LocalDay
    public var endDay: LocalDay
    public var dayCount: Int
    public var stopCount: Int
    /// Every drive of the trip added up (the start place's drive included).
    public var drivingSeconds: TimeInterval
    public var drivingMeters: Double
    /// Some of that driving is a straight-line estimate.
    public var drivingIncludesEstimate: Bool
    /// Schedule conflicts across the trip (a drive estimate is not one).
    public var issueCount: Int
    public var isPinned: Bool

    public init(name: String, startDay: LocalDay, endDay: LocalDay, dayCount: Int, stopCount: Int, drivingSeconds: TimeInterval,
                drivingMeters: Double, drivingIncludesEstimate: Bool, issueCount: Int, isPinned: Bool) {
        self.name = name
        self.startDay = startDay
        self.endDay = endDay
        self.dayCount = dayCount
        self.stopCount = stopCount
        self.drivingSeconds = drivingSeconds
        self.drivingMeters = drivingMeters
        self.drivingIncludesEstimate = drivingIncludesEstimate
        self.issueCount = issueCount
        self.isPinned = isPinned
    }
}

/// One card of the day selector. `primarySession` and `stopCount` are what `DaySummary` takes; `bestScore` adds the day's
/// best-window score.
public struct BuildDayItem: Equatable, Sendable, Identifiable {
    public var index: Int
    public var date: LocalDay
    public var stopCount: Int
    /// The kind of the day's best window, else its first stop's session; nil with no stops.
    public var primarySession: LightWindowKind?
    public var bestScore: Int?
    public var hasConflict: Bool
    public var id: Int { index }

    public init(index: Int, date: LocalDay, stopCount: Int, primarySession: LightWindowKind?, bestScore: Int?, hasConflict: Bool) {
        self.index = index
        self.date = date
        self.stopCount = stopCount
        self.primarySession = primarySession
        self.bestScore = bestScore
        self.hasConflict = hasConflict
    }
}

// MARK: Rows

/// What the time on the left of a stop card is.
public enum BuildStopTimeLabel: Equatable, Sendable {
    /// A light stop: when you must be set up.
    case setUp
    /// A lodging or waypoint: when you arrive.
    case arrive
}

/// A stop card.
public struct BuildStop: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var placeID: UUID
    /// 1-based across the whole trip: the number on the map pin.
    public var number: Int
    public var name: String
    public var locality: String
    public var coordinate: Coordinate
    public var kind: StopKind
    public var session: LightWindowKind
    public var timeZone: TimeZone
    /// The time on the left of the card: set-up time for a light stop, arrival for a lodging or waypoint; nil when unknown.
    public var time: Date?
    public var timeLabel: BuildStopTimeLabel
    /// When to be at the car (set-up time minus the walk-in); nil without a window or fixed arrival.
    public var parkAt: Date?
    /// nil when the walk-in is not known (shown as unknown, never guessed).
    public var walkInMinutes: Int?
    public var setUpBufferMinutes: Int
    /// 0 means "until the window ends".
    public var dwellMinutes: Int
    /// When you are free to leave ("shoot until"); nil for an overnight lodging or a stop with no window.
    public var shootUntil: Date?
    public var fixedArrival: LocalTime?
    /// Every window the sun makes there that day, with its score (the light-window picker's menu).
    public var options: [BuildWindowOption]
    /// The chosen session's score for the score chip; nil until a forecast has one (and for lodging and waypoints).
    public var score: Int?
    /// A better score is still on its way (the forecast tier is not complete); the shown score is kept meanwhile.
    public var scoreIsImproving: Bool
    public var note: String
    public var issues: [BuildIssue]

    public init(id: UUID, placeID: UUID, number: Int, name: String, locality: String, coordinate: Coordinate, kind: StopKind,
                session: LightWindowKind, timeZone: TimeZone, time: Date?, timeLabel: BuildStopTimeLabel, parkAt: Date?,
                walkInMinutes: Int?, setUpBufferMinutes: Int, dwellMinutes: Int, shootUntil: Date?, fixedArrival: LocalTime?,
                options: [BuildWindowOption], score: Int?, scoreIsImproving: Bool, note: String, issues: [BuildIssue]) {
        self.id = id
        self.placeID = placeID
        self.number = number
        self.name = name
        self.locality = locality
        self.coordinate = coordinate
        self.kind = kind
        self.session = session
        self.timeZone = timeZone
        self.time = time
        self.timeLabel = timeLabel
        self.parkAt = parkAt
        self.walkInMinutes = walkInMinutes
        self.setUpBufferMinutes = setUpBufferMinutes
        self.dwellMinutes = dwellMinutes
        self.shootUntil = shootUntil
        self.fixedArrival = fixedArrival
        self.options = options
        self.score = score
        self.scoreIsImproving = scoreIsImproving
        self.note = note
        self.issues = issues
    }
}

/// What a drive's time rests on.
public enum DriveBasis: Equatable, Sendable {
    /// MapKit's traffic for this departure time.
    case trafficAware(departing: Date)
    /// MapKit's typical drive time (no departure time known, or it is beyond the traffic horizon).
    case typical
    /// No road route: a straight-line guess, labelled as such.
    case estimate

    /// "With traffic", "Typical" or "Estimated" (English; views may phrase it themselves).
    public var label: String {
        switch self {
        case .trafficAware: "With traffic"
        case .typical: "Typical"
        case .estimate: "Estimated"
        }
    }
}

/// Where a drive's lookup stands.
public enum DriveLegState: Equatable, Sendable {
    /// Being asked for (or queued); the row shows the estimate meanwhile.
    case loading
    /// A road route is known.
    case ready
    /// Throttled or offline; asked again at `retryAt`.
    case failed(retryAt: Date)
    /// MapKit has no road route between the two places. Final.
    case noRoute
}

/// A drive between two stops, into a day's first stop, or from the start place.
public struct BuildDrive: Equatable, Sendable, Identifiable {
    /// The stop the drive arrives at.
    public var toStopID: UUID
    public var fromName: String
    public var fromLocality: String
    public var fromStart: Bool
    public var state: DriveLegState
    /// nil only for the trip's first stop when there is no start place.
    public var seconds: TimeInterval?
    public var meters: Double?
    /// The time is a straight-line estimate (the same as `DriveSegmentRow.Drive.isEstimate`).
    public var isEstimate: Bool
    public var basis: DriveBasis?
    public var leaveBy: Date?
    public var leaveZone: TimeZone
    public var issue: BuildIssue?
    public var note: String
    /// For a transfer into a day: Morning or Evening Before.
    public var transferTiming: TransferTiming?

    public var id: UUID { toStopID }
    public var fits: Bool { issue == nil }

    public init(toStopID: UUID, fromName: String, fromLocality: String, fromStart: Bool, state: DriveLegState, seconds: TimeInterval?,
                meters: Double?, isEstimate: Bool, basis: DriveBasis?, leaveBy: Date?, leaveZone: TimeZone, issue: BuildIssue?,
                note: String, transferTiming: TransferTiming?) {
        self.toStopID = toStopID
        self.fromName = fromName
        self.fromLocality = fromLocality
        self.fromStart = fromStart
        self.state = state
        self.seconds = seconds
        self.meters = meters
        self.isEstimate = isEstimate
        self.basis = basis
        self.leaveBy = leaveBy
        self.leaveZone = leaveZone
        self.issue = issue
        self.note = note
        self.transferTiming = transferTiming
    }
}

/// Where you sleep, with what the Find Hotels button needs.
public struct BuildOvernight: Equatable, Sendable, Identifiable {
    /// The day before the night.
    public var afterDay: Int
    /// "Page, AZ", or the place's name when it has no locality.
    public var place: String
    public var coordinate: Coordinate
    public var id: Int { afterDay }

    public init(afterDay: Int, place: String, coordinate: Coordinate) {
        self.afterDay = afterDay
        self.place = place
        self.coordinate = coordinate
    }

    /// "Overnight near Page, AZ".
    public var text: String { "Overnight near \(place)" }

    /// The Apple Maps search for Hotels near the overnight (`maps://?q=Hotels&sll=lat,lon`), the same URL `FindHotelsButton` opens.
    public var findHotelsURL: URL? { URL(string: "maps://?q=Hotels&sll=\(coordinate.latitude),\(coordinate.longitude)") }
}

/// A day card's header.
public struct BuildDayHeader: Equatable, Sendable, Identifiable {
    public var index: Int
    public var date: LocalDay
    public var sunrise: Date?
    public var sunset: Date?
    public var timeZone: TimeZone
    public var stopCount: Int
    public var drivingSeconds: TimeInterval
    public var hasEstimatedDrive: Bool
    public var conflictCount: Int
    public var best: BuildBestWindow?
    public var id: Int { index }

    public init(index: Int, date: LocalDay, sunrise: Date?, sunset: Date?, timeZone: TimeZone, stopCount: Int,
                drivingSeconds: TimeInterval, hasEstimatedDrive: Bool, conflictCount: Int, best: BuildBestWindow?) {
        self.index = index
        self.date = date
        self.sunrise = sunrise
        self.sunset = sunset
        self.timeZone = timeZone
        self.stopCount = stopCount
        self.drivingSeconds = drivingSeconds
        self.hasEstimatedDrive = hasEstimatedDrive
        self.conflictCount = conflictCount
        self.best = best
    }
}

/// A light-first reordering the user can apply or dismiss.
public struct BuildSuggestion: Equatable, Sendable {
    public var dayIndex: Int
    /// Stop ids in the suggested order.
    public var order: [UUID]
    public var issuesBefore: Int
    public var issuesAfter: Int

    public init(dayIndex: Int, order: [UUID], issuesBefore: Int, issuesAfter: Int) {
        self.dayIndex = dayIndex
        self.order = order
        self.issuesBefore = issuesBefore
        self.issuesAfter = issuesAfter
    }

    /// "Putting the day in light order clears 2 conflicts".
    public var message: String {
        let fixed = max(1, issuesBefore - issuesAfter)
        return "Putting this day in light order clears \(fixed) \(fixed == 1 ? "conflict" : "conflicts")"
    }
}

/// The card between two days (or the first drive from the start place): the drive and the night.
public struct BuildTransfer: Equatable, Sendable {
    public var day: Int
    public var drive: BuildDrive?
    /// The timing the Morning / Evening Before picker shows (always Morning for the first day).
    public var timing: TransferTiming
    /// Whether the picker applies (a day after the first).
    public var canChooseTiming: Bool
    /// Where you slept the night before this day's drive, shown in the card.
    public var overnight: BuildOvernight?

    public init(day: Int, drive: BuildDrive?, timing: TransferTiming, canChooseTiming: Bool, overnight: BuildOvernight?) {
        self.day = day
        self.drive = drive
        self.timing = timing
        self.canChooseTiming = canChooseTiming
        self.overnight = overnight
    }
}

/// One row of the builder list, in order: day headers, stops, drives, the foot of each day, and transfer cards.
public struct BuildRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case dayHeader(BuildDayHeader)
        case suggestion(BuildSuggestion)
        case conflicts(Int)
        case stop(BuildStop)
        case drive(BuildDrive)
        /// "Add Stop" and, when the overnight is not in a transfer card, the overnight note with Find Hotels.
        case footer(day: Int, overnight: BuildOvernight?)
        case transfer(BuildTransfer)
    }

    public var id: String
    public var day: Int
    public var kind: Kind
    /// Where the row sits in its day card; nil for a transfer card.
    public var position: TripBuilderRowPosition?

    public init(id: String, day: Int, kind: Kind, position: TripBuilderRowPosition?) {
        self.id = id
        self.day = day
        self.kind = kind
        self.position = position
    }
}

// MARK: Start place

/// Where day 1 starts, and when to leave it for the first stop.
public struct BuildStartPlace: Equatable, Sendable {
    public var placeID: UUID
    public var name: String
    public var locality: String
    public var coordinate: Coordinate
    /// When to leave for the trip's first stop; nil until the drive's time is known.
    public var firstLeaveBy: Date?
    public var timeZone: TimeZone

    public init(placeID: UUID, name: String, locality: String, coordinate: Coordinate, firstLeaveBy: Date?, timeZone: TimeZone) {
        self.placeID = placeID
        self.name = name
        self.locality = locality
        self.coordinate = coordinate
        self.firstLeaveBy = firstLeaveBy
        self.timeZone = timeZone
    }
}

// MARK: Map

/// A numbered pin on the route map. Selection is separate (`BuildModel.selectedStopID`), so choosing a stop does not change
/// this value.
public struct BuildWaypoint: Equatable, Sendable, Identifiable {
    public var stopID: UUID
    public var number: Int
    public var coordinate: Coordinate
    public var kind: StopKind
    public var name: String
    public var day: Int
    public var id: UUID { stopID }

    public init(stopID: UUID, number: Int, coordinate: Coordinate, kind: StopKind, name: String, day: Int) {
        self.stopID = stopID
        self.number = number
        self.coordinate = coordinate
        self.kind = kind
        self.name = name
        self.day = day
    }
}

/// One drawn drive: its road path thinned for drawing.
public struct BuildMapLeg: Equatable, Sendable, Identifiable {
    public var toStopID: UUID
    /// The day of the stop it arrives at.
    public var day: Int
    public var path: [Coordinate]
    /// A straight line, drawn dashed.
    public var isEstimate: Bool
    public var id: UUID { toStopID }

    public init(toStopID: UUID, day: Int, path: [Coordinate], isEstimate: Bool) {
        self.toStopID = toStopID
        self.day = day
        self.path = path
        self.isEstimate = isEstimate
    }
}

/// Everything the route map draws. Equal across changes that do not touch the geometry (a selection, a note, a score).
public struct BuildMapContent: Equatable, Sendable {
    public var waypoints: [BuildWaypoint]
    public var legs: [BuildMapLeg]
    public var startCoordinate: Coordinate?

    public init(waypoints: [BuildWaypoint] = [], legs: [BuildMapLeg] = [], startCoordinate: Coordinate? = nil) {
        self.waypoints = waypoints
        self.legs = legs
        self.startCoordinate = startCoordinate
    }
}

// MARK: Conditions and packs

/// How far the conditions for the trip's stops have come.
public struct BuildConditionsProgress: Equatable, Sendable {
    public var totalStops: Int
    /// Stops whose forecast is complete.
    public var readyStops: Int
    /// Stops with a first score that a better forecast is still improving.
    public var improvingStops: Int
    /// Stops with no score yet.
    public var waitingStops: Int
    /// Stops still waiting on each forecast source, by display name ("NOAA", "MET Norway").
    public var pendingBySource: [String: Int]

    public init(totalStops: Int = 0, readyStops: Int = 0, improvingStops: Int = 0, waitingStops: Int = 0,
                pendingBySource: [String: Int] = [:]) {
        self.totalStops = totalStops
        self.readyStops = readyStops
        self.improvingStops = improvingStops
        self.waitingStops = waitingStops
        self.pendingBySource = pendingBySource
    }

    public var isComplete: Bool { totalStops > 0 && readyStops == totalStops }

    /// "Conditions: 4 of 9 stops ready; NOAA forecast still loading for 3". Empty for a trip with no stops.
    public var text: String {
        guard totalStops > 0 else { return "" }
        if isComplete { return "Conditions: \(totalStops == 1 ? "1 stop" : "all \(totalStops) stops") ready" }
        var text = "Conditions: \(readyStops) of \(totalStops) \(totalStops == 1 ? "stop" : "stops") ready"
        for (name, count) in pendingBySource.sorted(by: { ($1.value, $1.key) < ($0.value, $0.key) }) where count > 0 {
            text += "; \(name) forecast still loading for \(count)"
        }
        if waitingStops > 0 { text += "; waiting for a first score for \(waitingStops)" }
        return text
    }
}

/// The offline pack of a pinned trip.
public enum BuildPackState: Equatable, Sendable {
    /// No pack (the trip is not pinned, or none has been built).
    case none
    case building
    case ready(builtAt: Date)
    case failed
    /// Sample data: no pack is built, by design.
    case sampleData
    /// This library has no folder for packs (in memory), so none can be built. Not a failure.
    case unavailable
}

/// The `.iter` formats a trip can be shared in.
public enum BuildExportFormat: Sendable, Equatable {
    /// Format 2: stop kind, dwell, fixed arrivals, start place and library metadata. Merges by id on import.
    case v2
    /// Format 1, for Iter versions before the rebuild; leaves out what that format has no place for.
    case v1ForOlderIter
}
