import Foundation
import IterCore

/// OpenStreetMap through the public Overpass API: named peaks, waterfalls, viewpoints and so on inside the area's box.
/// Free, no key. One request, a result cap, and a server-side timeout so a busy server answers instead of hanging.
public struct OverpassProvider: DiscoveryProvider {
    public static let endpoint = "https://overpass-api.de/api/interpreter"
    /// Most elements one feature query returns (Overpass picks by id, so a big area can be cut; the cap keeps replies small).
    public static let resultCap = 400
    /// Per-kind cap when no feature is named and four kinds are fetched.
    public static let perKindCap = 100

    public let id = DiscoverySourceID.openStreetMap
    private let http: DiscoveryHTTP

    public init(http: DiscoveryHTTP) { self.http = http }

    public func discover(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        let query = Self.query(region: area.boundary?.boundingRegion ?? area.region, feature: feature)
        let data = try await http.post(URL(string: Self.endpoint)!, form: ["data": query], host: .overpass, isCacheable: OverpassParser.looksLikeJSON)
        return try OverpassParser.places(from: data, defaultFeature: feature)
    }

    /// The Overpass QL for a feature (or, with none, viewpoints, peaks, waterfalls and lakes) in a box.
    static func query(region: GeoRegion, feature: FeatureKind?) -> String {
        let s = region.center.latitude - region.latitudeDelta / 2, n = region.center.latitude + region.latitudeDelta / 2
        let w = region.center.longitude - region.longitudeDelta / 2, e = region.center.longitude + region.longitudeDelta / 2
        let bbox = String(format: "(%.5f,%.5f,%.5f,%.5f)", max(-90, s), max(-180, w), min(90, n), min(180, e))
        var out = "[out:json][timeout:20];\n"
        if let feature {
            out += "(\n" + feature.osmTags.map { "  nwr\($0.overpassFilters)\(bbox);" }.joined(separator: "\n") + "\n);\n"
            out += "out center tags \(resultCap);"
        } else {
            for kind in [FeatureKind.viewpoint, .peak, .waterfall, .lake] {
                out += "(\n" + kind.osmTags.map { "  nwr\($0.overpassFilters)\(bbox);" }.joined(separator: "\n") + "\n);\n"
                out += "out center tags \(perKindCap);\n"
            }
        }
        return out
    }
}

/// Reads Overpass JSON. Pure.
enum OverpassParser {
    static func looksLikeJSON(_ data: Data) -> Bool {
        data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }) == UInt8(ascii: "{")
    }

    /// Named elements with a position. `defaultFeature` labels them when the tags do not say.
    static func places(from data: Data, defaultFeature: FeatureKind?) throws -> [DiscoveredPlace] {
        guard looksLikeJSON(data) else {
            // Overpass answers an overloaded request with an HTML page and status 200.
            let text = String(decoding: data.prefix(2_000), as: UTF8.self).lowercased()
            throw text.contains("too busy") || text.contains("timeout") || text.contains("rate_limited") ? DiscoveryError.busy : DiscoveryError.badResponse
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { throw DiscoveryError.badResponse }
        var seen = Set<String>()
        var result: [DiscoveredPlace] = []
        for element in elements {
            guard let tags = element["tags"] as? [String: Any], let rawName = tags["name"] as? String else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let coordinate = coordinate(of: element) else { continue }
            guard seen.insert(name + "@" + coordinate.cacheKey).inserted else { continue }
            var links: [URL] = []
            if let wiki = tags["wikipedia"] as? String, let url = wikipediaURL(wiki) { links.append(url) }
            if let q = tags["wikidata"] as? String, q.hasPrefix("Q"), let url = URL(string: "https://www.wikidata.org/wiki/\(q)") { links.append(url) }
            result.append(DiscoveredPlace(name: name, coordinate: coordinate,
                                          elevationMeters: (tags["ele"] as? String).flatMap(ElevationParser.metres(from:)),
                                          feature: feature(of: tags) ?? defaultFeature,
                                          sources: [.openStreetMap], links: links))
        }
        return result
    }

    private static func coordinate(of element: [String: Any]) -> Coordinate? {
        func make(_ lat: Any?, _ lon: Any?) -> Coordinate? {
            guard let la = (lat as? NSNumber)?.doubleValue, let lo = (lon as? NSNumber)?.doubleValue,
                  (-90...90).contains(la), (-180...180).contains(lo) else { return nil }
            return Coordinate(latitude: la, longitude: lo)
        }
        if let c = make(element["lat"], element["lon"]) { return c }
        if let center = element["center"] as? [String: Any] { return make(center["lat"], center["lon"]) }
        return nil
    }

    /// "en:Mount Cleveland (Montana)" -> https://en.wikipedia.org/wiki/Mount_Cleveland_(Montana)
    static func wikipediaURL(_ tag: String) -> URL? {
        let parts = tag.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].range(of: #"^[a-z\-]{2,12}$"#, options: .regularExpression) != nil else { return nil }
        let title = parts[1].replacingOccurrences(of: " ", with: "_")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://\(parts[0]).wikipedia.org/wiki/\(encoded)")
    }

    private static func feature(of tags: [String: Any]) -> FeatureKind? {
        for kind in FeatureKind.allCases {
            for tag in kind.osmTags {
                guard let value = tags[tag.key] as? String, tag.values.contains(value) else { continue }
                if let n = tag.nameContains, !((tags["name"] as? String) ?? "").contains(n) { continue }
                return kind
            }
        }
        return nil
    }
}

