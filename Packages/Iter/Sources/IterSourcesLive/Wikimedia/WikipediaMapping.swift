import Foundation
import IterModel
import IterSources

/// Wikipedia geosearch and extract responses into evidence documents. Pure.
public enum WikipediaMapping {
    public struct Hit: Hashable, Sendable {
        public var pageID: Int
        public var title: String
        public var coordinate: Coordinate?
        public var distanceM: Double?
    }

    /// `list=geosearch` results, nearest first (the API's order).
    public static func hits(from data: Data) throws -> [Hit] {
        let object = try jsonObject(data)
        if let err = WikimediaAPI.errorText(in: object) { throw SourceError.http(status: 200, excerpt: "wikipedia: \(err)") }
        guard let query = object["query"] as? [String: Any], let rows = query["geosearch"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = (row["pageid"] as? NSNumber)?.intValue, let title = row["title"] as? String else { return nil }
            var c: Coordinate?
            if let lat = (row["lat"] as? NSNumber)?.doubleValue, let lon = (row["lon"] as? NSNumber)?.doubleValue {
                c = Coordinate(latitude: lat, longitude: lon)
            }
            return Hit(pageID: id, title: title, coordinate: c, distanceM: (row["dist"] as? NSNumber)?.doubleValue)
        }
    }

    /// `prop=extracts` results as page id to plain text. Pages without an extract are left out. Tolerates both the
    /// default `query.pages` object keyed by page id and the `formatversion=2` array shape.
    public static func extracts(from data: Data) throws -> [Int: String] {
        let object = try jsonObject(data)
        if let err = WikimediaAPI.errorText(in: object) { throw SourceError.http(status: 200, excerpt: "wikipedia: \(err)") }
        guard let query = object["query"] as? [String: Any] else { return [:] }
        var pages: [[String: Any]] = []
        if let dict = query["pages"] as? [String: Any] { pages = dict.values.compactMap { $0 as? [String: Any] } }
        else if let list = query["pages"] as? [[String: Any]] { pages = list }
        var out: [Int: String] = [:]
        for page in pages {
            guard let id = (page["pageid"] as? NSNumber)?.intValue, let text = page["extract"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out[id] = trimmed }
        }
        return out
    }

    /// Documents for `hits`: inside the area, titles containing a term first (otherwise API order), capped to `limit`.
    /// A hit without an extract gets its title as text.
    public static func documents(hits: [Hit], extracts: [Int: String], area: DiscoveryArea, terms: [String], limit: Int,
                                 descriptor: SourceDescriptor, retrievedAt: Date,
                                 articleBase: String = "https://en.wikipedia.org/?curid=") -> [EvidenceDocument] {
        let needles = terms.map { $0.lowercased() }.filter { !$0.isEmpty }
        let inside = hits.filter { hit in hit.coordinate.map(area.contains) ?? true }
        let matching = inside.filter { h in needles.contains { h.title.lowercased().contains($0) } }
        let rest = inside.filter { h in !needles.contains { h.title.lowercased().contains($0) } }
        return (matching + rest).prefix(max(0, limit)).map { hit in
            let url = URL(string: "\(articleBase)\(hit.pageID)")
            return EvidenceDocument(
                title: hit.title, text: extracts[hit.pageID] ?? hit.title, url: url, coordinate: hit.coordinate,
                citation: Citation(source: descriptor.id, url: url, title: hit.title, retrievedAt: retrievedAt,
                                   licence: descriptor.licence))
        }
    }

    static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SourceError.decoding("wikimedia: not a JSON object")
        }
        return o
    }
}
