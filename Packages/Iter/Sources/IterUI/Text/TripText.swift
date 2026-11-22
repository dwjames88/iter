import Foundation
import IterModel

/// Trip-mode phrasing: when to leave, when you arrive, how late you are.
public enum TripText {
    /// Within this many seconds of the departure time it reads "Leave now".
    public static let nowTolerance: TimeInterval = 60

    /// "Leave by 17:40", "Leave now", or "Late by 6 min" once the departure time has passed by more than a minute.
    public static func leaveBy(_ departure: Date, now: Date, in zone: TimeZone, locale: Locale = .current) -> String {
        let delta = departure.timeIntervalSince(now)
        if delta > nowTolerance {
            let t = TimeText.time(departure, in: zone, locale: locale)
            return String(localized: "Leave by \(t)", bundle: .module, locale: locale, comment: "Trip mode: latest departure time, e.g. Leave by 17:40")
        }
        if delta >= -nowTolerance {
            return String(localized: "Leave Now", bundle: .module, locale: locale, comment: "Trip mode: the departure time is now")
        }
        return lateBy(-delta, locale: locale)
    }

    /// "Arrive 18:05"
    public static func arrive(_ arrival: Date, in zone: TimeZone, locale: Locale = .current) -> String {
        let t = TimeText.time(arrival, in: zone, locale: locale)
        return String(localized: "Arrive \(t)", bundle: .module, locale: locale, comment: "Trip mode: estimated arrival time, e.g. Arrive 18:05")
    }

    /// "Late by 6 min". Rounds up to whole minutes, minimum one.
    public static func lateBy(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let d = wholeMinutes(seconds, locale: locale)
        return String(localized: "Late by \(d)", bundle: .module, locale: locale, comment: "Trip mode: how late you are, e.g. Late by 6 min")
    }

    /// Seconds rounded up to whole minutes (minimum one), abbreviated: "6 min", "1 hr, 20 min".
    private static func wholeMinutes(_ seconds: TimeInterval, locale: Locale) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(locale))
    }

    /// "Arrive 18:05", or "Arrive 18:05 · 6 min after the light starts" when the arrival falls after `deadline`
    /// (for example the window's start). The leave-by line already says how late you are leaving; this line says
    /// what the lateness means for the arrival.
    public static func eta(arrival: Date, deadline: Date?, in zone: TimeZone, locale: Locale = .current) -> String {
        if let deadline, arrival.timeIntervalSince(deadline) > nowTolerance {
            let t = TimeText.time(arrival, in: zone, locale: locale)
            let d = wholeMinutes(arrival.timeIntervalSince(deadline), locale: locale)
            return String(localized: "Arrive \(t) · \(d) after the light starts", bundle: .module, locale: locale,
                          comment: "Trip mode: estimated arrival time when it falls after the light window starts, e.g. Arrive 18:05 · 6 min after the light starts")
        }
        return arrive(arrival, in: zone, locale: locale)
    }

    /// "1 hr, 20 min · 94 mi": the drive line.
    public static func drive(seconds: TimeInterval, meters: Double, locale: Locale = .current) -> String {
        let d = TimeText.duration(seconds, locale: locale)
        let m = TimeText.distance(meters: meters, locale: locale)
        return String(localized: "\(d) · \(m)", bundle: .module, locale: locale, comment: "Trip mode drive summary: duration and distance")
    }
}
