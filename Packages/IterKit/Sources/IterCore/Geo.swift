import Foundation

/// A point on the earth in degrees (WGS 84). Platform-neutral stand-in for `CLLocationCoordinate2D`.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public static let earthRadiusMeters = 6_371_008.8

    /// Great-circle distance in metres (haversine).
    public func distance(to other: Coordinate) -> Double {
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let dφ = (other.latitude - latitude) * .pi / 180
        let dλ = (other.longitude - longitude) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * Coordinate.earthRadiusMeters * asin(min(1, sqrt(a)))
    }

    /// Initial compass bearing in degrees (0 = north, 90 = east) toward `other`.
    public func bearing(to other: Coordinate) -> Double {
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let dλ = (other.longitude - longitude) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    /// A key stable to about 100 m, for caches.
    public var cacheKey: String {
        String(format: "%.3f,%.3f", latitude, longitude)
    }
}

/// A geographic box, used to describe a map region without depending on MapKit.
public struct GeoRegion: Codable, Hashable, Sendable {
    public var center: Coordinate
    public var latitudeDelta: Double
    public var longitudeDelta: Double

    public init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        self.center = center
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }

    /// The smallest region containing every coordinate, padded by `padding` (a fraction of the span).
    public static func enclosing(_ coordinates: [Coordinate], padding: Double = 0.2, minimumDelta: Double = 0.05) -> GeoRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates.dropFirst() {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let latDelta = max(minimumDelta, (maxLat - minLat) * (1 + padding))
        let lonDelta = max(minimumDelta, (maxLon - minLon) * (1 + padding))
        return GeoRegion(center: Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                         latitudeDelta: latDelta, longitudeDelta: lonDelta)
    }

    public func contains(_ c: Coordinate) -> Bool {
        abs(c.latitude - center.latitude) <= latitudeDelta / 2 && abs(c.longitude - center.longitude) <= longitudeDelta / 2
    }
}

/// Sixteen-point compass label for a bearing, e.g. 100° → "E".
public func compassPoint(for bearing: Double) -> String {
    let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    let normalised = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return points[Int((normalised / 22.5).rounded()) % 16]
}
