import Foundation
import IterModel
import IterSky

/// One stop as the builder shows it: the stop, its schedule, and the windows of its day at its place.
public struct TripStopEntry: Identifiable, Sendable, Equatable {
    public var stop: Stop
    /// 1-based position in the whole trip (the number on the map pin).
    public var number: Int
    public var schedule: StopSchedule?
    /// The stop before this one in trip order (possibly on an earlier day).
    public var previous: Stop?
    /// The trip's start place, on the trip's first stop only (the drive into it comes from there).
    public var startPlace: Place?
    /// Every window the sun produces on this stop's day at this place, with its score or "no forecast".
    public var windows: [LightWindow]
    /// The window for the stop's chosen session (light stops); nil when the sun does not produce it that day, and for lodging
    /// and waypoints.
    public var sessionWindow: LightWindow?

    public init(stop: Stop, number: Int, schedule: StopSchedule?, previous: Stop?, startPlace: Place? = nil, windows: [LightWindow],
                sessionWindow: LightWindow?) {
        self.stop = stop
        self.number = number
        self.schedule = schedule
        self.previous = previous
        self.startPlace = startPlace
        self.windows = windows
        self.sessionWindow = sessionWindow
    }

    public var id: UUID { stop.id }
    public var isOvernightFromPrevious: Bool { previous.map { $0.dayIndex != stop.dayIndex } ?? false }

    /// Schedule conflicts on this stop: a drive that does not fit, a backwards order, a window the sun does not produce.
    /// A straight-line drive estimate is a note, not a conflict (same rule as `TripSchedule.issueCount`).
    public var conflicts: [ScheduleIssue] { schedule?.conflicts ?? [] }

    /// How many seconds the drive into this stop is short of fitting, if it does not fit.
    public var driveShortBySeconds: TimeInterval? { schedule?.shortBySeconds }
}

/// One day of the trip with its stops and totals.
public struct TripDay: Identifiable, Sendable, Equatable {
    public var index: Int
    public var day: LocalDay
    public var stops: [TripStopEntry]
    /// Driving between this day's stops, plus the drive into its first stop from the day before (a morning transfer; an
    /// evening-before transfer counts toward the day before instead) or from the start place.
    public var drivingSeconds: TimeInterval
    /// Any of those drives is a straight-line estimate.
    public var hasEstimatedDrive: Bool
    /// Sun times at the first stop's place, in that place's zone. nil when the day has no stops.
    public var sunrise: Date?
    public var sunset: Date?
    public var timeZoneIdentifier: String?
    /// When the drive into this day's first stop happens (morning for the first day and when there is no such drive).
    public var transferTiming: TransferTiming

    public init(index: Int, day: LocalDay, stops: [TripStopEntry], drivingSeconds: TimeInterval, hasEstimatedDrive: Bool,
                sunrise: Date?, sunset: Date?, timeZoneIdentifier: String?, transferTiming: TransferTiming = .morning) {
        self.index = index
        self.day = day
        self.stops = stops
        self.drivingSeconds = drivingSeconds
        self.hasEstimatedDrive = hasEstimatedDrive
        self.sunrise = sunrise
        self.sunset = sunset
        self.timeZoneIdentifier = timeZoneIdentifier
        self.transferTiming = transferTiming
    }

    public var id: Int { index }
    public var timeZone: TimeZone { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .gmt }
}

/// Builds the days the builder lists. Pure: the caller supplies the schedule and each stop's day of light.
public enum TripDays {
    /// - `lights[stop.id]` is the `DayLight` at that stop's place on its day (`LightEngine.dayLight`). A stop with no entry is
    ///   still listed, with no windows (the old builder dropped such stops; a lodging or waypoint has no reason to need light).
    ///   The day's sunrise and sunset come from its first stop's `DayLight`.
    /// - Stops are numbered 1... across the whole trip in day-major order.
    public static func make(trip: Trip, start: Place?, schedule: TripSchedule, lights: [UUID: DayLight]) -> [TripDay] {
        var number = 0
        var previous: Stop?
        var entriesByDay: [[TripStopEntry]] = Array(repeating: [], count: trip.dayCount)
        var driving: [TimeInterval] = Array(repeating: 0, count: trip.dayCount)
        var estimated: [Bool] = Array(repeating: false, count: trip.dayCount)
        for index in 0..<trip.dayCount {
            for stop in trip.stops(onDay: index) {
                number += 1
                let entrySchedule = schedule.schedule(for: stop.id)
                if let leg = entrySchedule?.legFromPrevious {
                    // An evening-before transfer is driven the day before, after the previous stop.
                    var driveDay = index
                    if let previous, previous.dayIndex < index, trip.transferTiming(intoDay: index) == .eveningBefore {
                        driveDay = previous.dayIndex
                    }
                    driving[driveDay] += leg.seconds
                    if leg.isEstimate { estimated[driveDay] = true }
                }
                let light = lights[stop.id]
                let startPlace = previous == nil && entrySchedule?.fromStart == true ? start : nil
                entriesByDay[index].append(TripStopEntry(
                    stop: stop, number: number, schedule: entrySchedule, previous: previous, startPlace: startPlace,
                    windows: light?.windows ?? [], sessionWindow: stop.kind == .light ? light?.window(stop.session) : nil))
                previous = stop
            }
        }
        return (0..<trip.dayCount).map { index in
            let entries = entriesByDay[index]
            let first = entries.first.flatMap { lights[$0.id] }
            return TripDay(index: index, day: trip.day(index), stops: entries, drivingSeconds: driving[index],
                           hasEstimatedDrive: estimated[index], sunrise: first?.sun.sunrise, sunset: first?.sun.sunset,
                           timeZoneIdentifier: first?.timeZoneIdentifier, transferTiming: trip.transferTiming(intoDay: index))
        }
    }
}
