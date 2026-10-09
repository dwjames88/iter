import Foundation
import IterCore

extension TripStopEntry {
    /// Schedule conflicts on this stop: a drive that does not fit, a backwards order, a window the sun does not produce.
    /// A straight-line drive estimate is a note, not a conflict (same rule as `TripSchedule.issueCount`).
    public var conflicts: [ScheduleIssue] {
        (schedule?.issues ?? []).filter { $0 != .driveEstimated }
    }

    /// How many seconds the drive into this stop is short of fitting, if it does not fit.
    public var driveShortBySeconds: TimeInterval? {
        for issue in schedule?.issues ?? [] {
            if case .driveDoesNotFit(let seconds) = issue { return seconds }
        }
        return nil
    }
}

/// A drive on the day timeline: into a day's first stop from the day before (`driveIn`), or between two stops of one day.
/// It always belongs to the day of the stop it arrives at.
public struct TripDriveItem: Identifiable, Sendable, Equatable {
    /// The stop the drive arrives at.
    public var toStopID: UUID
    /// The stop the drive leaves from (possibly on an earlier day).
    public var fromName: String
    public var fromLocality: String
    /// nil until the drive has been fetched or estimated.
    public var leg: DriveLeg?
    /// When to leave, in `leaveZone`.
    public var leaveBy: Date?
    /// The time zone of the stop you leave from.
    public var leaveZone: TimeZone
    /// How far the drive is from fitting, nil when it fits.
    public var shortBySeconds: TimeInterval?

    public var id: UUID { toStopID }
    public var fits: Bool { shortBySeconds == nil }
    public var isEstimate: Bool { leg?.isEstimate ?? false }
}

/// One row of a day's timeline, top to bottom.
public enum TripTimelineItem: Identifiable, Sendable, Equatable {
    /// The drive from the previous day's last stop into this day's first stop.
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
    public var spotName: String
    public var locality: String

    public var id: Int { afterDay }
    /// "Page, AZ", or the spot's name when it has no locality.
    public var place: String { locality.isEmpty ? spotName : locality }
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

/// One day's cell in the overview strip.
public struct TripOverviewCell: Identifiable, Sendable, Equatable {
    public var index: Int
    public var date: LocalDay
    public var stopCount: Int
    public var bestWindow: TripDayBestWindow?
    public var hasConflict: Bool
    public var conflictCount: Int

    public var id: Int { index }
}

/// The day-first shape of a trip: day groups with their timelines, the overnight boundaries and the overview cells.
/// A pure value built from the builder's days and suggestions; it holds no state of its own.
public struct TripDayLayout: Sendable, Equatable {
    public var groups: [TripDayGroup]

    public init(groups: [TripDayGroup]) { self.groups = groups }

    public var overviewCells: [TripOverviewCell] {
        groups.map {
            TripOverviewCell(index: $0.index, date: $0.date, stopCount: $0.stopCount, bestWindow: $0.bestWindow,
                             hasConflict: $0.hasConflict, conflictCount: $0.conflictCount)
        }
    }

    public func group(forDay index: Int) -> TripDayGroup? { groups.first { $0.index == index } }

    /// The day a stop is on.
    public func day(ofStop id: UUID) -> Int? {
        groups.first { $0.stops.contains { $0.id == id } }?.index
    }

    public static func make(days: [TripDay], suggestions: [OrderingSuggestion]) -> TripDayLayout {
        var groups: [TripDayGroup] = []
        for day in days {
            var items: [TripTimelineItem] = []
            for (position, entry) in day.stops.enumerated() {
                if let previous = entry.previous {
                    let drive = driveItem(into: entry, from: previous)
                    items.append(position == 0 ? .driveIn(drive) : .drive(drive))
                }
                items.append(.stop(entry))
            }
            items.append(.addStop(day: day.index))

            let sessions = day.stops.compactMap { entry in
                entry.sessionWindow.map { TripDayBestWindow(stopID: entry.id, window: $0, zone: entry.stop.spot.timeZone) }
            }
            // Highest score wins; the earliest stop wins a tie. With no score anywhere, the first stop's window.
            var best: TripDayBestWindow?
            for candidate in sessions {
                guard let score = candidate.window.score else { continue }
                if score > (best?.window.score ?? -1) { best = candidate }
            }
            if best == nil, let first = day.stops.first, let window = first.sessionWindow {
                best = TripDayBestWindow(stopID: first.id, window: window, zone: first.stop.spot.timeZone)
            }

            groups.append(TripDayGroup(
                index: day.index, date: day.day, sunrise: day.sunrise, sunset: day.sunset, timeZone: day.timeZone,
                stopCount: day.stops.count, drivingSeconds: day.drivingSeconds, hasEstimatedDrive: day.hasEstimatedDrive,
                bestWindow: best, conflictCount: day.stops.reduce(0) { $0 + $1.conflicts.count },
                suggestion: suggestions.first { $0.dayIndex == day.index }, items: items, overnightAfter: nil))
        }
        // Where you sleep: the most recent stop of this or an earlier day (a day with no stops keeps you where you were).
        var lastStop: TripStopEntry?
        for position in groups.indices.dropLast() {
            if let last = days[position].stops.last { lastStop = last }
            if let lastStop {
                groups[position].overnightAfter = OvernightBoundary(afterDay: groups[position].index,
                                                                    spotName: lastStop.stop.spot.name,
                                                                    locality: lastStop.stop.spot.locality)
            }
        }
        return TripDayLayout(groups: groups)
    }

    private static func driveItem(into entry: TripStopEntry, from previous: TripStopPlan) -> TripDriveItem {
        TripDriveItem(toStopID: entry.id, fromName: previous.spot.name, fromLocality: previous.spot.locality,
                      leg: entry.schedule?.legFromPrevious, leaveBy: entry.schedule?.leaveBy,
                      leaveZone: previous.spot.timeZone, shortBySeconds: entry.driveShortBySeconds)
    }
}
