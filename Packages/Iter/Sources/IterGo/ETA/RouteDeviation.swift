import Foundation
import IterModel

/// How far a fix is from the drawn route (BLUEPRINT §10.2: refresh the route line when the user is more than 1 km off).
public enum RouteDeviation {
    public static let rerouteThresholdM: Double = 1_000

    /// Distance in metres from `point` to the nearest point on the polyline. Infinity for an empty path.
    public static func distance(from point: Coordinate, to path: [Coordinate]) -> Double {
        guard let first = path.first else { return .infinity }
        guard path.count > 1 else { return point.distance(to: first) }
        return zip(path, path.dropFirst()).reduce(Double.infinity) { min($0, segmentDistance(point, $1.0, $1.1)) }
    }

    /// True when the fix is usable and further than 1 km from a non-empty path.
    public static func needsReroute(fix: LocationFix, path: [Coordinate]) -> Bool {
        guard fix.isUsable(), !path.isEmpty else { return false }
        return distance(from: fix.coordinate, to: path) > rerouteThresholdM
    }

    /// Point to segment, in a local flat projection around the point (fine for segments of a few km).
    private static func segmentDistance(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let mPerDeg = Coordinate.earthRadiusMeters * .pi / 180
        let cosLat = cos(p.latitude * .pi / 180)
        func xy(_ c: Coordinate) -> (Double, Double) {
            var dLon = c.longitude - p.longitude
            if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
            return (dLon * mPerDeg * cosLat, (c.latitude - p.latitude) * mPerDeg)
        }
        let (ax, ay) = xy(a), (bx, by) = xy(b)
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return (ax * ax + ay * ay).squareRoot() }
        let t = min(1, max(0, -(ax * dx + ay * dy) / len2))
        let cx = ax + t * dx, cy = ay + t * dy
        return (cx * cx + cy * cy).squareRoot()
    }
}
