import Foundation
import IterCore

/// Moon position from Meeus ch. 47, abridged to the largest periodic terms
/// (32 longitude/distance terms, 30 latitude terms, plus the planetary and flattening additives).
/// The truncation error is a few hundredths of a degree in longitude, well inside what rise/set and phase need.
struct LunarCoordinates {
    var longitude: Double        // geometric ecliptic longitude, degrees
    var latitude: Double         // ecliptic latitude, degrees
    var distanceKm: Double
    var apparentLongitude: Double // longitude + nutation in longitude
    var alpha: Double            // apparent geocentric right ascension, degrees
    var delta: Double            // apparent geocentric declination, degrees
    var parallax: Double         // equatorial horizontal parallax, degrees

    // D, M, M', F multipliers, Σl (1e-6 deg), Σr (1e-3 km)
    private static let lonDist: [(Int, Int, Int, Int, Double, Double)] = [
        (0, 0, 1, 0, 6_288_774, -20_905_355), (2, 0, -1, 0, 1_274_027, -3_699_111),
        (2, 0, 0, 0, 658_314, -2_955_968), (0, 0, 2, 0, 213_618, -569_925),
        (0, 1, 0, 0, -185_116, 48_888), (0, 0, 0, 2, -114_332, -3_149),
        (2, 0, -2, 0, 58_793, 246_158), (2, -1, -1, 0, 57_066, -152_138),
        (2, 0, 1, 0, 53_322, -170_733), (2, -1, 0, 0, 45_758, -204_586),
        (0, 1, -1, 0, -40_923, -129_620), (1, 0, 0, 0, -34_720, 108_743),
        (0, 1, 1, 0, -30_383, 104_755), (2, 0, 0, -2, 15_327, 10_321),
        (0, 0, 1, 2, -12_528, 0), (0, 0, 1, -2, 10_980, 79_661),
        (4, 0, -1, 0, 10_675, -34_782), (0, 0, 3, 0, 10_034, -23_210),
        (4, 0, -2, 0, 8_548, -21_636), (2, 1, -1, 0, -7_888, 24_208),
        (2, 1, 0, 0, -6_766, 30_824), (1, 0, -1, 0, -5_163, -8_379),
        (1, 1, 0, 0, 4_987, -16_675), (2, -1, 1, 0, 4_036, -12_831),
        (2, 0, 2, 0, 3_994, -10_445), (4, 0, 0, 0, 3_861, -11_650),
        (2, 0, -3, 0, 3_665, 14_403), (0, 1, -2, 0, -2_689, -7_003),
        (2, 0, -1, 2, -2_602, 0), (2, -1, -2, 0, 2_390, 10_056),
        (1, 0, 1, 0, -2_348, 6_322), (2, -2, 0, 0, 2_236, -9_884),
    ]

    // D, M, M', F multipliers, Σb (1e-6 deg)
    private static let lat: [(Int, Int, Int, Int, Double)] = [
        (0, 0, 0, 1, 5_128_122), (0, 0, 1, 1, 280_602), (0, 0, 1, -1, 277_693),
        (2, 0, 0, -1, 173_237), (2, 0, -1, 1, 55_413), (2, 0, -1, -1, 46_271),
        (2, 0, 0, 1, 32_573), (0, 0, 2, 1, 17_198), (2, 0, 1, -1, 9_266),
        (0, 0, 2, -1, 8_822), (2, -1, 0, -1, 8_216), (2, 0, -2, -1, 4_324),
        (2, 0, 1, 1, 4_200), (2, 1, 0, -1, -3_359), (2, -1, -1, 1, 2_463),
        (2, -1, 0, 1, 2_211), (2, -1, -1, -1, 2_065), (0, 1, -1, -1, -1_870),
        (4, 0, -1, -1, 1_828), (0, 1, 0, 1, -1_794), (0, 0, 0, 3, -1_749),
        (0, 1, -1, 1, -1_565), (1, 0, 0, 1, -1_491), (0, 1, 1, 1, -1_475),
        (0, 1, 1, -1, -1_410), (0, 1, 0, -1, -1_344), (1, 0, 0, -1, -1_335),
        (0, 0, 3, 1, 1_107), (4, 0, 0, -1, 1_021), (4, 0, -1, 1, 833),
    ]

