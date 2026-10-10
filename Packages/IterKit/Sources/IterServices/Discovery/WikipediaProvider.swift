import Foundation
import IterCore

/// Wikipedia articles with coordinates near the area (the geosearch API), kept when their title suggests the feature,
/// with a two-sentence extract as the snippet. Free, no key. An article counts as presence: `mentions` is 1.
public struct WikipediaProvider: DiscoveryProvider {
    public static let endpoint = "https://en.wikipedia.org/w/api.php"
    /// The API's largest search radius.
    public static let radiusMeters = 10_000
    /// Geosearch calls per request; a larger area is sampled on a grid of at most 3 x 3 points.
    public static let maximumGeosearchCalls = 9
    /// Extract calls per request (20 pages each, the API's limit for intro extracts).
    public static let maximumExtractCalls = 3

    public let id = DiscoverySourceID.wikipedia
    private let http: DiscoveryHTTP

    public init(http: DiscoveryHTTP) { self.http = http }

    public func discover(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        var hits: [WikipediaParser.Hit] = []
        var seenIDs = Set<Int>()
        var firstError: (any Error)?
        var succeeded = false
        for point in Self.samplePoints(for: area.region).prefix(Self.maximumGeosearchCalls) {
            try Task.checkCancellation()
            guard let url = DiscoveryHTTP.url(Self.endpoint, [
                ("action", "query"), ("list", "geosearch"), ("gscoord", "\(point.latitude)|\(point.longitude)"),
                ("gsradius", "\(Self.radiusMeters)"), ("gslimit", "50"), ("format", "json"), ("formatversion", "2"),
            ]) else { continue }
            do {
                let data = try await http.get(url, host: .wikipedia)
                succeeded = true
                for hit in try WikipediaParser.geosearch(data) where seenIDs.insert(hit.pageID).inserted { hits.append(hit) }
            } catch {
                if error is CancellationError { throw error }
                firstError = firstError ?? error
            }
        }
        if !succeeded, let firstError { throw firstError }

        let wanted = hits.filter { WikipediaParser.titleMatches($0.title, feature: feature) }
            .filter { area.region.contains($0.coordinate) || area.contains($0.coordinate) }
            .sorted { $0.distance < $1.distance }
        var snippets: [Int: WikipediaParser.Extract] = [:]
        for chunk in stride(from: 0, to: min(wanted.count, Self.maximumExtractCalls * 20), by: 20) {
            try Task.checkCancellation()
            let ids = wanted[chunk..<min(chunk + 20, wanted.count)].map { String($0.pageID) }.joined(separator: "|")
            guard let url = DiscoveryHTTP.url(Self.endpoint, [
                ("action", "query"), ("prop", "extracts|pageprops"), ("exintro", "1"), ("explaintext", "1"), ("exsentences", "2"),
                ("exlimit", "20"), ("ppprop", "wikibase_item"), ("pageids", ids), ("format", "json"), ("formatversion", "2"),
            ]) else { continue }
            // Extracts are a nicety: a failure here keeps the places, without snippets.
            if let data = try? await http.get(url, host: .wikipedia) {
                for extract in WikipediaParser.extracts(data) { snippets[extract.pageID] = extract }
            }
        }
        return wanted.map { hit in
            let extract = snippets[hit.pageID]
            let inferred = feature ?? WikipediaParser.inferFeature(from: hit.title)
            return DiscoveredPlace(
                name: WikipediaParser.cleanTitle(hit.title), coordinate: hit.coordinate,
                elevationMeters: inferred == .peak ? extract?.text.flatMap(ElevationParser.metres(inProse:)) : nil,
                feature: inferred, sources: [.wikipedia], snippet: extract?.text,
                links: WikipediaParser.articleURL(hit.title).map { [$0] } ?? [], mentions: 1)
        }
    }

