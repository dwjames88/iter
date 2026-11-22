import Foundation
import IterModel

/// Times, days, durations and distances as words. Every function takes an explicit `Locale` (and `TimeZone` where a
/// clock time is involved) so output is deterministic; the defaults follow the device. Times follow the locale's 12 or
/// 24 hour convention through `Date.FormatStyle`, in the spot's own zone (a sunrise in Utah is planned in Utah time).
public enum TimeText {
    private static let utc = TimeZone(identifier: "UTC")!

    private static func utcCalendar(_ locale: Locale) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        cal.locale = locale
        return cal
    }

    // MARK: Clock times

    /// "5:45 AM" (en_US) or "05:45" (en_GB, de_DE).
    public static func time(_ date: Date, in zone: TimeZone, locale: Locale = .current) -> String {
        let cal = calendarFor(locale, zone)
        let uses12Hour = locale.hourCycle == .zeroToEleven || locale.hourCycle == .oneToTwelve
        if uses12Hour {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: cal, timeZone: zone))
        }
        // 24-hour locales always show two digits, so ranges line up: "05:45–06:20".
        let style = Date.FormatStyle(locale: locale, calendar: cal, timeZone: zone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return date.formatted(style)
    }

    /// "05:45–06:20" (24 hour locales) or "5:45 AM–6:20 AM" (12 hour locales).
    public static func timeRange(_ span: TimeSpan, in zone: TimeZone, locale: Locale = .current) -> String {
        let start = time(span.start, in: zone, locale: locale)
        let end = time(span.end, in: zone, locale: locale)
        return String(localized: "\(start)–\(end)", bundle: .module, locale: locale, comment: "A time range, e.g. 6:12 PM–6:48 PM")
    }

    private static func calendarFor(_ locale: Locale, _ zone: TimeZone) -> Calendar {
        var cal = locale.calendar
        cal.timeZone = zone
        return cal
    }

    // MARK: Days

    private static func dayDate(_ day: LocalDay, _ locale: Locale) -> Date { day.noon(in: utc) }

    private static func dayStyle(_ locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: utcCalendar(locale), timeZone: utc)
    }

    /// "Tue, 6 Oct" (en_GB) / "Tue, Oct 6" (en_US): weekday, day and month, abbreviated.
    public static func day(_ day: LocalDay, locale: Locale = .current) -> String {
        dayDate(day, locale).formatted(dayStyle(locale).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Tue"
    public static func weekday(_ day: LocalDay, locale: Locale = .current) -> String {
        dayDate(day, locale).formatted(dayStyle(locale).weekday(.abbreviated))
    }

    /// "6"
    public static func dayNumber(_ day: LocalDay, locale: Locale = .current) -> String {
        day.day.formatted(.number.locale(locale).grouping(.never))
    }

    /// "Tuesday, 6 October"
    public static func longDay(_ day: LocalDay, locale: Locale = .current) -> String {
        dayDate(day, locale).formatted(dayStyle(locale).weekday(.wide).day().month(.wide))
    }

    /// "Today", "Tomorrow", "Yesterday", otherwise `day(_:)`. `today` is the current day in the spot's zone.
    public static func relativeDay(_ day: LocalDay, today: LocalDay, locale: Locale = .current) -> String {
        switch today.days(until: day) {
        case 0: String(localized: "Today", bundle: .module, locale: locale, comment: "Relative day")
        case 1: String(localized: "Tomorrow", bundle: .module, locale: locale, comment: "Relative day")
        case -1: String(localized: "Yesterday", bundle: .module, locale: locale, comment: "Relative day")
        default: Self.day(day, locale: locale)
        }
    }

    // MARK: Durations

    /// How wide a duration is written.
    public enum DurationWidth: Sendable { case wide, abbreviated, narrow }

    /// "1 hr, 20 min" (abbreviated), "1 hour, 20 minutes" (wide), "1h 20m" (narrow). Hours and minutes only;
    /// under a minute reads "0 min". Rounds to the nearest minute.
    public static func duration(_ seconds: TimeInterval, width: DurationWidth = .abbreviated, locale: Locale = .current) -> String {
        let minutes = Int((seconds / 60).rounded())
        let w: Duration.UnitsFormatStyle.UnitWidth = switch width {
        case .wide: .wide
        case .abbreviated: .abbreviated
        case .narrow: .narrow
        }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: w, maximumUnitCount: 2, zeroValueUnits: .hide).locale(locale))
            .nonEmpty ?? Duration.seconds(0).formatted(.units(allowed: [.minutes], width: w, zeroValueUnits: .show(length: 1)).locale(locale))
    }

    // MARK: Distances

    /// "194 mi" or "312 km": the unit follows the locale's road convention. `meters` is always metric.
    public static func distance(meters: Double, locale: Locale = .current) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// Distance in kilometres input, same output as `distance(meters:)`.
    public static func distance(kilometers: Double, locale: Locale = .current) -> String {
        distance(meters: kilometers * 1000, locale: locale)
    }

    // MARK: Zones

    /// Only when the spot's zone differs from the device's: "Mountain Time · 1 hr ahead of you". nil otherwise.
    public static func zoneNote(for zone: TimeZone, now: Date, local: TimeZone = .autoupdatingCurrent,
                                locale: Locale = .current) -> String? {
        let diff = zone.secondsFromGMT(for: now) - local.secondsFromGMT(for: now)
        guard diff != 0 else { return nil }
        let name = zone.localizedName(for: .generic, locale: locale) ?? zone.identifier
        let amount = (Double(abs(diff)) / 3600).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return diff > 0
            ? String(localized: "\(name) · \(amount) hr ahead of you", bundle: .module, locale: locale, comment: "Spot time zone note, ahead")
            : String(localized: "\(name) · \(amount) hr behind you", bundle: .module, locale: locale, comment: "Spot time zone note, behind")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
