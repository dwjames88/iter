import Foundation

/// Low-precision solar coordinates (Meeus, Astronomical Algorithms ch. 25; same model as the NOAA solar calculator).
struct SolarCoordinates {
    var apparentLongitude: Double   // λ, degrees (nutation and aberration applied)
    var alpha: Double               // apparent right ascension, degrees
    var delta: Double               // apparent declination, degrees
    var distanceAU: Double          // Earth-Sun distance, astronomical units
    var obliquity: Double           // true obliquity, degrees

    /// `T` is Julian centuries of dynamical time since J2000.0.
    init(T: Double) {
        let r = AstroMath.rad
        let L0 = AstroMath.norm360(280.46646 + 36000.76983 * T + 0.0003032 * T * T)   // geometric mean longitude
        let M = AstroMath.norm360(357.52911 + 35999.05029 * T - 0.0001537 * T * T)    // mean anomaly
        let e = 0.016708634 - 0.000042037 * T - 0.0000001267 * T * T
        let C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(r(M))              // equation of centre
            + (0.019993 - 0.000101 * T) * sin(r(2 * M))
            + 0.000289 * sin(r(3 * M))
        let trueLong = L0 + C
        let trueAnomaly = M + C
        distanceAU = 1.000001018 * (1 - e * e) / (1 + e * cos(r(trueAnomaly)))
        let omega = 125.04 - 1934.136 * T
        apparentLongitude = AstroMath.norm360(trueLong - 0.00569 - 0.00478 * sin(r(omega)))
        obliquity = AstroMath.meanObliquity(T: T) + 0.00256 * cos(r(omega))
        let eq = AstroMath.equatorial(lambda: apparentLongitude, beta: 0, eps: obliquity)
        alpha = eq.alpha
        delta = eq.delta
    }

    /// Geometric (unrefracted) altitude and azimuth.
    func horizontal(jdUT: Double, latitude: Double, longitudeEast: Double) -> (altitude: Double, azimuth: Double) {
        AstroMath.horizontal(alpha: alpha, delta: delta, jdUT: jdUT, latitude: latitude, longitudeEast: longitudeEast)
    }

    /// Equation of time in minutes (apparent minus mean solar time), derived from the right ascension
    /// and the mean longitude.
    static func equationOfTime(T: Double) -> Double {
        let L0 = AstroMath.norm360(280.46646 + 36000.76983 * T + 0.0003032 * T * T)
        let s = SolarCoordinates(T: T)
        var d = L0 - s.alpha
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d * 4
    }

    /// Geometric altitude of the Sun's centre at an instant (seconds since the Unix epoch).
    static func altitude(unix t: Double, latitude: Double, longitude: Double) -> Double {
        let jd = t / 86_400 + 2_440_587.5
        return SolarCoordinates(T: AstroMath.centuriesTT(jdUT: jd))
            .horizontal(jdUT: jd, latitude: latitude, longitudeEast: longitude).altitude
    }
}