    /// One point for an area that fits in a search circle; otherwise cell centres of up to a 3 x 3 grid.
    static func samplePoints(for region: GeoRegion) -> [Coordinate] {
        let kmPerDegree = 111.32
        let heightKm = region.latitudeDelta * kmPerDegree
        let widthKm = region.longitudeDelta * kmPerDegree * max(0.1, cos(region.center.latitude * .pi / 180))
        let cell = Double(radiusMeters) / 1000 * 2 / 2.0.squareRoot()   // the square that fits in the circle, about 14 km
        guard max(heightKm, widthKm) > cell else { return [region.center] }
        let rows = min(3, Int((heightKm / cell).rounded(.up))), columns = min(3, Int((widthKm / cell).rounded(.up)))
        var points: [Coordinate] = []
        for r in 0..<max(1, rows) {
            for c in 0..<max(1, columns) {
                let lat = region.center.latitude - region.latitudeDelta / 2 + region.latitudeDelta * (Double(r) + 0.5) / Double(max(1, rows))
                let lon = region.center.longitude - region.longitudeDelta / 2 + region.longitudeDelta * (Double(c) + 0.5) / Double(max(1, columns))
                points.append(Coordinate(latitude: lat, longitude: lon))
            }
        }
        return points
    }
}

enum WikipediaParser {
    struct Hit: Equatable { var pageID: Int; var title: String; var coordinate: Coordinate; var distance: Double }
    struct Extract: Equatable { var pageID: Int; var text: String? }

    static func geosearch(_ data: Data) throws -> [Hit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DiscoveryError.badResponse }
        if root["error"] != nil { throw DiscoveryError.badResponse }
        let list = ((root["query"] as? [String: Any])?["geosearch"] as? [[String: Any]]) ?? []
        return list.compactMap { item in
            guard let id = (item["pageid"] as? NSNumber)?.intValue, let title = item["title"] as? String,
                  let lat = (item["lat"] as? NSNumber)?.doubleValue, let lon = (item["lon"] as? NSNumber)?.doubleValue else { return nil }
            return Hit(pageID: id, title: title, coordinate: Coordinate(latitude: lat, longitude: lon),
                       distance: (item["dist"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    static func extracts(_ data: Data) -> [Extract] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (root["query"] as? [String: Any])?["pages"] as? [[String: Any]] else { return [] }
        return pages.compactMap { page in
            guard let id = (page["pageid"] as? NSNumber)?.intValue else { return nil }
            let text = (page["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Extract(pageID: id, text: (text?.isEmpty ?? true) ? nil : String(text!.prefix(400)))
        }
    }

    private static let scenicKeywords = ["mountain", "mount ", "mt ", "peak", "falls", "fall", "lake", "glacier", "canyon", "overlook", "viewpoint",
                                         "lookout", "vista", "beach", "bay", "cove", "arch", "bridge", "lighthouse", "cave", "pass", "valley",
                                         "ridge", "butte", "dome", "spire", "cliff", "gorge", "river", "creek", "geyser", "hot spring", "point"]

    static func titleMatches(_ title: String, feature: FeatureKind?) -> Bool {
        let lower = " " + title.lowercased()
        let keywords = feature?.titleKeywords ?? scenicKeywords
        return keywords.contains { lower.contains($0.hasSuffix(" ") || $0.hasSuffix(".") ? " " + $0 : $0) }
    }

    static func inferFeature(from title: String) -> FeatureKind? {
        let lower = " " + title.lowercased()
        return FeatureKind.allCases.first { kind in
            kind.titleKeywords.contains { lower.contains($0.hasSuffix(" ") || $0.hasSuffix(".") ? " " + $0 : $0) }
        }
    }

    /// "Hidden Lake (Flathead County, Montana)" -> "Hidden Lake"
    static func cleanTitle(_ title: String) -> String {
        guard let open = title.firstIndex(of: "(") else { return title }
        return title[..<open].trimmingCharacters(in: .whitespaces)
    }

    static func articleURL(_ title: String) -> URL? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }
}
