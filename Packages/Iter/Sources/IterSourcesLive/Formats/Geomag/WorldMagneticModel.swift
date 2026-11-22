// WorldMagneticModel.swift
//
// On-device World Magnetic Model 2025 (WMM2025) evaluation: magnetic declination, inclination and the
// full field vector with secular variation. Pure Swift, Foundation only, no networking, no clock.
//
// Method: WMM2025 Technical Report equations. Geodetic position on the WGS84 ellipsoid is converted to
// geocentric spherical coordinates, Schmidt semi-normalised associated Legendre functions are built by
// recurrence to degree 12, the coefficients are advanced linearly to the requested epoch
// g(t) = g + gdot (t - t0), the field is summed in spherical components (radius 6371.2 km) and rotated
// back to the geodetic frame. Rates come from summing the secular-variation coefficients alone.
//
// Coefficients: see WMM2025Coefficients.swift (NOAA/NCEI, public domain).
//
// Validity: the model is valid for decimal years 2025.0 through 2030.0 inclusive. `evaluate` throws
// `WorldMagneticModelError.outsideValidity` outside that window rather than silently extrapolating.
//
// Poles: the east component divides P(n,m) by sin(colatitude). That ratio is computed directly by a
// recurrence (no division), so evaluation is finite at the geographic poles, where Y comes from the
// m = 1 terms exactly as in the official software; declination at a pole is then atan2(Y, X) for the
// supplied longitude.

import Foundation

/// The magnetic field at one point and instant, in the geodetic (north, east, down) frame.
public struct MagneticField: Sendable, Equatable {
    /// North component, nT.
    public var north: Double
    /// East component, nT.
    public var east: Double
    /// Down component, nT.
    public var down: Double
    /// Horizontal intensity, nT.
    public var horizontal: Double
    /// Total intensity, nT.
    public var total: Double
    /// Inclination (dip), degrees, positive down.
    public var inclination: Double
    /// Declination, degrees east of true north.
    public var declination: Double
    /// Grid variation, degrees; only defined poleward of 55 degrees latitude, otherwise nil.
    public var gridVariation: Double?

    /// Secular variation, per year: nT/yr for components and intensities, degrees/yr for the angles.
    public var northRate: Double
    public var eastRate: Double
    public var downRate: Double
    public var horizontalRate: Double
    public var totalRate: Double
    public var inclinationRate: Double
    public var declinationRate: Double

    /// Conventional names X, Y, Z for north, east, down.
    public var x: Double { north }
    public var y: Double { east }
    public var z: Double { down }
}

public enum WorldMagneticModelError: Error, Sendable, Equatable {
    /// The decimal year is outside `WorldMagneticModel.validRange`.
    case outsideValidity(decimalYear: Double)
    /// Latitude not in [-90, 90], or an input is not finite.
    case invalidInput
}

public enum WorldMagneticModel {
    /// Epoch of the coefficients (decimal year).
    public static let epoch: Double = coefficients.epoch
    /// Model name from the coefficient header, `WMM-2025`.
    public static let name: String = coefficients.name
    /// Release date from the coefficient header, `11/13/2024`.
    public static let releaseDate: String = coefficients.releaseDate
    /// Decimal years for which the model is valid (inclusive).
    public static let validRange: ClosedRange<Double> = 2025.0...2030.0

    /// Evaluates the field.
    /// - Parameters:
    ///   - latitude: geodetic latitude, degrees (-90...90).
    ///   - longitude: geodetic longitude, degrees east (any value; wrapped by trigonometry).
    ///   - altitudeKm: height above the WGS84 ellipsoid, kilometres.
    ///   - decimalYear: for example 2026.8904; see `decimalYear(for:)`.
    /// - Throws: `WorldMagneticModelError`.
    public static func evaluate(
        latitude: Double, longitude: Double, altitudeKm: Double, decimalYear: Double
    ) throws -> MagneticField {
        guard latitude.isFinite, longitude.isFinite, altitudeKm.isFinite, decimalYear.isFinite,
              abs(latitude) <= 90 else { throw WorldMagneticModelError.invalidInput }
        guard validRange.contains(decimalYear) else {
            throw WorldMagneticModelError.outsideValidity(decimalYear: decimalYear)
        }
        return compute(latitude: latitude, longitude: longitude, altitudeKm: altitudeKm,
                       dt: decimalYear - coefficients.epoch)
    }

