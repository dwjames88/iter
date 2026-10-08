import Foundation

/// A calendar day as seen at a place (year-month-day with no time and no zone).
/// Trips and light windows are planned in the local day of the spot, not the Mac's.
public struct LocalDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local day that contains `date` in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let c = LocalDay.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Parses "YYYY-MM-DD". A date that does not exist ("2026-02-30") is nil, not rolled into March.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...LocalDay.daysInMonth(year: parts[0], month: parts[1])).contains(parts[2])
        else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Days in a Gregorian month (`month` 1...12).
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Midnight at the start of this day in `timeZone`.
    public func start(in timeZone: TimeZone) -> Date {
        LocalDay.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Local noon in `timeZone`; a safe anchor for "which day" in sun calculations.
    public func noon(in timeZone: TimeZone) -> Date {
        LocalDay.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// The instant at `hour:minute` local time on this day.
    public func at(hour: Int, minute: Int = 0, in timeZone: TimeZone) -> Date {
        LocalDay.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    public func adding(days: Int) -> LocalDay {
        let utc = TimeZone(identifier: "UTC")!
        let d = LocalDay.calendar(utc).date(byAdding: .day, value: days, to: noon(in: utc))!
        return LocalDay(d, in: utc)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: LocalDay) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return LocalDay.calendar(utc).dateComponents([.day], from: noon(in: utc), to: other.noon(in: utc)).day!
    }

    /// Day of year, 1...366.
    public var ordinal: Int {
        let utc = TimeZone(identifier: "UTC")!
        return LocalDay.calendar(utc).ordinality(of: .day, in: .year, for: noon(in: utc))!
    }

    public static func today(in timeZone: TimeZone, now: Date = .now) -> LocalDay {
        LocalDay(now, in: timeZone)
    }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}

/// A closed span of time, e.g. a light window or a drive.
public struct TimeSpan: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var midpoint: Date { start.addingTimeInterval(duration / 2) }
    public func contains(_ date: Date) -> Bool { date >= start && date <= end }
}
