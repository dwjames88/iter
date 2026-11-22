import Foundation
import IterModel

/// What is left of a planned leg, measured along its stored route line.
public struct OfflineEstimate: Codable, Hashable, Sendable {
    /// The leg's planned time scaled by `fractionRemaining`.
    public var seconds: TimeInterval
    /// The leg's planned distance scaled by `fractionRemaining`.
    public var meters: Double
    /// Remaining path length over total path length, 0...1.
    public var fractionRemaining: Double
    /// How far the position is from the route line.
    public var crossTrackMeters: Double
    /// True when the position is within `OfflineETA.maxCrossTrackMeters` of the line (always true for a returned estimate).
    public var isAlongRoute: Bool

    public init(seconds: TimeInterval, meters: Double, fractionRemaining: Double, crossTrackMeters: Double, isAlongRoute: Bool) {
        self.seconds = seconds
        self.meters = meters
        self.fractionRemaining = fractionRemaining
        self.crossTrackMeters = crossTrackMeters
        self.isAlongRoute = isAlongRoute
    }
}

/// ETA without a network: the planned leg time scaled by progress along the stored route line (blueprint §10.7). Pure.
public enum OfflineETA {
    /// Further than this from the route line and the position is not considered to be on the route.
    public static let maxCrossTrackMeters: Double = 2000

    private static let earthRadius = 6_371_000.0

    /// Projects `position` onto `leg.path`. Nil when the path has fewer than two points, has no length, or the position is more
    /// than `maxCrossTrackMeters` from it (the caller then falls back to a straight line).
    public static func estimate(from position: Coordinate, along leg: Leg) -> OfflineEstimate? {
        let path = leg.path
        guard path.count >= 2 else { return nil }
        var lengths: [Double] = []
        var frames: [Double] = []
        for (a, b) in zip(path, path.dropFirst()) {
            let cosLat = cos((a.latitude + b.latitude) / 2 * .pi / 180)
            frames.append(cosLat)
            lengths.append(vector(from: a, to: b, cosLat: cosLat).length)
        }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }

        var best: (index: Int, t: Double, cross: Double)?
        for i in 0..<lengths.count {
            let a = path[i]
            let ab = vector(from: a, to: path[i + 1], cosLat: frames[i])
            let ap = vector(from: a, to: position, cosLat: frames[i])
            let len2 = ab.x * ab.x + ab.y * ab.y
            let t = len2 > 0 ? min(1, max(0, (ap.x * ab.x + ap.y * ab.y) / len2)) : 0
            let dx = ap.x - t * ab.x, dy = ap.y - t * ab.y
            let cross = (dx * dx + dy * dy).squareRoot()
            if best == nil || cross < best!.cross { best = (i, t, cross) }
        }
        guard let best, best.cross <= maxCrossTrackMeters else { return nil }
        let remaining = (1 - best.t) * lengths[best.index] + lengths[(best.index + 1)...].reduce(0, +)
        let fraction = min(1, max(0, remaining / total))
        return OfflineEstimate(seconds: leg.seconds * fraction, meters: leg.meters * fraction, fractionRemaining: fraction,
                               crossTrackMeters: best.cross, isAlongRoute: true)
    }

    /// An ETA from `position` to `destination`: along the planned leg's route line when the position is on it, else a straight
    /// line (`Leg.estimate`, × 1.3 at 70 km/h). Departing is `now`; arrival is `now` plus the drive.
    public static func eta(from position: Coordinate, to destination: Coordinate, plannedLeg: Leg?, now: Date) -> (eta: ETA, isAlongRoute: Bool) {
        if let plannedLeg, let along = estimate(from: position, along: plannedLeg) {
            return (ETA(seconds: along.seconds, arrival: now.addingTimeInterval(along.seconds), departing: now), true)
        }
        let seconds = Leg.estimate(from: position, to: destination).seconds
        return (ETA(seconds: seconds, arrival: now.addingTimeInterval(seconds), departing: now), false)
    }

    /// Metres east and north from `a` to `b`, equirectangular at the given cosine of latitude.
    private static func vector(from a: Coordinate, to b: Coordinate, cosLat: Double) -> (x: Double, y: Double, length: Double) {
        let x = (b.longitude - a.longitude) * .pi / 180 * cosLat * earthRadius
        let y = (b.latitude - a.latitude) * .pi / 180 * earthRadius
        return (x, y, (x * x + y * y).squareRoot())
    }
}
