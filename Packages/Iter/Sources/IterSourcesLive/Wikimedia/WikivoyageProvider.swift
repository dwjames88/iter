import Foundation
import IterModel
import IterSources

/// Wikivoyage (en.wikivoyage.org) travel-guide articles near an area, as text evidence. The same MediaWiki API as
/// `WikipediaProvider`: a geosearch, one batched introduction request, then the whole article of the three best pages.
/// Destination articles have "See" and "Do" sections that name viewpoints, trails and photo spots, so the text is the
/// article condensed to about 4,000 characters with those sections kept first (`WikivoyageText.condense`).
public struct WikivoyageProvider: TextEvidenceProvider {
    /// Longest document text, characters.
    public static let maxTextCharacters = WikipediaProvider.Site.wikivoyage.maxCharacters

    public let descriptor: SourceDescriptor
    private let inner: WikipediaProvider

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.wikivoyage) {
        self.descriptor = descriptor
        self.inner = WikipediaProvider(http: http, clock: clock, descriptor: descriptor, site: .wikivoyage)
    }

    public func documents(for query: TextQuery, in area: DiscoveryArea) async throws -> [EvidenceDocument] {
        try await inner.documents(for: query, in: area)
    }
}

/// Shortens a plain-text MediaWiki article (`explaintext`: headings as `== See ==`) to a character budget. Pure.
public enum WikivoyageText {
    /// Section titles kept first when the article is too long: what to see and do.
    static let priorityTitles: Set<String> = ["see", "do"]

    /// `text` itself when it fits in `limit` characters. Otherwise the introduction and the "See" and "Do" sections come
    /// first, then the other sections in order while there is room; the result keeps the article's order and ends at a
    /// paragraph or sentence break, with "…" marking the cut.
    public static func condense(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, trimmed.count > limit else { return trimmed }
        let sections = split(trimmed)
        var budget = limit
        var chosen = [String?](repeating: nil, count: sections.count)
        // The introduction, then See and Do, then the rest.
        let order = sections.indices.filter { sections[$0].title.isEmpty }
            + sections.indices.filter { priorityTitles.contains(sections[$0].title) }
            + sections.indices.filter { !sections[$0].title.isEmpty && !priorityTitles.contains(sections[$0].title) }
        for i in order {
            let body = sections[i].body
            guard budget > 0 else { break }
            if body.count + 2 <= budget {
                chosen[i] = body
                budget -= body.count + 2
            } else if budget >= 300 || sections[i].title.isEmpty {
                chosen[i] = cut(body, to: budget) + "…"
                budget = 0
            }
        }
        return chosen.compactMap { $0 }.joined(separator: "\n\n")
    }

    struct Section {
        /// Lower-cased heading of a top-level (`== X ==`) section; "" for the introduction.
        var title: String
        /// The heading line and everything up to the next top-level heading, subsections included.
        var body: String
    }

    /// Splits at top-level headings (`== Title ==`, not `=== Sub ===`).
    static func split(_ text: String) -> [Section] {
        var sections = [Section(title: "", body: "")]
        var lines: [String] = []
        func flush() {
            sections[sections.count - 1].body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let title = topLevelTitle(line) {
                flush()
                sections.append(Section(title: title, body: ""))
            }
            lines.append(line)
        }
        flush()
        return sections.filter { !$0.body.isEmpty }
    }

    static func topLevelTitle(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("=="), t.hasSuffix("=="), !t.hasPrefix("===") else { return nil }
        let title = t.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).lowercased()
        return title.isEmpty ? nil : title
    }

    /// At most `n` characters, ending at a paragraph break, else a sentence end, else a word break (when one is near).
    static func cut(_ s: String, to n: Int) -> String {
        guard s.count > n else { return s }
        let head = String(s.prefix(n))
        let floor = n * 3 / 4
        for marker in ["\n\n", "\n", ". ", " "] {
            if let r = head.range(of: marker, options: .backwards), head.distance(from: head.startIndex, to: r.lowerBound) >= floor {
                let end = marker == ". " ? head.index(after: r.lowerBound) : r.lowerBound
                return String(head[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
