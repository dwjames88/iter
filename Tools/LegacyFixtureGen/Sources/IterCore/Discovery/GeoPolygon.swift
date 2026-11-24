import Foundation

/// One or more closed rings of coordinates. Containment is even-odd, so an inner ring is a hole and several
/// outer rings (an archipelago, a park in two parts) all count.
public struct GeoPolygon: Codable, Hashable, Sendable {
    public var rings: [[Coordinate]]

    public init(rings: [[Coordinate]]) {
        self.rings = rings.filter { $0.count >= 3 }
    }

    public var isEmpty: Bool { rings.isEmpty }

    /// Ray casting in (longitude, latitude), ignoring the antimeridian. Points exactly on an edge may fall either way.
    public func contains(_ point: Coordinate) -> Bool {
        var inside = false
        for ring in rings {
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[i], b = ring[j]
                if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                    let crossing = (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                    if point.longitude < crossing { inside.toggle() }
                }
                j = i
            }
        }
        return inside
    }

    /// The smallest box around every vertex (no padding). An empty polygon gives a zero-sized region at 0, 0.
    public var boundingRegion: GeoRegion {
        let all = rings.joined()
        guard let first = all.first else { return GeoRegion(center: Coordinate(latitude: 0, longitude: 0), latitudeDelta: 0, longitudeDelta: 0) }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in all {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        return GeoRegion(center: Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                         latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon)
    }
}

/// Where discovery looks: a named area, its box, and (when known) its real outline.
public struct DiscoveryArea: Hashable, Sendable {
    public var name: String?
    public var region: GeoRegion
    public var boundary: GeoPolygon?

    public init(name: String?, region: GeoRegion, boundary: GeoPolygon? = nil) {
        self.name = name
        self.region = region
        self.boundary = boundary
    }

    /// The boundary when there is one, otherwise the region's box.
    public func contains(_ coordinate: Coordinate) -> Bool {
        if let boundary, !boundary.isEmpty { return boundary.contains(coordinate) }
        return region.contains(coordinate)
    }
}
