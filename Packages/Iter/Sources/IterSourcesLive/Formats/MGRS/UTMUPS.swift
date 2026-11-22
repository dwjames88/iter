// UTMUPS.swift
//
// Universal Transverse Mercator (80 S to 84 N) and Universal Polar Stereographic (beyond those
// latitudes) on WGS84. UTM uses the Kruger series (TransverseMercator.swift). UPS follows the
// ellipsoidal polar stereographic of Snyder (1987) as formulated by Karney (GeographicLib,
// PolarStereographic) using the exact conformal-latitude relations. Pure, Foundation only.
//
// Zones: 1 to 60 by 6 degrees from 180 W, with the Norway exception (56 N to 64 N, 3 E to 12 E is
// zone 32) and the Svalbard exceptions (72 N to 84 N: zones 31, 33, 35, 37 are widened and 32, 34,
// 36 are not used). A `UTMUPSCoordinate` with zone 0 is a UPS coordinate.

import Foundation

public enum MGRSError: Error, Sendable, Equatable {
    /// Latitude not finite or outside -90...90.
    case invalidLatitude
    /// Longitude not finite.
    case invalidLongitude
    /// UTM was requested for a latitude outside 80 S to 84 N (use UPS or MGRS, which handles the poles).
    case outsideUTMCoverage
    /// Precision (digits per coordinate) not in 0...5.
    case invalidPrecision
    /// The MGRS text or its components are malformed or inconsistent.
    case invalidReference(String)
    /// Easting/northing/zone do not describe a valid point.
    case invalidCoordinate
}

/// A UTM or UPS coordinate in metres. `zone` 0 means UPS.
public struct UTMUPSCoordinate: Sendable, Equatable {
    /// UTM zone 1...60, or 0 for UPS.
    public var zone: Int
    public var isNorth: Bool
    /// Easting including the 500 km (UTM) or 2000 km (UPS) false easting.
    public var easting: Double
    /// Northing including the 10,000 km (UTM, southern hemisphere) or 2000 km (UPS) false northing.
    public var northing: Double
    /// Point scale factor is not stored; use `convergence` APIs if needed later.
    public var isPolar: Bool { zone == 0 }

    public init(zone: Int, isNorth: Bool, easting: Double, northing: Double) {
        self.zone = zone; self.isNorth = isNorth; self.easting = easting; self.northing = northing
    }
}

public enum UTM {
    public static let minimumLatitude = -80.0
    public static let maximumLatitude = 84.0
    static let k0 = 0.9996

    /// Wraps longitude into [-180, 180): the antimeridian is -180, which is the west edge of zone 1
    /// (NGA GEOTRANS does the same: longitude 180 gives zone 1).
    static func normalise(longitude: Double) -> Double {
        if longitude >= -180 && longitude < 180 { return longitude }
        var l = longitude.truncatingRemainder(dividingBy: 360)
        if l >= 180 { l -= 360 } else if l < -180 { l += 360 }
        return l
    }

    /// The UTM zone number (1...60) for a point, with the Norway and Svalbard exceptions.
    public static func zone(latitude: Double, longitude: Double) -> Int {
        let lon = normalise(longitude: longitude)
        var zone = min(60, Int(floor((lon + 180) / 6)) + 1)
        if latitude >= 56 && latitude < 64 && lon >= 3 && lon < 12 {
            zone = 32
        } else if latitude >= 72 && latitude <= 84 {
            if lon >= 0 && lon < 9 { zone = 31 }
            else if lon >= 9 && lon < 21 { zone = 33 }
            else if lon >= 21 && lon < 33 { zone = 35 }
            else if lon >= 33 && lon < 42 { zone = 37 }
        }
        return zone
    }

    /// Central meridian of a zone, degrees (the nominal one: -177 + 6 (zone - 1)).
    public static func centralMeridian(zone: Int) -> Double { Double(zone - 1) * 6 - 180 + 3 }

