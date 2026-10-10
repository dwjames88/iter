import Foundation
import IterCore

/// The "See" listings of a Wikivoyage travel guide for the area. Free, no key. Each listing is a recommendation by a
/// travel writer, so `mentions` is 2. Listings without `lat` and `long` are returned without a coordinate and
/// validated by the engine.
public struct WikivoyageProvider: DiscoveryProvider {
    public static let endpoint = "https://en.wikivoyage.org/w/api.php"

    public let id = DiscoverySourceID.wikivoyage
    private let http: DiscoveryHTTP

    public init(http: DiscoveryHTTP) { self.http = http }

    public func discover(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        guard let name = area.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw DiscoveryError.notFound }
        let wikitext: String
        do {
            wikitext = try await page(named: name)
        } catch DiscoveryError.notFound {
            // "Glacier National Park" is a disambiguated title on Wikivoyage; ask search for the nearest page.
            guard let title = try await searchTitle(name) else { throw DiscoveryError.notFound }
            wikitext = try await page(named: title)
        }
        let listings = WikivoyageParser.seeListings(in: wikitext)
        return listings.compactMap { listing in
            if let feature, !WikivoyageParser.matches(listing, feature: feature) { return nil }
            let link = URL(string: "https://en.wikivoyage.org/wiki/" + (name.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))
            return DiscoveredPlace(name: listing.name, coordinate: listing.coordinate, feature: feature, sources: [.wikivoyage],
                                   snippet: listing.summary, links: link.map { [$0] } ?? [], mentions: 2)
        }
    }

    private func page(named title: String) async throws -> String {
        guard let url = DiscoveryHTTP.url(Self.endpoint, [("action", "parse"), ("page", title), ("prop", "wikitext"), ("redirects", "1"),
                                                           ("format", "json"), ("formatversion", "2")]) else { throw DiscoveryError.badResponse }
        let data = try await http.get(url, host: .wikivoyage)
        return try WikivoyageParser.wikitext(data)
    }

    private func searchTitle(_ name: String) async throws -> String? {
        guard let url = DiscoveryHTTP.url(Self.endpoint, [("action", "query"), ("list", "search"), ("srsearch", name), ("srlimit", "1"),
                                                           ("srnamespace", "0"), ("format", "json"), ("formatversion", "2")]) else { return nil }
        let data = try await http.get(url, host: .wikivoyage)
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hits = ((root?["query"] as? [String: Any])?["search"] as? [[String: Any]]) ?? []
        return hits.first?["title"] as? String
    }
}

enum WikivoyageParser {
    struct Listing: Equatable {
        var name: String
        var coordinate: Coordinate?
        var summary: String?
    }

