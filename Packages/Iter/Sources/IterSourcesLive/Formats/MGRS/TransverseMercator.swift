// TransverseMercator.swift
//
// WGS84 transverse Mercator (forward and inverse) using the Kruger series to order n^6, as in
// C. F. F. Karney, "Transverse Mercator with an accuracy of a few nanometers", J. Geodesy 85 (2011),
// eqs. (35) and (36); accurate to well under a millimetre within a UTM zone. Also holds the conformal
// latitude helpers shared with the polar stereographic projection. Foundation only, pure.

import Foundation

enum GridWGS84 {
    static let a = 6378137.0
    static let f = 1.0 / 298.257223563
    static let e2 = f * (2 - f)
    static let e = e2.squareRoot()
    static let e2m = 1 - e2          // (1 - f)^2
    static let n = f / (2 - f)       // third flattening
}

/// Conformal-latitude helpers (Karney 2011, eqs. 7 and 9): taup = tan(conformal latitude), tau = tan(phi).
enum ConformalLatitude {
    static func taup(fromTau tau: Double) -> Double {
        let tau1 = (1 + tau * tau).squareRoot()
        let sig = sinh(GridWGS84.e * atanh(GridWGS84.e * tau / tau1))
        return (1 + sig * sig).squareRoot() * tau - sig * tau1
    }

    /// Inverse of `taup(fromTau:)` by Newton iteration (converges in 2 to 3 steps).
    static func tau(fromTaup taup: Double) -> Double {
        var tau = taup / GridWGS84.e2m
        for _ in 0..<12 {
            let tau1 = (1 + tau * tau).squareRoot()
            let sig = sinh(GridWGS84.e * atanh(GridWGS84.e * tau / tau1))
            let taupa = (1 + sig * sig).squareRoot() * tau - sig * tau1
            let dtau = (taup - taupa) * (1 + GridWGS84.e2m * tau * tau)
                / (GridWGS84.e2m * tau1 * (1 + taupa * taupa).squareRoot())
            tau += dtau
            if abs(dtau) < 1e-15 * max(1, abs(tau)) { break }
        }
        return tau
    }
}

struct TransverseMercator: Sendable {
    let k0: Double
    private let aRect: Double   // rectifying radius A
    private let alpha: [Double] // alpha[1...6], index 0 unused
    private let beta: [Double]

    static let utm = TransverseMercator(k0: 0.9996)

    init(k0: Double) {
        self.k0 = k0
        let n = GridWGS84.n
        let n2 = n * n, n3 = n2 * n, n4 = n2 * n2, n5 = n4 * n, n6 = n3 * n3
        aRect = GridWGS84.a / (1 + n) * (1 + n2 / 4 + n4 / 64 + n6 / 256)
        alpha = [
            0,
            n / 2 - 2 * n2 / 3 + 5 * n3 / 16 + 41 * n4 / 180 - 127 * n5 / 288 + 7891 * n6 / 37800,
            13 * n2 / 48 - 3 * n3 / 5 + 557 * n4 / 1440 + 281 * n5 / 630 - 1983433 * n6 / 1935360,
            61 * n3 / 240 - 103 * n4 / 140 + 15061 * n5 / 26880 + 167603 * n6 / 181440,
            49561 * n4 / 161280 - 179 * n5 / 168 + 6601661 * n6 / 7257600,
            34729 * n5 / 80640 - 3418889 * n6 / 1995840,
            212378941 * n6 / 319334400,
        ]
        beta = [
            0,
            n / 2 - 2 * n2 / 3 + 37 * n3 / 96 - n4 / 360 - 81 * n5 / 512 + 96199 * n6 / 604800,
            n2 / 48 + n3 / 15 - 437 * n4 / 1440 + 46 * n5 / 105 - 1118711 * n6 / 3870720,
            17 * n3 / 480 - 37 * n4 / 840 - 209 * n5 / 4480 + 5569 * n6 / 90720,
            4397 * n4 / 161280 - 11 * n5 / 504 - 830251 * n6 / 7257600,
            4583 * n5 / 161280 - 108847 * n6 / 3991680,
            20648693 * n6 / 638668800,
        ]
    }

    /// Forward projection. `lambda` is the longitude relative to the central meridian, radians (|lambda| < ~pi/2).
    /// Returns (x east of the central meridian, y north of the equator) in metres, scaled by k0.
    func forward(phi: Double, lambda: Double) -> (x: Double, y: Double) {
        let tau = tan(phi)
        let taup = ConformalLatitude.taup(fromTau: tau)
        let cl = cos(lambda), sl = sin(lambda)
        let xip = atan2(taup, cl)
        let etap = asinh(sl / (taup * taup + cl * cl).squareRoot())
        var xi = xip, eta = etap
        for j in 1...6 {
            let jj = Double(2 * j)
            xi += alpha[j] * sin(jj * xip) * cosh(jj * etap)
            eta += alpha[j] * cos(jj * xip) * sinh(jj * etap)
        }
        return (k0 * aRect * eta, k0 * aRect * xi)
    }

    /// Inverse projection from (x, y) metres relative to the central meridian and equator.
    /// Returns (phi, lambda) in radians, lambda relative to the central meridian.
    func inverse(x: Double, y: Double) -> (phi: Double, lambda: Double) {
        let xi = y / (k0 * aRect), eta = x / (k0 * aRect)
        var xip = xi, etap = eta
        for j in 1...6 {
            let jj = Double(2 * j)
            xip -= beta[j] * sin(jj * xi) * cosh(jj * eta)
            etap -= beta[j] * cos(jj * xi) * sinh(jj * eta)
        }
        let sinChi = sin(xip) / cosh(etap)
        let taup = sinChi / (1 - sinChi * sinChi).squareRoot()
        let tau = ConformalLatitude.tau(fromTaup: taup)
        return (atan(tau), atan2(sinh(etap), cos(xip)))
    }
}
