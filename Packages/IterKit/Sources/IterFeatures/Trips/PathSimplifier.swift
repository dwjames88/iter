import Foundation
import IterCore

/// Douglas-Peucker line simplification for the route the map draws. MapKit's directions return a vertex every few metres;
/// at the zoom a trip is planned at, thousands of them are the same pixels, and each one costs the map's overlay renderer
/// when a polyline is restyled (every day switch). The full road path stays in the drive leg; only the drawn copy is thinned.
public enum PathSimplifier {
    /// About 25 m: well under a pixel at the zoom a whole trip fits, and under 5 px at the 25-mile selection zoom.
    public static let routeTolerance = 0.00022

    /// `points` thinned so no dropped point is further than `tolerance` degrees (measured with longitude scaled by the
    /// cosine of the path's mean latitude) from the line that replaces it. The first and last points always stay.
    public static func simplify(_ points: [Coordinate], tolerance: Double) -> [Coordinate] {
        guard points.count > 2, tolerance > 0 else { return points }
        let meanLatitude = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
        let scale = max(0.1, cos(meanLatitude * .pi / 180))
        let xy = points.map { (x: $0.longitude * scale, y: $0.latitude) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            let a = xy[first], b = xy[last]
            let dx = b.x - a.x, dy = b.y - a.y
            let length2 = dx * dx + dy * dy
            var worst = 0.0
            var worstIndex = -1
            for i in (first + 1)..<last {
                let p = xy[i]
                let distance: Double
                if length2 == 0 {
                    distance = hypot(p.x - a.x, p.y - a.y)
                } else {
                    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
                    distance = hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
                }
                if distance > worst { worst = distance; worstIndex = i }
            }
            if worst > tolerance, worstIndex >= 0 {
                keep[worstIndex] = true
                stack.append((first, worstIndex))
                stack.append((worstIndex, last))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }
}
