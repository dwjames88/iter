import Foundation
import IterModel
import IterSources

/// English Wikipedia articles near an area, with their introductions as extract text. The same MediaWiki API serves
/// other wikis (`Site`): `WikivoyageProvider` runs this type against en.wikivoyage.org.
///
/// Two requests: a geosearch around the area centre, then one `prop=extracts|coordinates` request for the first 20
/// pages (the API's cap for intro extracts). When the second request fails the documents carry their titles as text.
/// A site with `fullTextPages > 0` then fetches the whole article of that many top-ranked pages, one request each (the
/// API returns whole-article extracts for one page at a time), and condenses it to `maxCharacters`.
public struct WikipediaProvider: TextEvidenceProvider {
    /// A MediaWiki site this provider can read.
    struct Site: Sendable, Hashable {
        var apiBase: String
        /// Where a document's link goes: this plus the page id.
        var articleBase: String
        /// Top-ranked pages whose whole article replaces the introduction (0 = introductions only).
        var fullTextPages: Int
        /// Longest text of a whole-article extract, characters.
        var maxCharacters: Int

        static let wikipedia = Site(apiBase: "https://en.wikipedia.org/w/api.php", articleBase: "https://en.wikipedia.org/?curid=",
                                    fullTextPages: 0, maxCharacters: 0)
        static let wikivoyage = Site(apiBase: "https://en.wikivoyage.org/w/api.php", articleBase: "https://en.wikivoyage.org/?curid=",
                                     fullTextPages: 3, maxCharacters: 4_000)
    }

    /// `exintro` extracts are limited to 20 pages per request.
    static let extractPageCap = 20
    static let apiBase = Site.wikipedia.apiBase

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock
    private let site: Site

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.wikipedia) {
        self.init(http: http, clock: clock, descriptor: descriptor, site: .wikipedia)
    }

    init(http: any HTTPClient, clock: any SourceClock, descriptor: SourceDescriptor, site: Site) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
        self.site = site
    }

    static func geosearchURL(center: Coordinate, radiusM: Int, limit: Int, site: Site = .wikipedia) -> URL {
        URL(string: site.apiBase + "?action=query&list=geosearch&gscoord=\(WikimediaAPI.coordParam(center))&gsradius=\(radiusM)&gslimit=\(limit)&format=json")!
    }

    static func extractsURL(pageIDs: [Int], site: Site = .wikipedia) -> URL {
        let ids = pageIDs.map(String.init).joined(separator: "%7C")
        return URL(string: site.apiBase + "?action=query&prop=extracts%7Ccoordinates&exintro=1&explaintext=1&exlimit=max&pageids=\(ids)&format=json")!
    }

    /// The whole article of one page as plain text (no `exintro`; the API allows one such page per request).
    static func fullExtractURL(pageID: Int, site: Site) -> URL {
        URL(string: site.apiBase + "?action=query&prop=extracts%7Ccoordinates&explaintext=1&exlimit=1&pageids=\(pageID)&format=json")!
    }

    public func documents(for query: TextQuery, in area: DiscoveryArea) async throws -> [EvidenceDocument] {
        guard query.limit > 0 else { return [] }
        let radius = WikimediaAPI.clampRadius(WikimediaAPI.radius(of: area))
        // Ask for more than wanted when a boundary will cut some away.
        let hasBoundary = !(area.boundary?.isEmpty ?? true)
        let limit = min(500, max(1, query.limit * (hasBoundary ? 3 : 1)))
        let url = Self.geosearchURL(center: area.region.center, radiusM: radius, limit: limit, site: site)
        let hits: [WikipediaMapping.Hit]
        do {
            let response = try await http.send(.get(url, from: descriptor))
            hits = try WikipediaMapping.hits(from: response.body)
        } catch { throw SourceError.wrap(error) }

        // Rank first so the 20 pages that get extracts are the ones that will be returned.
        let ranked = WikipediaMapping.documents(hits: hits, extracts: [:], area: area, terms: query.terms,
                                                limit: query.limit, descriptor: descriptor, retrievedAt: clock.now,
                                                articleBase: site.articleBase)
        var extracts: [Int: String] = [:]
        let wanted = ranked.compactMap { doc in hits.first { $0.title == doc.title }?.pageID }.prefix(Self.extractPageCap)
        if !wanted.isEmpty {
            do {
                let response = try await http.send(.get(Self.extractsURL(pageIDs: Array(wanted), site: site), from: descriptor))
                extracts = try WikipediaMapping.extracts(from: response.body)
            } catch {
                if SourceError.wrap(error) == .cancelled { throw SourceError.cancelled }
                extracts = [:]
            }
        }
        // Whole articles for the top pages: Wikivoyage's See and Do sections name the places worth a photo.
        for id in wanted.prefix(site.fullTextPages) {
            do {
                let response = try await http.send(.get(Self.fullExtractURL(pageID: id, site: site), from: descriptor))
                if let full = try WikipediaMapping.extracts(from: response.body)[id] {
                    extracts[id] = WikivoyageText.condense(full, limit: site.maxCharacters)
                }
            } catch {
                if SourceError.wrap(error) == .cancelled { throw SourceError.cancelled }
            }
        }
        return WikipediaMapping.documents(hits: hits, extracts: extracts, area: area, terms: query.terms,
                                          limit: query.limit, descriptor: descriptor, retrievedAt: clock.now,
                                          articleBase: site.articleBase)
    }
}