/// Finds the real outline of a national park, nature reserve or protected area by name, from OSM relations.
public struct OverpassBoundary: BoundaryResolving {
    private let http: DiscoveryHTTP

    public init(http: DiscoveryHTTP) { self.http = http }

    /// The outline of the named area near `region`, or nil on any failure (no match, busy server, rings that do not close).
    public func resolveBoundary(areaName: String, near region: GeoRegion?) async -> GeoPolygon? {
        let name = areaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let query = Self.query(areaName: name, near: region)
        guard let data = try? await http.post(URL(string: OverpassProvider.endpoint)!, form: ["data": query], host: .overpass,
                                              isCacheable: OverpassParser.looksLikeJSON) else { return nil }
        return Self.polygon(from: data, near: region?.center)
    }

    static func query(areaName: String, near region: GeoRegion?) -> String {
        // Matches "Yosemite" and "Yosemite National Park" alike, case-insensitively.
        let base = areaName.replacingOccurrences(of: #"(?i)\s+national\s+park$"#, with: "", options: .regularExpression)
        let pattern = "^" + NSRegularExpression.escapedPattern(for: base) + "( National Park)?$"
        let quoted = pattern.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var bbox = ""
        if let r = region {
            // A generous box around the centre so a boundary larger than the guessed region is still found.
            let pad = max(r.latitudeDelta, r.longitudeDelta, 0.5)
            bbox = String(format: "(%.4f,%.4f,%.4f,%.4f)", max(-90, r.center.latitude - pad), max(-180, r.center.longitude - pad),
                          min(90, r.center.latitude + pad), min(180, r.center.longitude + pad))
        }
        return """
        [out:json][timeout:25];
        (
          relation["boundary"~"^(national_park|protected_area)$"]["name"~"\(quoted)",i]\(bbox);
          relation["leisure"="nature_reserve"]["name"~"\(quoted)",i]\(bbox);
        );
        out geom;
        """
    }

    /// Chooses the largest relation that contains `point` (or the largest overall) and assembles its rings.
    static func polygon(from data: Data, near point: Coordinate?) -> GeoPolygon? {
        guard OverpassParser.looksLikeJSON(data),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return nil }
        var candidates: [GeoPolygon] = []
        for element in elements where element["type"] as? String == "relation" {
            let members = (element["members"] as? [[String: Any]]) ?? []
            var outer: [[Coordinate]] = [], inner: [[Coordinate]] = []
            for m in members where m["type"] as? String == "way" {
                let line = ((m["geometry"] as? [[String: Any]]) ?? []).compactMap { p -> Coordinate? in
                    guard let la = (p["lat"] as? NSNumber)?.doubleValue, let lo = (p["lon"] as? NSNumber)?.doubleValue else { return nil }
                    return Coordinate(latitude: la, longitude: lo)
                }
                guard line.count >= 2 else { continue }
                if (m["role"] as? String) == "inner" { inner.append(line) } else { outer.append(line) }
            }
            let rings = assembleRings(outer) + assembleRings(inner)
            let polygon = GeoPolygon(rings: rings)
            if !assembleRings(outer).isEmpty { candidates.append(polygon) }
        }
        func area(_ p: GeoPolygon) -> Double { let r = p.boundingRegion; return r.latitudeDelta * r.longitudeDelta }
        let containing = point.map { p in candidates.filter { $0.contains(p) } } ?? []
        let pool = containing.isEmpty ? candidates : containing
        return pool.max(by: { area($0) < area($1) })
    }

    /// Joins open ways end to end into closed rings. A way that is already closed is a ring. Chains that never close are dropped.
    static func assembleRings(_ ways: [[Coordinate]]) -> [[Coordinate]] {
        var remaining = ways.filter { $0.count >= 2 }
        var rings: [[Coordinate]] = []
        while !remaining.isEmpty {
            var ring = remaining.removeFirst()
            while ring.first != ring.last {
                guard let tail = ring.last,
                      let index = remaining.firstIndex(where: { $0.first == tail || $0.last == tail }) else { break }
                var next = remaining.remove(at: index)
                if next.first != tail { next.reverse() }
                ring.append(contentsOf: next.dropFirst())
            }
            if ring.count >= 4, ring.first == ring.last { rings.append(ring) }
        }
        return rings
    }
}
