import Foundation
import IterModel
import IterSky

/// A drive on the day timeline: into a day's first stop from the day before or from the trip's start place (`driveIn`), or
/// between two stops of one day. It always belongs to the day of the stop it arrives at.
public struct TripDriveItem: Identifiable, Sendable, Equatable {
    /// The stop the drive arrives at.
    public var toStopID: UUID
    /// What the drive leaves from: the previous stop's name, or the start place's.
    public var fromName: String
    public var fromLocality: String
    /// True when the drive leaves from the trip's start place rather than a stop.
    public var fromStart: Bool
    /// nil until the drive has been fetched or estimated.
    public var leg: Leg?
    /// When to leave, in `leaveZone`.
    public var leaveBy: Date?
    /// The time zone of the place you leave from.
    public var leaveZone: TimeZone
    /// How far the drive is from fitting, nil when it fits.
    public var shortBySeconds: TimeInterval?
    /// When the drive happens, for a transfer into a day's first stop; nil for a drive between two stops of one day and for the
    /// drive from the start place.
    public var transferTiming: TransferTiming?
    /// The note about this drive (the arriving stop's `driveNote`).
    public var note: String = ""

    public var id: UUID { toStopID }
    public var fits: Bool { shortBySeconds == nil }
    public var isEstimate: Bool { leg?.isEstimate ?? false }
}

/// One row of a day's timeline, top to bottom.
public enum TripTimelineItem: Identifiable, Sendable, Equatable {
    /// The drive into this day's first stop: from the previous day's last stop, or, on the trip's first stop, from the start place.
    case driveIn(TripDriveItem)
    case stop(TripStopEntry)
    /// The drive between two stops of the same day.
    case drive(TripDriveItem)
    case addStop(day: Int)

    public var id: String {
        switch self {
        case .driveIn(let drive): "driveIn-\(drive.toStopID)"
        case .stop(let entry): "stop-\(entry.id)"
        case .drive(let drive): "drive-\(drive.toStopID)"
        case .addStop(let day): "addStop-\(day)"
        }
    }

    public var isDrive: Bool {
        switch self {
        case .driveIn, .drive: true
        case .stop, .addStop: false
        }
    }
}

/// The best light of a day: the stop's session window and the zone its times are read in.
public struct TripDayBestWindow: Sendable, Equatable {
    public var stopID: UUID
    public var window: LightWindow
    public var zone: TimeZone
}

/// Where you sleep between two days.
public struct OvernightBoundary: Sendable, Equatable, Identifiable {
    /// The day before the night; the boundary sits between this day and the next.
    public var afterDay: Int
    public var placeName: String
    public var locality: String
    /// Where the sleeping stop's place is (for finding hotels near it).
    public var coordinate: Coordinate

    public var id: Int { afterDay }
    /// "Page, AZ", or the place's name when it has no locality.
    public var place: String { locality.isEmpty ? placeName : locality }
}

/// One day of the trip as the builder lists it.
public struct TripDayGroup: Identifiable, Sendable, Equatable {
    public var index: Int
    public var date: LocalDay
    /// The day's light bookends, at its first stop's place (nil with no stops).
    public var sunrise: Date?
    public var sunset: Date?
    public var timeZone: TimeZone
    public var stopCount: Int
    public var drivingSeconds: TimeInterval
    public var hasEstimatedDrive: Bool
    public var bestWindow: TripDayBestWindow?
    public var conflictCount: Int
    public var suggestion: OrderingSuggestion?
    public var items: [TripTimelineItem]
    /// Where you sleep after this day; nil for the last day, and before any stop has been placed.
    public var overnightAfter: OvernightBoundary?

    public var id: Int { index }
    public var hasConflict: Bool { conflictCount > 0 }

    public var stops: [TripStopEntry] {
        items.compactMap { if case .stop(let entry) = $0 { entry } else { nil } }
    }
}

/// The day-first shape of a trip: day groups with their timelines and the overnight boundaries. A pure value built from the
/// builder's days and suggestions; it holds no state of its own.
public struct TripDayLayout: Sendable, Equatable {
    public var groups: [TripDayGroup]

    public init(groups: [TripDayGroup]) { self.groups = groups }

    public func group(forDay index: Int) -> TripDayGroup? { groups.first { $0.index == index } }