    /// `T` is Julian centuries of dynamical time since J2000.0.
    init(T: Double) {
        let r = AstroMath.rad
        let Lp = AstroMath.norm360(218.3164477 + 481267.88123421 * T - 0.0015786 * T * T)
        let D = AstroMath.norm360(297.8501921 + 445267.1114034 * T - 0.0018819 * T * T)
        let M = AstroMath.norm360(357.5291092 + 35999.0502909 * T - 0.0001536 * T * T)
        let Mp = AstroMath.norm360(134.9633964 + 477198.8675055 * T + 0.0087414 * T * T)
        let F = AstroMath.norm360(93.2720950 + 483202.0175233 * T - 0.0036539 * T * T)
        let A1 = r(119.75 + 131.849 * T)
        let A2 = r(53.09 + 479264.290 * T)
        let A3 = r(313.45 + 481266.484 * T)
        let E = 1 - 0.002516 * T - 0.0000074 * T * T

        var sumL = 0.0, sumR = 0.0, sumB = 0.0
        for t in Self.lonDist {
            let arg = r(Double(t.0) * D + Double(t.1) * M + Double(t.2) * Mp + Double(t.3) * F)
            let e = abs(t.1) == 1 ? E : (abs(t.1) == 2 ? E * E : 1)
            sumL += t.4 * e * sin(arg)
            sumR += t.5 * e * cos(arg)
        }
        for t in Self.lat {
            let arg = r(Double(t.0) * D + Double(t.1) * M + Double(t.2) * Mp + Double(t.3) * F)
            let e = abs(t.1) == 1 ? E : (abs(t.1) == 2 ? E * E : 1)
            sumB += t.4 * e * sin(arg)
        }
        sumL += 3958 * sin(A1) + 1962 * sin(r(Lp - F)) + 318 * sin(A2)
        sumB += -2235 * sin(r(Lp)) + 382 * sin(A3) + 175 * sin(A1 - r(F)) + 175 * sin(A1 + r(F))
            + 127 * sin(r(Lp - Mp)) - 115 * sin(r(Lp + Mp))

        longitude = AstroMath.norm360(Lp + sumL / 1e6)
        latitude = sumB / 1e6
        distanceKm = 385_000.56 + sumR / 1000
        parallax = AstroMath.deg(asin(6378.14 / distanceKm))

        let nut = AstroMath.nutation(T: T)
        apparentLongitude = AstroMath.norm360(longitude + nut.dpsi)
        let eps = AstroMath.meanObliquity(T: T) + nut.deps
        let eq = AstroMath.equatorial(lambda: apparentLongitude, beta: latitude, eps: eps)
        alpha = eq.alpha
        delta = eq.delta
    }

    /// Topocentric altitude (parallax applied, no refraction) and azimuth. The parallax is applied in altitude
    /// only on a spherical Earth, which is accurate to a few thousandths of a degree for the Moon.
    func topocentric(jdUT: Double, latitude: Double, longitudeEast: Double) -> (altitude: Double, azimuth: Double) {
        let g = AstroMath.horizontal(alpha: alpha, delta: delta, jdUT: jdUT, latitude: latitude, longitudeEast: longitudeEast)
        let h = AstroMath.rad(g.altitude)
        let sinPi = 6378.14 / distanceKm
        let alt = atan2(sin(h) - sinPi, cos(h))
        return (AstroMath.deg(alt), g.azimuth)
    }

    /// Illuminated fraction and phase cycle (Meeus ch. 48) given the Sun's coordinates at the same instant.
    func phase(sun: SolarCoordinates) -> MoonPhase {
        let r = AstroMath.rad
        let cosPsi = cos(r(latitude)) * cos(r(apparentLongitude - sun.apparentLongitude))
        let psi = acos(max(-1, min(1, cosPsi)))
        let sunKm = sun.distanceAU * 149_597_870.7
        let i = atan2(sunKm * sin(psi), distanceKm - sunKm * cos(psi))
        let k = (1 + cos(i)) / 2
        let cycle = AstroMath.norm360(apparentLongitude - sun.apparentLongitude) / 360
        return MoonPhase(illumination: k, cycle: cycle)
    }
}
