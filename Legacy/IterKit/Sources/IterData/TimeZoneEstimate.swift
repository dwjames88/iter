import Foundation
import IterCore

/// A time zone guess for a coordinate when no lookup answered. Never the Mac's zone: a spot's light is planned on its own clock.
public enum TimeZoneEstimate {
    /// How close a curated spot must be to lend its zone.
    public static let curatedRadiusMeters = 150_000.0

    /// The nearest curated spot's zone when within 150 km, else a fixed offset from longitude ("GMT-0100").
    public static func identifier(for coordinate: Coordinate) -> String {
        if let nearest = CuratedSpots.all.min(by: { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) }),
           nearest.coordinate.distance(to: coordinate) <= curatedRadiusMeters {
            return nearest.timeZoneIdentifier
        }
        let hours = max(-12, min(14, Int((coordinate.longitude / 15).rounded())))
        return TimeZone(secondsFromGMT: hours * 3600)!.identifier
    }
}
