import Foundation
import IterModel
import IterSources

/// English Wikipedia articles near an area, with their introductions as extract text.
///
/// Two requests: a geosearch around the area centre, then one `prop=extracts|coordinates` request for the first 20
/// pages (the API's cap for intro extracts). When the second request fails the documents carry their titles as text.
public struct WikipediaProvider: TextEvidenceProvider {
    /// `exintro` extracts are limited to 20 pages per request.
    static let extractPageCap = 20
    static let apiBase = "https://en.wikipedia.org/w/api.php"

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.wikipedia) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    static func geosearchURL(center: Coordinate, radiusM: Int, limit: Int) -> URL {
        URL(string: apiBase + "?action=query&list=geosearch&gscoord=\(WikimediaAPI.coordParam(center))&gsradius=\(radiusM)&gslimit=\(limit)&format=json")!
    }

    static func extractsURL(pageIDs: [Int]) -> URL {
        let ids = pageIDs.map(String.init).joined(separator: "%7C")
        return URL(string: apiBase + "?action=query&prop=extracts%7Ccoordinates&exintro=1&explaintext=1&exlimit=max&pageids=\(ids)&format=json")!
    }

    public func documents(for query: TextQuery, in area: DiscoveryArea) async throws -> [EvidenceDocument] {
        guard query.limit > 0 else { return [] }
        let radius = WikimediaAPI.clampRadius(WikimediaAPI.radius(of: area))
        // Ask for more than wanted when a boundary will cut some away.
        let hasBoundary = !(area.boundary?.isEmpty ?? true)
        let limit = min(500, max(1, query.limit * (hasBoundary ? 3 : 1)))
        let url = Self.geosearchURL(center: area.region.center, radiusM: radius, limit: limit)
        let hits: [WikipediaMapping.Hit]
        do {
            let response = try await http.send(.get(url, from: descriptor))
            hits = try WikipediaMapping.hits(from: response.body)
        } catch { throw SourceError.wrap(error) }

        // Rank first so the 20 pages that get extracts are the ones that will be returned.
        let ranked = WikipediaMapping.documents(hits: hits, extracts: [:], area: area, terms: query.terms,
                                                limit: query.limit, descriptor: descriptor, retrievedAt: clock.now)
        var extracts: [Int: String] = [:]
        let wanted = ranked.compactMap { doc in hits.first { $0.title == doc.title }?.pageID }.prefix(Self.extractPageCap)
        if !wanted.isEmpty {
            do {
                let response = try await http.send(.get(Self.extractsURL(pageIDs: Array(wanted)), from: descriptor))
                extracts = try WikipediaMapping.extracts(from: response.body)
            } catch {
                if SourceError.wrap(error) == .cancelled { throw SourceError.cancelled }
                extracts = [:]
            }
        }
        return WikipediaMapping.documents(hits: hits, extracts: extracts, area: area, terms: query.terms,
                                          limit: query.limit, descriptor: descriptor, retrievedAt: clock.now)
    }
}