    /// The `parse.wikitext` of a `action=parse` reply. A `missingtitle` error is `.notFound`.
    static func wikitext(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DiscoveryError.badResponse }
        if let error = root["error"] as? [String: Any] {
            throw (error["code"] as? String) == "missingtitle" ? DiscoveryError.notFound : DiscoveryError.badResponse
        }
        guard let text = (root["parse"] as? [String: Any])?["wikitext"] as? String else { throw DiscoveryError.badResponse }
        return text
    }

    /// The text of the level-2 "See" section (or all of the text if the page has none).
    static func seeSection(in wikitext: String) -> String {
        let lines = wikitext.components(separatedBy: "\n")
        var inSee = false, found = false
        var out: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=="), !trimmed.hasPrefix("===") {
                let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).lowercased()
                inSee = title == "see"
                if inSee { found = true }
                continue
            }
            if inSee { out.append(line) }
        }
        return found ? out.joined(separator: "\n") : wikitext
    }

    /// Every `{{see ...}}` or `{{listing|type=see ...}}` template in the See section.
    static func seeListings(in wikitext: String) -> [Listing] {
        let section = seeSection(in: wikitext)
        var listings: [Listing] = []
        for template in templates(in: section) {
            let kind = template.name.lowercased()
            let fields = template.fields
            guard kind == "see" || (kind == "listing" && fields["type"]?.lowercased() == "see") else { continue }
            guard let rawName = fields["name"] else { continue }
            let name = clean(rawName)
            guard !name.isEmpty else { continue }
            var coordinate: Coordinate?
            if let lat = fields["lat"].flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
               let lon = (fields["long"] ?? fields["lon"]).flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
               (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) {
                coordinate = Coordinate(latitude: lat, longitude: lon)
            }
            let summary = fields["content"].map(clean).flatMap { $0.isEmpty ? nil : firstSentences($0, limit: 300) }
            listings.append(Listing(name: name, coordinate: coordinate, summary: summary))
        }
        return listings
    }

    /// A listing suits a feature when its name says so ("Iceberg Lake", "Sperry Glacier"). The prose is not consulted:
    /// "Two Medicine Road" mentions lakes without being one.
    static func matches(_ listing: Listing, feature: FeatureKind) -> Bool {
        let name = " " + listing.name.lowercased()
        return (feature.titleKeywords + feature.synonyms).contains { name.contains($0.hasSuffix(" ") || $0.hasSuffix(".") ? " " + $0 : $0) }
    }

    // MARK: Template reading

    struct Template { var name: String; var fields: [String: String] }

    /// Top-level `{{...}}` templates, with nested braces and `[[links|text]]` pipes handled.
    static func templates(in text: String) -> [Template] {
        let chars = Array(text)
        var result: [Template] = []
        var i = 0
        while i < chars.count - 1 {
            guard chars[i] == "{", chars[i + 1] == "{" else { i += 1; continue }
            var depth = 0, j = i
            while j < chars.count - 1 {
                if chars[j] == "{", chars[j + 1] == "{" { depth += 1; j += 2; continue }
                if chars[j] == "}", chars[j + 1] == "}" { depth -= 1; j += 2; if depth == 0 { break }; continue }
                j += 1
            }
            guard depth == 0 else { break }
            let inner = String(chars[(i + 2)..<(j - 2)])
            result.append(parse(inner))
            i = j
        }
        return result
    }

    private static func parse(_ inner: String) -> Template {
        var parts: [String] = []
        var current = ""
        var braces = 0, brackets = 0
        let chars = Array(inner)
        var k = 0
        while k < chars.count {
            let c = chars[k]
            let next: Character? = k + 1 < chars.count ? chars[k + 1] : nil
            if c == "{", next == "{" { braces += 1; current += "{{"; k += 2; continue }
            if c == "}", next == "}" { braces -= 1; current += "}}"; k += 2; continue }
            if c == "[", next == "[" { brackets += 1; current += "[["; k += 2; continue }
            if c == "]", next == "]" { brackets -= 1; current += "]]"; k += 2; continue }
            if c == "|", braces == 0, brackets == 0 { parts.append(current); current = ""; k += 1; continue }
            current.append(c); k += 1
        }
        parts.append(current)
        var fields: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, fields[key] == nil { fields[key] = value }
        }
        return Template(name: parts[0].trimmingCharacters(in: .whitespacesAndNewlines), fields: fields)
    }

    /// Plain text from wikitext: links to their label, bold and italic marks, nested templates and tags removed.
    static func clean(_ wikitext: String) -> String {
        var s = wikitext
        s = s.replacingOccurrences(of: #"\{\{[^{}]*\}\}"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[https?://[^\s\]]+\s+([^\]]*)\]"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[https?://[^\s\]]+\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "'''", with: "").replacingOccurrences(of: "''", with: "")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func firstSentences(_ text: String, limit: Int) -> String {
        var out = ""
        for sentence in text.split(separator: ".", omittingEmptySubsequences: true) {
            let next = out + (out.isEmpty ? "" : " ") + sentence.trimmingCharacters(in: .whitespaces) + "."
            if next.count > limit { break }
            out = next
            if out.count >= limit / 2 { break }
        }
        return out.isEmpty ? String(text.prefix(limit)) : out
    }
}
