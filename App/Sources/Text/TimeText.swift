import Foundation
import IterCore

/// Times are always shown in the spot's own zone (a sunrise in Utah is planned in Utah time).
enum TimeText {
    static func time(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }

    static func timeRange(_ span: TimeSpan, in zone: TimeZone) -> String {
        String(localized: "\(time(span.start, in: zone))–\(time(span.end, in: zone))", comment: "A time range, e.g. 6:12–6:48 PM")
    }

    /// "Tue 6 Oct"
    static func day(_ day: LocalDay) -> String {
        let utc = TimeZone(identifier: "UTC")!
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).weekday(.abbreviated)
        style.timeZone = utc
        return day.noon(in: utc).formatted(style)
    }

    /// "Tue"
    static func weekday(_ day: LocalDay) -> String {
        let utc = TimeZone(identifier: "UTC")!
        var style = Date.FormatStyle().weekday(.abbreviated)
        style.timeZone = utc
        return day.noon(in: utc).formatted(style)
    }

    /// "6"
    static func dayNumber(_ day: LocalDay) -> String {
        String(day.day)
    }

    /// "Tuesday, 6 October"
    static func longDay(_ day: LocalDay) -> String {
        let utc = TimeZone(identifier: "UTC")!
        var style = Date.FormatStyle().weekday(.wide).day().month(.wide)
        style.timeZone = utc
        return day.noon(in: utc).formatted(style)
    }

    /// "1 h 15 min"
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// "Updated 2:04 PM" in the Mac's zone.
    static func updated(_ date: Date) -> String {
        String(localized: "Updated \(date.formatted(date: .omitted, time: .shortened))", comment: "Forecast age")
    }

    /// Only when the spot's zone differs from the Mac's: "Mountain Time · 1 hr ahead of you". nil otherwise (C11).
    static func zoneNote(for zone: TimeZone, now: Date = .now, local: TimeZone = .current) -> String? {
        let diff = zone.secondsFromGMT(for: now) - local.secondsFromGMT(for: now)
        guard diff != 0 else { return nil }
        let name = zone.localizedName(for: zone.isDaylightSavingTime(for: now) ? .generic : .generic, locale: .current) ?? zone.identifier
        let hours = Double(abs(diff)) / 3600
        let amount = hours.formatted(.number.precision(.fractionLength(0...1)))
        return diff > 0
            ? String(localized: "\(name) · \(amount) h ahead of you", comment: "Spot time zone note, ahead")
            : String(localized: "\(name) · \(amount) h behind you", comment: "Spot time zone note, behind")
    }
}
