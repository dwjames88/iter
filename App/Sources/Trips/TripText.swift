import Foundation
import IterCore
import IterFeatures

/// Trip phrasing: dates, schedules, issues, connectors. Everything that reads as a sentence goes through the String Catalog.
extension TimeText {
    private static var utc: TimeZone { TimeZone(identifier: "UTC")! }

    /// "Wed 7 – Sat 10 Oct" (the month appears once when both ends share it); a one-day trip is just "Wed 7 Oct".
    static func dateRange(from start: LocalDay, to end: LocalDay) -> String {
        if start == end { return day(start) }
        let sameMonth = start.year == end.year && start.month == end.month
        var short = Date.FormatStyle().weekday(.abbreviated).day()
        short.timeZone = utc
        if !sameMonth { short = short.month(.abbreviated) }
        var full = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        full.timeZone = utc
        let a = start.noon(in: utc).formatted(short)
        let b = end.noon(in: utc).formatted(full)
        return String(localized: "\(a) – \(b)", comment: "Trip date range, e.g. Wed 7 – Sat 10 Oct")
    }

    static func dayAndStops(days: Int, stops: Int) -> String {
        String(localized: "\(days) days · \(stops) stops", comment: "Trip size on a trip card, e.g. 4 days · 6 stops")
    }

    /// "Day 2 · Thu, Oct 8, 2026"
    static func tripDay(index: Int, day: LocalDay) -> String {
        String(localized: "Day \(index + 1) · \(self.day(day))", comment: "Trip day header, e.g. Day 2 · Wed 7 Oct")
    }
}

extension LightText {
    /// "Sunrise from 7:12 AM, Thu": a window's start, in the spot's own zone.
    static func windowStart(_ kind: LightWindowKind, at start: Date, day: LocalDay, in zone: TimeZone) -> String {
        String(localized: "\(name(kind)) from \(TimeText.time(start, in: zone)), \(TimeText.weekday(day))",
               comment: "A light window and when it starts, e.g. Sunrise from 7:12 AM, Thu")
    }

    /// "Next: Mesa Arch · Sunrise from 7:12 AM, Thu"
    static func nextSession(_ next: NextSession) -> String {
        String(localized: "Next: \(next.spotName) · \(windowStart(next.kind, at: next.start, day: next.day, in: next.timeZone))",
               comment: "A trip's next session on its card")
    }

    /// "Sunrise · 6:12–6:48 AM": the session menu's label.
    static func sessionLabel(_ window: LightWindow, in zone: TimeZone) -> String {
        String(localized: "\(name(window.kind)) · \(TimeText.timeRange(window.span, in: zone))",
               comment: "Session menu item: window name and its time range")
    }

    /// The session menu item with the score that day: "Sunrise · 6:12–6:48 AM · 64".
    static func sessionMenuItem(_ window: LightWindow, in zone: TimeZone) -> String {
        let base = sessionLabel(window, in: zone)
        if let score = window.score {
            return String(localized: "\(base) · \(score)", comment: "Session menu item with its score")
        }
        return String(localized: "\(base) · \(noForecastShort(window.assessment.noForecastReason))", comment: "Session menu item with no forecast")
    }

    static func noSession(_ kind: LightWindowKind) -> String {
        String(localized: "\(name(kind)) · no window this day", comment: "A stop's session that the sun does not produce that day")
    }

    /// "Sunrise 7:12 AM · Sunset 6:48 PM": a day's light frame.
    static func dayFrame(sunrise: Date?, sunset: Date?, in zone: TimeZone) -> String? {
        switch (sunrise, sunset) {
        case let (rise?, set?):
            String(localized: "Sunrise \(TimeText.time(rise, in: zone)) · Sunset \(TimeText.time(set, in: zone))", comment: "A day's sunrise and sunset")
        case let (rise?, nil):
            String(localized: "Sunrise \(TimeText.time(rise, in: zone))", comment: "A day's sunrise only")
        case let (nil, set?):
            String(localized: "Sunset \(TimeText.time(set, in: zone))", comment: "A day's sunset only")
        case (nil, nil):
            nil
        }
    }

