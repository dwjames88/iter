import Foundation

/// Shared time, angle and coordinate helpers for the ephemeris. All angles are degrees unless a name says otherwise.
enum AstroMath {
    /// ΔT = TT − UT1 in seconds. A constant: the true value is about 69 s in the mid 2020s and drifts by
    /// well under a second per year, which is far below what these low-precision series resolve
    /// (1 s of time moves the Sun 0.004° and the Moon 0.5 arcsec in position).
    static let deltaT: Double = 69.0

    static let j2000: Double = 2_451_545.0

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Reduces an angle to 0..<360.
    static func norm360(_ a: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Julian Day (UT) of an instant.
    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// Julian centuries of dynamical time (TT) since J2000.0 for a Julian Day in UT.
    static func centuriesTT(jdUT: Double) -> Double {
        (jdUT + deltaT / 86_400 - j2000) / 36_525
    }

    /// Julian centuries of TT since J2000.0 for a Julian Ephemeris Day (already in TT).
    static func centuries(jde: Double) -> Double { (jde - j2000) / 36_525 }

    /// Mean obliquity of the ecliptic (Meeus 22.2), degrees.
    static func meanObliquity(T: Double) -> Double {
        23.4392911 - 0.0130041667 * T - 1.63889e-7 * T * T + 5.03611e-7 * T * T * T
    }

    /// Low-precision nutation (Meeus ch. 22 abridged to four terms): (Δψ, Δε) in degrees.
    static func nutation(T: Double) -> (dpsi: Double, deps: Double) {
        let omega = rad(125.04452 - 1934.136261 * T)
        let l0 = rad(280.4665 + 36000.7698 * T)
        let lm = rad(218.3165 + 481267.8813 * T)
        let dpsi = (-17.20 * sin(omega) - 1.32 * sin(2 * l0) - 0.23 * sin(2 * lm) + 0.21 * sin(2 * omega)) / 3600
        let deps = (9.20 * cos(omega) + 0.57 * cos(2 * l0) + 0.10 * cos(2 * lm) - 0.09 * cos(2 * omega)) / 3600
        return (dpsi, deps)
    }

    /// Apparent sidereal time at Greenwich in degrees (Meeus 12.4 plus the equation of the equinoxes).
    static func apparentSiderealTime(jdUT: Double) -> Double {
        let d = jdUT - j2000
        let Tu = d / 36_525
        let mean = 280.46061837 + 360.98564736629 * d + 0.000387933 * Tu * Tu - Tu * Tu * Tu / 38_710_000
        let T = centuriesTT(jdUT: jdUT)
        let n = nutation(T: T)
        let eps = meanObliquity(T: T) + n.deps
        return norm360(mean + n.dpsi * cos(rad(eps)))
    }

    /// Ecliptic (λ, β) to equatorial (α, δ), all degrees, for obliquity `eps`.
    static func equatorial(lambda: Double, beta: Double, eps: Double) -> (alpha: Double, delta: Double) {
        let l = rad(lambda), b = rad(beta), e = rad(eps)
        let alpha = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
        let delta = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
        return (norm360(deg(alpha)), deg(delta))
    }

    /// Geometric (unrefracted, geocentric) altitude and azimuth (clockwise from true north) of an equatorial
    /// position seen from `latitude`, `longitudeEast` at the given UT Julian Day.
    static func horizontal(alpha: Double, delta: Double, jdUT: Double,
                           latitude: Double, longitudeEast: Double) -> (altitude: Double, azimuth: Double) {
        let H = rad(apparentSiderealTime(jdUT: jdUT) + longitudeEast - alpha)
        let phi = rad(latitude), d = rad(delta)
        let sinAlt = sin(phi) * sin(d) + cos(phi) * cos(d) * cos(H)
        let alt = deg(asin(max(-1, min(1, sinAlt))))
        // Azimuth measured from the south, then shifted to north-based.
        let azSouth = atan2(sin(H), cos(H) * sin(phi) - tan(d) * cos(phi))
        return (alt, norm360(deg(azSouth) + 180))
    }

    /// Atmospheric refraction in degrees for a true (geometric) altitude, at 1010 hPa and 10 °C.
    /// Piecewise Bennett/Sæmundsson-style fit as used by the NOAA solar calculator; continuous across the pieces.
    static func refraction(trueAltitude h: Double) -> Double {
        if h > 85 { return 0 }
        let t = tan(rad(h))
        let arcsec: Double
        if h > 5 {
            arcsec = 58.1 / t - 0.07 / (t * t * t) + 0.000086 / (t * t * t * t * t)
        } else if h > -0.575 {
            arcsec = 1735 + h * (-518.2 + h * (103.4 + h * (-12.79 + h * 0.711)))
        } else {
            arcsec = -20.774 / t
        }
        return arcsec / 3600
    }

    /// Finds sign changes of `f(t) - threshold` over uniformly spaced samples and refines each by bisection
    /// to under half a second. `t` is seconds since the Unix epoch. Returns (time, isRising) in time order.
    static func crossings(t0: Double, step: Double, values: [Double], threshold: Double,
                          f: (Double) -> Double) -> [(time: Double, rising: Bool)] {
        var out: [(Double, Bool)] = []
        guard values.count > 1 else { return [] }
        for i in 0..<(values.count - 1) {
            let a = values[i] - threshold, b = values[i + 1] - threshold
            guard (a < 0 && b >= 0) || (a >= 0 && b < 0) else { continue }
            let rising = b >= 0
            var lo = t0 + Double(i) * step
            var hi = t0 + Double(i + 1) * step
            while hi - lo > 0.5 {
                let mid = (lo + hi) / 2
                let v = f(mid) - threshold
                if (v >= 0) == rising { hi = mid } else { lo = mid }
            }
            out.append(((lo + hi) / 2, rising))
        }
        return out
    }
}