    /// The day a stop is on.
    public func day(ofStop id: UUID) -> Int? {
        groups.first { $0.stops.contains { $0.id == id } }?.index
    }

    /// The layout straight from a trip: `TripDays.make` then `make(days:suggestions:)`.
    public static func make(trip: Trip, start: Place?, schedule: TripSchedule, lights: [UUID: DayLight],
                            suggestions: [OrderingSuggestion]) -> TripDayLayout {
        make(days: TripDays.make(trip: trip, start: start, schedule: schedule, lights: lights), suggestions: suggestions)
    }

    public static func make(days: [TripDay], suggestions: [OrderingSuggestion]) -> TripDayLayout {
        var groups: [TripDayGroup] = []
        for day in days {
            var items: [TripTimelineItem] = []
            for (position, entry) in day.stops.enumerated() {
                if let drive = driveItem(into: entry) {
                    items.append(position == 0 ? .driveIn(drive) : .drive(drive))
                }
                items.append(.stop(entry))
            }
            items.append(.addStop(day: day.index))

            let sessions = day.stops.compactMap { entry in
                entry.sessionWindow.map { TripDayBestWindow(stopID: entry.id, window: $0, zone: entry.stop.place.timeZone) }
            }
            // Highest score wins; the earliest stop wins a tie. With no score anywhere, the first stop's window.
            var best: TripDayBestWindow?
            for candidate in sessions {
                guard let score = candidate.window.score else { continue }
                if score > (best?.window.score ?? -1) { best = candidate }
            }
            if best == nil, let first = day.stops.first, let window = first.sessionWindow {
                best = TripDayBestWindow(stopID: first.id, window: window, zone: first.stop.place.timeZone)
            }

            groups.append(TripDayGroup(
                index: day.index, date: day.day, sunrise: day.sunrise, sunset: day.sunset, timeZone: day.timeZone,
                stopCount: day.stops.count, drivingSeconds: day.drivingSeconds, hasEstimatedDrive: day.hasEstimatedDrive,
                bestWindow: best, conflictCount: day.stops.reduce(0) { $0 + $1.conflicts.count },
                suggestion: suggestions.first { $0.dayIndex == day.index }, items: items, overnightAfter: nil))
        }
        // Where you sleep: the most recent stop of this or an earlier day (a day with no stops keeps you where you were).
        // Before an evening-before transfer into the next day, you sleep near that day's first stop, the destination.
        var lastStop: TripStopEntry?
        for position in groups.indices.dropLast() {
            if let last = days[position].stops.last { lastStop = last }
            var sleeping = lastStop
            let next = days[position + 1]
            if lastStop != nil, next.transferTiming == .eveningBefore, let destination = next.stops.first {
                sleeping = destination
            }
            if let sleeping {
                groups[position].overnightAfter = OvernightBoundary(afterDay: groups[position].index,
                                                                    placeName: sleeping.stop.place.name,
                                                                    locality: sleeping.stop.place.locality,
                                                                    coordinate: sleeping.stop.place.coordinate)
            }
        }
        return TripDayLayout(groups: groups)
    }

    /// The drive into `entry`: from the previous stop, or from the start place for the trip's first stop. nil when there is
    /// neither (a first stop with no start place).
    private static func driveItem(into entry: TripStopEntry) -> TripDriveItem? {
        if let previous = entry.previous {
            return TripDriveItem(toStopID: entry.id, fromName: previous.place.name, fromLocality: previous.place.locality, fromStart: false,
                                 leg: entry.schedule?.legFromPrevious, leaveBy: entry.schedule?.leaveBy,
                                 leaveZone: previous.place.timeZone, shortBySeconds: entry.driveShortBySeconds,
                                 transferTiming: entry.schedule?.transferTiming, note: entry.stop.driveNote)
        }
        if let start = entry.startPlace {
            return TripDriveItem(toStopID: entry.id, fromName: start.name, fromLocality: start.locality, fromStart: true,
                                 leg: entry.schedule?.legFromPrevious, leaveBy: entry.schedule?.leaveBy,
                                 leaveZone: start.timeZone, shortBySeconds: nil, transferTiming: nil, note: entry.stop.driveNote)
        }
        return nil
    }
}
