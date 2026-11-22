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
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let d = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(locale))
        return String(localized: "Late by \(d)", bundle: .module, locale: locale, comment: "Trip mode: how late you are, e.g. Late by 6 min")
    }

    /// "Arrive 18:05", or "Late by 6 min" when the arrival falls after `deadline` (for example the window's start).
    public static func eta(arrival: Date, deadline: Date?, in zone: TimeZone, locale: Locale = .current) -> String {
        if let deadline, arrival.timeIntervalSince(deadline) > nowTolerance {
            return lateBy(arrival.timeIntervalSince(deadline), locale: locale)
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
