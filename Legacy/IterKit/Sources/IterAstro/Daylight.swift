import Foundation
import IterCore

/// Where it is day and night on Earth right now, as map geometry. MapKit has no public time-of-day layer, so the
/// maps draw this instead: the night side of the globe, as polygons that never wrap the antimeridian.
public enum Daylight {
    /// The point on Earth where the Sun is straight overhead.
    public static func subsolarPoint(at date: Date) -> Coordinate {
        let jd = AstroMath.julianDay(date)
        let sun = SolarCoordinates(T: AstroMath.centuriesTT(jdUT: jd))
        let lon = AstroMath.norm360(sun.alpha - AstroMath.apparentSiderealTime(jdUT: jd) + 180) - 180
        return Coordinate(latitude: sun.delta, longitude: lon)
    }

    /// The part of the Earth where the Sun is below `sunAltitude` degrees (0 is the day/night line; -6, -12 and -18
    /// are the civil, nautical and astronomical twilight lines), as polygons in latitude -90...90 and longitude
    /// -180...180. Edges are `step` degrees of arc apart or less, so a map that joins vertices with straight lines
    /// (Mercator) or with great circles (a globe) draws the same curve.
    ///
    /// The region is a spherical cap centred on the antisolar point. A cap that holds a pole is closed along the
    /// pole's edge (at +-`poleLatitude`, since Mercator cannot reach 90); a cap that crosses the antimeridian is
    /// cut there into two polygons.
    public static func nightPolygons(at date: Date, sunAltitude: Double = 0, step: Double = 2,
                                     poleLatitude: Double = 89.5) -> [[Coordinate]] {
        let sub = subsolarPoint(at: date)
        let centre = (lat: -sub.latitude, lon: sub.longitude + 180)
        let radius = 90 + sunAltitude                       // angular radius of the cap, degrees
        guard radius > 0 else { return [] }
        if radius >= 180 { return [worldRectangle(poleLatitude: poleLatitude, step: step)] }

        // The cap boundary: points at `radius` from the centre, one per bearing, longitudes made continuous.
        let count = max(24, Int((360 / max(0.25, step)).rounded()))
        let phi0 = AstroMath.rad(centre.lat), rho = AstroMath.rad(radius)
        var boundary: [(lat: Double, lon: Double)] = []
        boundary.reserveCapacity(count + 1)
        var previous = centre.lon
        for i in 0...count {
            let bearing = AstroMath.rad(360 * Double(i) / Double(count))
            let lat = asin(max(-1, min(1, sin(phi0) * cos(rho) + cos(phi0) * sin(rho) * cos(bearing))))
            var lon = centre.lon + AstroMath.deg(atan2(sin(bearing) * sin(rho) * cos(phi0), cos(rho) - sin(phi0) * sin(lat)))
            if i == 0 { previous = lon }
            while lon - previous > 180 { lon -= 360 }
            while lon - previous < -180 { lon += 360 }
            previous = lon
            boundary.append((AstroMath.deg(lat), lon))
        }

        // Does the cap hold a pole? Then the boundary runs once round the world (the last point is 360 from the first).
        let holdsNorth = 90 - centre.lat < radius, holdsSouth = 90 + centre.lat < radius
        var ring: [(lat: Double, lon: Double)]
        if holdsNorth || holdsSouth {
            ring = boundary
            if ring.last!.lon < ring.first!.lon { ring.reverse() }          // west to east
            let pole = holdsNorth ? poleLatitude : -poleLatitude
            let from = ring.last!.lon, to = ring.first!.lon
            let pieces = max(1, Int(((from - to) / max(1, step)).rounded(.up)))
            for i in 0...pieces { ring.append((pole, from + (to - from) * Double(i) / Double(pieces))) }
        } else {
            ring = Array(boundary.dropLast())
        }
        ring = ring.map { (max(-poleLatitude, min(poleLatitude, $0.lat)), $0.lon) }

        // Cut the continuous ring at the antimeridian, folding each piece back into -180...180.
        var result: [[Coordinate]] = []
        let minLon = ring.map(\.lon).min()!, maxLon = ring.map(\.lon).max()!
        for k in Int(((minLon - 180) / 360).rounded(.down)) ... Int(((maxLon + 180) / 360).rounded(.up)) {
            let shifted = ring.map { (lat: $0.lat, lon: $0.lon - 360 * Double(k)) }
            let clipped = clip(clip(shifted, east: false), east: true)
            if clipped.count >= 3 { result.append(clipped.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }) }
        }
        return result
    }

    private static func worldRectangle(poleLatitude: Double, step: Double) -> [Coordinate] {
        [Coordinate(latitude: -poleLatitude, longitude: -180), Coordinate(latitude: -poleLatitude, longitude: 180),
         Coordinate(latitude: poleLatitude, longitude: 180), Coordinate(latitude: poleLatitude, longitude: -180)]
    }

    /// Sutherland-Hodgman against one meridian: keeps longitude <= 180 (`east`) or >= -180.
    private static func clip(_ poly: [(lat: Double, lon: Double)], east: Bool) -> [(lat: Double, lon: Double)] {
        guard !poly.isEmpty else { return [] }
        let edge = east ? 180.0 : -180.0
        func inside(_ p: (lat: Double, lon: Double)) -> Bool { east ? p.lon <= edge : p.lon >= edge }
        func cross(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> (lat: Double, lon: Double) {
            let t = (edge - a.lon) / (b.lon - a.lon)
            return (a.lat + (b.lat - a.lat) * t, edge)
        }
        var out: [(lat: Double, lon: Double)] = []
        for (i, cur) in poly.enumerated() {
            let prev = poly[(i + poly.count - 1) % poly.count]
            if inside(cur) {
                if !inside(prev) { out.append(cross(prev, cur)) }
                out.append(cur)
            } else if inside(prev) {
                out.append(cross(prev, cur))
            }
        }
        return out
    }
}