    /// Forward UTM. Throws `.outsideUTMCoverage` outside 80 S to 84 N. `zone` overrides the automatic zone.
    public static func forward(latitude: Double, longitude: Double, zone override: Int? = nil) throws -> UTMUPSCoordinate {
        guard latitude.isFinite, abs(latitude) <= 90 else { throw MGRSError.invalidLatitude }
        guard longitude.isFinite else { throw MGRSError.invalidLongitude }
        guard latitude >= minimumLatitude, latitude <= maximumLatitude else { throw MGRSError.outsideUTMCoverage }
        let zone = override ?? Self.zone(latitude: latitude, longitude: longitude)
        guard (1...60).contains(zone) else { throw MGRSError.invalidCoordinate }
        let lon = normalise(longitude: longitude)
        let lambda = normalise(longitude: lon - centralMeridian(zone: zone)) * .pi / 180
        let (x, y) = TransverseMercator.utm.forward(phi: latitude * .pi / 180, lambda: lambda)
        let north = latitude >= 0
        return UTMUPSCoordinate(zone: zone, isNorth: north, easting: 500_000 + x,
                                northing: y + (north ? 0 : 10_000_000))
    }

    /// Inverse UTM; returns (latitude, longitude) in degrees, longitude in (-180, 180].
    public static func inverse(_ c: UTMUPSCoordinate) throws -> (latitude: Double, longitude: Double) {
        guard (1...60).contains(c.zone), c.easting.isFinite, c.northing.isFinite else { throw MGRSError.invalidCoordinate }
        let (phi, lambda) = TransverseMercator.utm.inverse(
            x: c.easting - 500_000, y: c.northing - (c.isNorth ? 0 : 10_000_000))
        return (phi * 180 / .pi, normalise(longitude: centralMeridian(zone: c.zone) + lambda * 180 / .pi))
    }
}

public enum UPS {
    static let k0 = 0.994
    static let falseOrigin = 2_000_000.0

    private static var c: Double { (1 - GridWGS84.f) * exp(GridWGS84.e * atanh(GridWGS84.e)) }

    /// Forward UPS: north for latitude >= 0, south otherwise. Meant for latitudes beyond 84 N / 80 S, but
    /// accurate anywhere away from the opposite pole.
    public static func forward(latitude: Double, longitude: Double) throws -> UTMUPSCoordinate {
        guard latitude.isFinite, abs(latitude) <= 90 else { throw MGRSError.invalidLatitude }
        guard longitude.isFinite else { throw MGRSError.invalidLongitude }
        let north = latitude >= 0
        let absLat = abs(latitude)
        var rho = 0.0
        if absLat < 90 {
            let taup = ConformalLatitude.taup(fromTau: tan(absLat * .pi / 180))
            rho = 2 * k0 * GridWGS84.a / c / ((1 + taup * taup).squareRoot() + taup)
        }
        let lam = UTM.normalise(longitude: longitude) * .pi / 180
        let x = rho * sin(lam)
        let y = (north ? -1.0 : 1.0) * rho * cos(lam)
        return UTMUPSCoordinate(zone: 0, isNorth: north, easting: falseOrigin + x, northing: falseOrigin + y)
    }

    public static func inverse(_ p: UTMUPSCoordinate) throws -> (latitude: Double, longitude: Double) {
        guard p.zone == 0, p.easting.isFinite, p.northing.isFinite else { throw MGRSError.invalidCoordinate }
        let x = p.easting - falseOrigin, y = p.northing - falseOrigin
        let rho = (x * x + y * y).squareRoot()
        let t = rho != 0 ? rho / (2 * k0 * GridWGS84.a / c) : Double.ulpOfOne * Double.ulpOfOne
        let taup = (1 / t - t) / 2
        let tau = ConformalLatitude.tau(fromTaup: taup)
        var lat = atan(tau) * 180 / .pi
        if !p.isNorth { lat = -lat }
        let lon = UTM.normalise(longitude: atan2(x, p.isNorth ? -y : y) * 180 / .pi)
        return (lat, lon)
    }
}
