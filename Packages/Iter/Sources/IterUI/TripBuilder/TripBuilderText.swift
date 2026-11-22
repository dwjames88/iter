import Foundation
import IterModel

/// The Trip Builder's phrases, locale-aware and zone-explicit, built on the package's `TimeText`, `InflectedCount` and
/// `LightText`. Views take the finished strings; the app (or the views' own convenience inits) call these.
public enum TripBuilderText {
    private static let utc = TimeZone(identifier: "UTC")!

    /// "Day 2"
    public static func dayName(index: Int, locale: Locale = .current) -> String {
        String(localized: "Day \(index + 1)", bundle: .module, locale: locale, comment: "A trip day's name, e.g. Day 2")
    }

    private static func dayStyle(_ locale: Locale) -> Date.FormatStyle {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        cal.locale = locale
        return Date.FormatStyle(locale: locale, calendar: cal, timeZone: utc)
    }

    /// "Tuesday": the selector card's weekday.
    public static func weekdayName(_ day: LocalDay, locale: Locale = .current) -> String {
        day.noon(in: utc).formatted(dayStyle(locale).weekday(.wide))
    }

    /// "Tuesday, Oct 6": a day card's date line.
    public static func dayCardDate(_ day: LocalDay, locale: Locale = .current) -> String {
        day.noon(in: utc).formatted(dayStyle(locale).weekday(.wide).month(.abbreviated).day())
    }

    /// "1 Stop", "2 Stops", "No Stops": a selector card's count, in title case.
    public static func stopCountTitle(_ count: Int, locale: Locale = .current) -> String {
        guard count > 0 else {
            return String(localized: "No Stops", bundle: .module, locale: locale, comment: "Day selector card of a day with no stops")
        }
        return InflectedCount.stops(count, locale: locale).capitalized(with: locale)
    }

    /// "4 days • 6 stops": the header's trip size.
    public static func tripSize(days: Int, stops: Int, locale: Locale = .current) -> String {
        let d = InflectedCount.days(days, locale: locale)
        let s = InflectedCount.stops(stops, locale: locale)
        return String(localized: "\(d) • \(s)", bundle: .module, locale: locale, comment: "Trip size in the builder header, e.g. 4 days • 6 stops")
    }

    /// "2 hr, 19 min • 101 mi": a drive's time and distance.
    public static func driveLine(seconds: TimeInterval, meters: Double, locale: Locale = .current) -> String {
        let t = TimeText.duration(seconds, locale: locale)
        let d = TimeText.distance(meters: meters, locale: locale)
        return String(localized: "\(t) • \(d)", bundle: .module, locale: locale, comment: "Drive time and distance between two stops")
    }

    /// "490 mi • 9 hr, 34 min": the header's driving total.
    public static func drivingTotal(seconds: TimeInterval, meters: Double, locale: Locale = .current) -> String {
        driveLine(seconds: seconds, meters: meters, locale: locale)
    }

    /// "1 stop", "2 stops • 5 hr, 26 min of driving", or "No stops yet": a day card's totals.
    public static func dayTotals(stops: Int, drivingSeconds: TimeInterval, locale: Locale = .current) -> String {
        guard stops > 0 else {
            return String(localized: "No stops yet", bundle: .module, locale: locale, comment: "Day header for a day with no stops")
        }
        let count = InflectedCount.stops(stops, locale: locale)
        if drivingSeconds < 60 { return count }
        let d = TimeText.duration(drivingSeconds, locale: locale)
        return String(localized: "\(count) • \(d) of driving", bundle: .module, locale: locale, comment: "Day card total: stops and driving time")
    }

    /// "Sunrise at 06:25" / "Sunset at 18:01" (`kind` is `.goldenMorning` or anything else for sunset).
    public static func sunTime(_ kind: LightWindowKind, at time: Date, in zone: TimeZone, locale: Locale = .current) -> String {
        let label = kind == .goldenMorning
            ? String(localized: "Sunrise", bundle: .module, locale: locale, comment: "Day card: sunrise")
            : String(localized: "Sunset", bundle: .module, locale: locale, comment: "Day card: sunset")
        let t = TimeText.time(time, in: zone, locale: locale)
        return String(localized: "\(label) at \(t)", bundle: .module, locale: locale, comment: "Day card: sunrise or sunset and its time, e.g. Sunset at 18:14")
    }

    /// "Overnight near Page, AZ"
    public static func overnightNear(_ place: String, locale: Locale = .current) -> String {
        String(localized: "Overnight near \(place)", bundle: .module, locale: locale, comment: "Where you sleep between two trip days, e.g. Overnight near Page, AZ")
    }

    /// "Drive doesn't fit: 25 min short"
    public static func driveDoesntFit(shortBy seconds: TimeInterval, locale: Locale = .current) -> String {
        let d = TimeText.duration(max(seconds, 60), locale: locale)
        return String(localized: "Drive doesn't fit: \(d) short", bundle: .module, locale: locale, comment: "Warning on a drive that arrives after the window starts")
    }

    /// "Park at 16:42 • 25 min walk in"; without a park time just "25 min walk in"; "Walk-in unknown" with no walk.
    public static func parkLine(parkAt: Date?, walkMinutes: Int?, in zone: TimeZone, locale: Locale = .current) -> String {
        guard let walkMinutes else {
            return String(localized: "Walk-in unknown", bundle: .module, locale: locale, comment: "Walk from parking to the shooting spot is not known")
        }
        let walk = String(localized: "\(walkMinutes) min walk in", bundle: .module, locale: locale, comment: "Walk from parking to the shooting spot")
        guard let parkAt else { return walk }
        let t = TimeText.time(parkAt, in: zone, locale: locale)
        return String(localized: "Park at \(t) • \(walk)", bundle: .module, locale: locale, comment: "Park time, then the walk to the shooting spot")
    }

    /// "20 min setup"
    public static func setUpShort(minutes: Int, locale: Locale = .current) -> String {
        String(localized: "\(minutes) min setup", bundle: .module, locale: locale, comment: "Minutes to be set up before the window starts")
    }

    /// The transfer picker's items: "Morning", "Evening Before".
    public static func transferTimingName(_ timing: TransferTiming, locale: Locale = .current) -> String {
        switch timing {
        case .morning: String(localized: "Morning", bundle: .module, locale: locale, comment: "Transfer card picker item: drive on the morning of the shoot")
        case .eveningBefore: String(localized: "Evening Before", bundle: .module, locale: locale, comment: "Transfer card picker item: drive the evening before, after the last session")
        }
    }
}