    /// Convenience: evaluates for a `Date` using a UTC calendar.
    public static func evaluate(
        latitude: Double, longitude: Double, altitudeKm: Double, date: Date
    ) throws -> MagneticField {
        try evaluate(latitude: latitude, longitude: longitude, altitudeKm: altitudeKm,
                     decimalYear: decimalYear(for: date))
    }

    /// Decimal year of an instant: year + elapsed fraction of that UTC year.
    public static func decimalYear(for date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.year, from: date)
        var c = DateComponents()
        c.year = year; c.month = 1; c.day = 1
        let start = calendar.date(from: c)!
        c.year = year + 1
        let end = calendar.date(from: c)!
        let fraction = date.timeIntervalSince(start) / end.timeIntervalSince(start)
        return Double(year) + fraction
    }

    // MARK: - Coefficients

    private struct Coefficients: Sendable {
        var epoch: Double
        var name: String
        var releaseDate: String
        // Indexed [n][m], n and m in 0...12.
        var g: [[Double]]
        var h: [[Double]]
        var gDot: [[Double]]
        var hDot: [[Double]]
        var rowCount = 0
    }

    private static let degree = 12

    private static let coefficients: Coefficients = parse(WMM2025Coefficients.cofText)

    /// Parses `WMM.COF` text. Exposed to tests through `parsedRowCount`.
    private static func parse(_ text: String) -> Coefficients {
        let n = degree
        let zeros = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n + 1)
        var result = Coefficients(epoch: 0, name: "", releaseDate: "", g: zeros, h: zeros, gDot: zeros, hDot: zeros)
        var headerSeen = false
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard !fields.isEmpty else { continue }
            if !headerSeen {
                headerSeen = true
                result.epoch = Double(fields[0]) ?? 0
                result.name = fields.count > 1 ? String(fields[1]) : ""
                result.releaseDate = fields.count > 2 ? String(fields[2]) : ""
                continue
            }
            if fields[0].hasPrefix("9999") { break }
            guard fields.count >= 6, let degreeN = Int(fields[0]), let order = Int(fields[1]),
                  degreeN <= n, order <= degreeN,
                  let g = Double(fields[2]), let h = Double(fields[3]),
                  let gd = Double(fields[4]), let hd = Double(fields[5]) else { continue }
            result.g[degreeN][order] = g
            result.h[degreeN][order] = h
            result.gDot[degreeN][order] = gd
            result.hDot[degreeN][order] = hd
            result.rowCount += 1
        }
        return result
    }

    /// Number of coefficient rows read from the embedded text (90 for WMM2025). For tests.
    static var parsedRowCount: Int { coefficients.rowCount }

    // MARK: - Computation

    private static let semiMajorKm = 6378.137
    private static let flattening = 1.0 / 298.257223563
    private static let referenceRadiusKm = 6371.2

    /// Field vector (spherical, geocentric) from one set of coefficients; `rates` selects the dot terms.
    private static func sum(
        r: Double, ct: Double, st: Double, longitude: Double, rates: Bool, c: Coefficients
    ) -> (br: Double, bt: Double, bp: Double) {
        let n = degree
        // P: Schmidt semi-normalised Legendre; dP: d/dtheta; q: P / sin(theta) (no division).
        var p = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n + 1)
        var dp = p
        var q = p
        p[0][0] = 1
        for nn in 1...n {
            for m in 0...nn {
                if nn == m {
                    if nn == 1 {
                        p[1][1] = st; dp[1][1] = ct; q[1][1] = 1
                    } else {
                        let k = (Double(2 * nn - 1) / Double(2 * nn)).squareRoot()
                        p[nn][nn] = k * st * p[nn - 1][nn - 1]
                        dp[nn][nn] = k * (st * dp[nn - 1][nn - 1] + ct * p[nn - 1][nn - 1])
                        q[nn][nn] = k * p[nn - 1][nn - 1]
                    }
                } else {
                    let d = Double(nn * nn - m * m).squareRoot()
                    let k2 = nn - 1 >= m ? Double((nn - 1) * (nn - 1) - m * m).squareRoot() : 0
                    let p2 = nn >= 2 ? p[nn - 2][m] : 0
                    let dp2 = nn >= 2 ? dp[nn - 2][m] : 0
                    let q2 = nn >= 2 ? q[nn - 2][m] : 0
                    let a = Double(2 * nn - 1)
                    p[nn][m] = (a * ct * p[nn - 1][m] - k2 * p2) / d
                    dp[nn][m] = (a * (ct * dp[nn - 1][m] - st * p[nn - 1][m]) - k2 * dp2) / d
                    q[nn][m] = (a * ct * q[nn - 1][m] - k2 * q2) / d
                }
            }
        }
        var br = 0.0, bt = 0.0, bp = 0.0
        for nn in 1...n {
            let rr = pow(referenceRadiusKm / r, Double(nn + 2))
            for m in 0...nn {
                let gc = rates ? c.gDot[nn][m] : c.g[nn][m]
                let hc = rates ? c.hDot[nn][m] : c.h[nn][m]
                let cm = cos(Double(m) * longitude), sm = sin(Double(m) * longitude)
                br += rr * Double(nn + 1) * (gc * cm + hc * sm) * p[nn][m]
                bt -= rr * (gc * cm + hc * sm) * dp[nn][m]
                bp += rr * Double(m) * (gc * sm - hc * cm) * q[nn][m]
            }
        }
        return (br, bt, bp)
    }

    private static func compute(latitude: Double, longitude: Double, altitudeKm: Double, dt: Double) -> MagneticField {
        let c = coefficients
        let e2 = flattening * (2 - flattening)
        let phi = latitude * .pi / 180
        let lambda = longitude * .pi / 180
        let sinPhi = sin(phi), cosPhi = cos(phi)
        let rc = semiMajorKm / (1 - e2 * sinPhi * sinPhi).squareRoot()
        let pxy = (rc + altitudeKm) * cosPhi
        let pz = (rc * (1 - e2) + altitudeKm) * sinPhi
        let r = (pxy * pxy + pz * pz).squareRoot()
        let phiC = asin(pz / r)               // geocentric latitude
        let theta = Double.pi / 2 - phiC      // colatitude
        let ct = cos(theta), st = sin(theta)

        // Time-adjusted coefficients g(t) = g + gdot dt, built into a working copy.
        var adjusted = c
        for nn in 1...degree {
            for m in 0...nn {
                adjusted.g[nn][m] = c.g[nn][m] + dt * c.gDot[nn][m]
                adjusted.h[nn][m] = c.h[nn][m] + dt * c.hDot[nn][m]
            }
        }
        let main = sum(r: r, ct: ct, st: st, longitude: lambda, rates: false, c: adjusted)
        let sv = sum(r: r, ct: ct, st: st, longitude: lambda, rates: true, c: c)

        // Spherical (r, theta, phi) -> geocentric north, east, down, then rotate to geodetic.
        let psi = phi - phiC
        let cp = cos(psi), sp = sin(psi)
        func rotate(_ b: (br: Double, bt: Double, bp: Double)) -> (Double, Double, Double) {
            let xc = -b.bt, yc = b.bp, zc = -b.br
            return (xc * cp + zc * sp, yc, -xc * sp + zc * cp)
        }
        let (x, y, z) = rotate(main)
        let (xd, yd, zd) = rotate(sv)

        let h = (x * x + y * y).squareRoot()
        let f = (h * h + z * z).squareRoot()
        let deg = 180 / Double.pi
        let inc = atan2(z, h) * deg
        let dec = atan2(y, x) * deg

        // Official rate formulas.
        let hd = h > 0 ? (x * xd + y * yd) / h : 0
        let fd = (x * xd + y * yd + z * zd) / f
        let dd = h > 0 ? (x * yd - y * xd) / (h * h) * deg : 0
        let id = (h * zd - z * hd) / (f * f) * deg

        var gv: Double?
        if latitude > 55 {
            gv = normalise(dec - longitude)
        } else if latitude < -55 {
            gv = normalise(dec + longitude)
        }
        return MagneticField(
            north: x, east: y, down: z, horizontal: h, total: f, inclination: inc, declination: dec,
            gridVariation: gv, northRate: xd, eastRate: yd, downRate: zd, horizontalRate: hd,
            totalRate: fd, inclinationRate: id, declinationRate: dd)
    }

    /// Wraps degrees into (-180, 180].
    private static func normalise(_ d: Double) -> Double {
        var v = d.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 } else if v <= -180 { v += 360 }
        return v
    }
}
