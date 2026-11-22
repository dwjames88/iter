import Foundation
import IterModel

/// The Milky Way core (Sgr A*) for astrophotography planning.
///
/// Accuracy notes: the J2000 position is precessed to the date with the rigorous IAU 1976 angles
/// (Meeus, Astronomical Algorithms ch. 21). Nutation in the position, annual aberration and proper motion are
/// ignored (together under 0.01° for this purpose). The altitude/azimuth step reuses `AstroMath.horizontal` and
/// `AstroMath.refraction`, the same sidereal time and refraction model the sun and moon use.
public enum GalacticCentre {
    /// Sgr A*, J2000: RA 17h45m40.04s, Dec −29°00′28.1″.
    public static let rightAscensionJ2000: Double = (17 + 45.0 / 60 + 40.04 / 3600) * 15
    public static let declinationJ2000: Double = -(29 + 0.0 / 60 + 28.1 / 3600)

    /// Apparent altitude (with the same refraction model the sun/moon use) and azimuth (clockwise from north) of the core.
    public static func position(at date: Date, coordinate: Coordinate) -> SkyPosition {
        let jd = AstroMath.julianDay(date)
        let eq = precessed(T: AstroMath.centuriesTT(jdUT: jd))
        let h = AstroMath.horizontal(alpha: eq.alpha, delta: eq.delta, jdUT: jd,
                                     latitude: coordinate.latitude, longitudeEast: coordinate.longitude)
        return SkyPosition(altitude: h.altitude + AstroMath.refraction(trueAltitude: h.altitude), azimuth: h.azimuth)
    }

    /// The core over a span (normally a night): sampled every `stepMinutes`, from `span.start` to `span.end`
    /// inclusive. All times (peak, run boundaries) are sample times, so they are good to one step; nothing is
    /// refined between samples. A run is the first to last sample of consecutive qualifying samples, so a run
    /// that qualifies at a single sample has zero duration. Sun and moon altitudes come from `ephemeris`.
    public static func visibility(over span: TimeSpan, at coordinate: Coordinate, ephemeris: any Ephemeris,
                                  minimumAltitude: Double = 10, stepMinutes: Int = 10) -> MilkyWayVisibility {
        let step = TimeInterval(max(1, stepMinutes) * 60)
        var times: [Date] = []
        var t = span.start
        while t < span.end {
            times.append(t)
            t = t.addingTimeInterval(step)
        }
        times.append(span.end)

        let core = times.map { position(at: $0, coordinate: coordinate) }
        var peak = 0
        for i in core.indices where core[i].altitude > core[peak].altitude { peak = i }

        let dark = times.indices.map { i in
            core[i].altitude >= minimumAltitude && ephemeris.sunPosition(at: times[i], coordinate: coordinate).altitude < -18
        }
        let darkRun = longestRun(in: dark, within: 0..<times.count)
        var best: Range<Int>?
        if let darkRun {
            let moonDown = times.indices.map { i in
                dark[i] && ephemeris.moonPosition(at: times[i], coordinate: coordinate).altitude <= 0
            }
            best = longestRun(in: moonDown, within: darkRun)
        }
        func spanOf(_ r: Range<Int>?) -> TimeSpan? {
            r.map { TimeSpan(start: times[$0.lowerBound], end: times[$0.upperBound - 1]) }
        }
        return MilkyWayVisibility(span: span, peakAltitude: core[peak].altitude, peakTime: times[peak],
                                  peakAzimuth: core[peak].azimuth,
                                  coreUpInDark: spanOf(darkRun), bestWindow: spanOf(best))
    }

    /// Longest run of `true` flags inside `range` (first one wins a tie), as a half-open index range.
    private static func longestRun(in flags: [Bool], within range: Range<Int>) -> Range<Int>? {
        var best: Range<Int>?
        var start: Int?
        for i in range.lowerBound...range.upperBound {
            let on = i < range.upperBound && flags[i]
            if on, start == nil { start = i }
            if !on, let s = start {
                if best == nil || i - s > best!.count { best = s..<i }
                start = nil
            }
        }
        return best
    }

    /// J2000 RA/Dec precessed to the mean equator and equinox of date (Meeus 21.2, rigorous), degrees.
    private static func precessed(T: Double) -> (alpha: Double, delta: Double) {
        let t = T
        let zeta = AstroMath.rad((2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600)
        let z = AstroMath.rad((2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600)
        let theta = AstroMath.rad((2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600)
        let a0 = AstroMath.rad(rightAscensionJ2000), d0 = AstroMath.rad(declinationJ2000)
        let A = cos(d0) * sin(a0 + zeta)
        let B = cos(theta) * cos(d0) * cos(a0 + zeta) - sin(theta) * sin(d0)
        let C = sin(theta) * cos(d0) * cos(a0 + zeta) + cos(theta) * sin(d0)
        return (AstroMath.norm360(AstroMath.deg(atan2(A, B)) + AstroMath.deg(z)), AstroMath.deg(asin(max(-1, min(1, C)))))
    }
}

/// Whether, when and how well the Milky Way core can be photographed over a span.
public struct MilkyWayVisibility: Codable, Hashable, Sendable {
    /// The span that was examined.
    public var span: TimeSpan
    /// Highest core altitude in the span, its time and azimuth.
    public var peakAltitude: Double
    public var peakTime: Date
    public var peakAzimuth: Double
    /// The longest run where the core is ≥ minimumAltitude AND the sun is below −18° (astronomical dark). nil if none.
    public var coreUpInDark: TimeSpan?
    /// The longest run inside `coreUpInDark` where the moon is also below the horizon (altitude ≤ 0). nil if none.
    public var bestWindow: TimeSpan?
    /// True when `coreUpInDark` is non-nil.
    public var isVisible: Bool { coreUpInDark != nil }

    public init(span: TimeSpan, peakAltitude: Double, peakTime: Date, peakAzimuth: Double,
                coreUpInDark: TimeSpan?, bestWindow: TimeSpan?) {
        self.span = span
        self.peakAltitude = peakAltitude
        self.peakTime = peakTime
        self.peakAzimuth = peakAzimuth
        self.coreUpInDark = coreUpInDark
        self.bestWindow = bestWindow
    }
}