    /// "3 stops · 2 h 10 min driving"
    static func dayTotals(stops: Int, drivingSeconds: TimeInterval) -> String {
        guard stops > 0 else { return String(localized: "No stops yet", comment: "Day header for a day with no stops") }
        let count = String(AttributedString(localized: "^[\(stops) stop](inflect: true)").characters)
        if drivingSeconds < 60 { return count }
        return String(localized: "\(count) · \(TimeText.duration(drivingSeconds)) driving", comment: "Day total: stops and driving time")
    }
}

extension LightAssessment {
    /// The reason when there is no forecast; `.notLoaded` for a scored window (never read in that case).
    var noForecastReason: ForecastUnavailableReason {
        if case .noForecast(let reason) = self { return reason }
        return .notLoaded
    }
}

/// The backward schedule and its issues, phrased.
enum ScheduleText {
    /// "Leave 4:10 AM · park 5:42 AM · set up by 5:52 AM" (the headline). The first stop of the trip has no drive:
    /// "Set up by 5:52 AM". `previousZone` is where you leave from.
    static func headline(_ schedule: StopSchedule, in zone: TimeZone, leavingFrom previousZone: TimeZone?) -> String? {
        guard let setUpBy = schedule.setUpBy else { return nil }
        let setUp = TimeText.time(setUpBy, in: zone)
        guard let leaveBy = schedule.leaveBy else {
            return String(localized: "Set up by \(setUp)", comment: "Backward schedule for the first stop of a trip")
        }
        let leave = TimeText.time(leaveBy, in: previousZone ?? zone)
        if schedule.walkInKnown, let arriveBy = schedule.arriveBy, arriveBy != setUpBy {
            return String(localized: "Leave \(leave) · park \(TimeText.time(arriveBy, in: zone)) · set up by \(setUp)",
                          comment: "Backward schedule: leave, park, set up")
        }
        return String(localized: "Leave \(leave) · set up by \(setUp)", comment: "Backward schedule: leave and set up")
    }

    static func walkIn(minutes: Int?) -> String {
        guard let minutes else { return String(localized: "walk-in unknown", comment: "Walk from parking to the shooting spot is not known") }
        return String(localized: "\(minutes) min walk-in", comment: "Walk from parking to the shooting spot")
    }

    static func buffer(minutes: Int) -> String {
        String(localized: "\(minutes) min set-up", comment: "Minutes to be set up before the window starts")
    }

    /// "Drive doesn't fit: 25 min short"
    static func driveDoesNotFit(shortBy seconds: TimeInterval) -> String {
        String(localized: "Drive doesn't fit: \(TimeText.duration(max(60, seconds))) short", comment: "Schedule issue: the drive takes longer than the time available")
    }

    /// "Out of order: this Sunrise is earlier than the previous stop's Sunset"
    static func outOfOrder(this: LightWindowKind, previous: LightWindowKind) -> String {
        String(localized: "Out of order: this \(LightText.name(this)) is earlier than the previous stop's \(LightText.name(previous))",
               comment: "Schedule issue: the stop's window starts before the previous stop's window on the same day")
    }

    static func windowMissing(_ kind: LightWindowKind) -> String {
        String(localized: "No \(LightText.name(kind)) window on this day at this place", comment: "Schedule issue: the sun does not produce this window that day")
    }

    /// Issue lines for a stop's row. Drive conflicts and estimates belong to the connector, not the row.
    static func rowIssues(for entry: TripStopEntry) -> [String] {
        guard let schedule = entry.schedule else { return [] }
        var lines: [String] = []
        for issue in schedule.issues {
            switch issue {
            case .outOfOrder:
                if let previous = entry.previous {
                    lines.append(outOfOrder(this: entry.stop.session, previous: previous.session))
                }
            case .windowMissing:
                lines.append(windowMissing(entry.stop.session))
            case .driveDoesNotFit, .driveEstimated:
                break
            }
        }
        return lines
    }
}

/// The line between two stops.
enum ConnectorText {
    /// "1 h 15 min · 82 km"
    static func drive(_ leg: DriveLeg) -> String {
        String(localized: "\(TimeText.duration(leg.seconds)) · \(TimeText.distance(leg.meters))", comment: "Drive time and distance between two stops")
    }

    static let estimated = String(localized: "estimated", comment: "Marks a drive time that is a straight-line estimate, not a road route")
    static let overnight = String(localized: "Overnight", comment: "Divider between two trip days")
    static let driveEstimatedHelp = String(localized: "Drive time estimated", comment: "Explains an estimated drive")
}
