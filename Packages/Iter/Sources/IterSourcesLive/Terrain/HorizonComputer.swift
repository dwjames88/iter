import Foundation
import IterModel

/// Computes a terrain horizon profile by ray-marching an elevation sampler. Pure: no I/O, no clock.
///
/// For each azimuth (clockwise from true north, index 0 = north, matching `HorizonProfile`) the ray follows the great
/// circle from the observer. Sample spacing grows with distance (3 percent of the distance, never under 30 m or over 250 m).
/// At distance `d` over terrain of height `h`, the elevation angle is
/// `atan((h - h0 - drop) / d)` with `h0` the observer's eye height above sea level and
/// `drop = d^2 / (2R) * (1 - k)` the Earth-curvature drop reduced by standard refraction (`k = 0.13`).
/// The horizon is the largest angle along the ray and may be negative. A ray stops at the first coordinate the sampler
/// cannot answer (a missing tile), so a profile near a data edge reflects only the terrain that was available.
public struct HorizonComputer: Sendable {
    /// Result of a computation.
    public struct Result: Sendable, Equatable {
        public var profile: HorizonProfile
        /// Distance (m) of the last sample taken on each ray; 0 when the first sample was already missing.
        public var reachedMetres: [Double]
        /// Azimuths that got no sample at all; their value is `levelHorizonDegrees`, not terrain.
        public var azimuthsWithoutData: Int
    }

    public var observerHeightM: Double
    public var azimuthStepDegrees: Double
    public var maxDistanceM: Double
    /// Refraction coefficient; the curvature drop is multiplied by `1 - k`.
    public var refraction: Double
    public var earthRadiusM: Double

    public init(observerHeightM: Double = 2, azimuthStepDegrees: Double = HorizonProfile.standardStepDegrees,
                maxDistanceM: Double = 40_000, refraction: Double = 0.13, earthRadiusM: Double = Coordinate.earthRadiusMeters) {
        self.observerHeightM = observerHeightM
        self.azimuthStepDegrees = azimuthStepDegrees
        self.maxDistanceM = maxDistanceM
        self.refraction = refraction
        self.earthRadiusM = earthRadiusM
    }

    /// Number of azimuths, or nil when the step does not divide 360 degrees into a whole count.
    public var azimuthCount: Int? {
        guard azimuthStepDegrees > 0, azimuthStepDegrees <= 180 else { return nil }
        let n = 360 / azimuthStepDegrees
        return abs(n - n.rounded()) < 1e-6 ? Int(n.rounded()) : nil
    }

    /// The horizon of a level plane level with the observer's ground: the least negative angle
    /// `-atan(2 sqrt(h0 (1 - k) / (2R)))` (about -0.042 degrees for a 2 m eye).
    public var levelHorizonDegrees: Double {
        -atan(2 * (observerHeightM * (1 - refraction) / (2 * earthRadiusM)).squareRoot()) * 180 / .pi
    }

    /// Sample spacing at distance `d`.
    public static func step(atDistance d: Double) -> Double { min(250, max(30, d * 0.03)) }

    /// - Parameters:
    ///   - observer: where the eye is (ground position).
    ///   - groundElevationM: terrain height under the observer; the eye is `observerHeightM` above it.
    ///   - sampler: terrain height (m above sea level) at a coordinate, nil where unknown.
    /// - Returns: nil when `azimuthStepDegrees` does not divide 360 into a whole count.
    public func compute(from observer: Coordinate, groundElevationM: Double,
                        sampler: (Coordinate) -> Double?) -> Result? {
        guard let count = azimuthCount else { return nil }
        let h0 = groundElevationM + observerHeightM
        let φ1 = observer.latitude * .pi / 180, λ1 = observer.longitude * .pi / 180
        let sinφ1 = sin(φ1), cosφ1 = cos(φ1)
        let level = levelHorizonDegrees
        var values = [Double](repeating: level, count: count)
        var reached = [Double](repeating: 0, count: count)
        var without = 0
        for i in 0..<count {
            let θ = Double(i) * azimuthStepDegrees * .pi / 180
            let sinθ = sin(θ), cosθ = cos(θ)
            var best = -Double.infinity
            var d = HorizonComputer.step(atDistance: 0)
            var last = 0.0
            while d <= maxDistanceM {
                let δ = d / earthRadiusM
                let sinδ = sin(δ), cosδ = cos(δ)
                let sinφ2 = sinφ1 * cosδ + cosφ1 * sinδ * cosθ
                let φ2 = asin(max(-1, min(1, sinφ2)))
                let λ2 = λ1 + atan2(sinθ * sinδ * cosφ1, cosδ - sinφ1 * sinφ2)
                var lon = λ2 * 180 / .pi
                lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
                guard let h = sampler(Coordinate(latitude: φ2 * 180 / .pi, longitude: lon)) else { break }
                let drop = d * d / (2 * earthRadiusM) * (1 - refraction)
                best = max(best, atan((h - h0 - drop) / d))
                last = d
                d += HorizonComputer.step(atDistance: d)
            }
            reached[i] = last
            if best.isFinite { values[i] = best * 180 / .pi } else { without += 1 }
        }
        return Result(profile: HorizonProfile(azimuthStepDegrees: azimuthStepDegrees, elevationsDegrees: values),
                      reachedMetres: reached, azimuthsWithoutData: without)
    }
}
