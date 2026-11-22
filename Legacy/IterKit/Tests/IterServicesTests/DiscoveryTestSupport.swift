import Foundation
import Synchronization
import IterCore
@testable import IterServices

/// Loads a fixture from `Fixtures/discovery/` (see its README for what is recorded and what is hand-built).
enum DiscoveryFixture {
    static func data(_ name: String) -> Data {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent("discovery").appendingPathComponent(name)
        return try! Data(contentsOf: url)
    }
    static func string(_ name: String) -> String { String(decoding: data(name), as: UTF8.self) }
}

/// An HTTP helper with no waiting between requests and a memory-only cache: nothing slow, nothing on disk.
func quietHTTP(_ transport: any HTTPTransport, cache: DiscoveryCache = DiscoveryCache(),
               intervals: [DiscoveryHost: TimeInterval] = Dictionary(uniqueKeysWithValues: DiscoveryHost.allCases.map { ($0, 0) })) -> DiscoveryHTTP {
    DiscoveryHTTP(transport: transport, cache: cache, limiter: DiscoveryRateLimiter(intervals: intervals), userAgent: DiscoveryHTTP.userAgent(version: "test"))
}

func queryText(_ request: URLRequest) -> String {
    (request.url?.query ?? "").removingPercentEncoding ?? ""
}

func formBody(_ request: URLRequest) -> String {
    (String(decoding: request.httpBody ?? Data(), as: UTF8.self)).removingPercentEncoding ?? ""
}

func place(_ name: String, _ lat: Double, _ lon: Double, locality: String = "") -> PlaceResult {
    PlaceResult(id: name + "\(lat)", name: name, locality: locality, coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: nil, pointOfInterestCategory: nil)
}

/// A place search that answers from a closure and records what it was asked.
final class ScriptedSearch: PlaceSearching {
    private let state = Mutex<[String]>([])
    private let reply: @Sendable (String) -> [PlaceResult]
    init(_ reply: @escaping @Sendable (String) -> [PlaceResult] = { _ in [] }) { self.reply = reply }
    var queries: [String] { state.withLock { $0 } }
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        state.withLock { $0.append(query) }
        return reply(query)
    }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

struct ScriptedGeocoder: Geocoding {
    var results: [PlaceResult]
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { results[0] }
    func geocode(_ query: String) async throws -> [PlaceResult] { results }
}

/// An extractor that "finds" a fixed list of names and then applies the same filter the live one does,
/// so only names that really occur in the texts survive.
struct ListExtractor: DiscoveryExtracting {
    var names: [String]
    func extractPlaces(from texts: [DiscoveryText], area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        DiscoveryExtractionFilter.apply(candidates: names.map { ($0, "Because the texts say so.") }, texts: texts, area: area, feature: feature, maximum: 12)
    }
}

struct FailingExtractor: DiscoveryExtracting {
    func extractPlaces(from texts: [DiscoveryText], area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        throw DiscoveryError.unavailable("Apple Intelligence unavailable")
    }
}

/// The wire for the Glacier and Yosemite scenarios: every host answers from a fixture, and every request is recorded.
enum Wire {
    static func make(reddit: @escaping @Sendable (URLRequest) throws -> (status: Int, body: Data) = { r in
                        r.url!.path.hasPrefix("/r/GlacierNationalPark") ? (404, Data("{}".utf8)) : (200, DiscoveryFixture.data("reddit-search-glacier.json")) },
                     yosemite: Bool = false) -> FakeTransport {
        FakeTransport { request in try route(request, yosemite: yosemite, reddit: reddit) }
    }

    /// The answer each host gives. Reachable directly so a test can wrap it and override one host.
    static func route(_ request: URLRequest, yosemite: Bool = false,
                      reddit: @Sendable (URLRequest) throws -> (status: Int, body: Data) = { r in
                          r.url!.path.hasPrefix("/r/GlacierNationalPark") ? (404, Data("{}".utf8)) : (200, DiscoveryFixture.data("reddit-search-glacier.json")) }) throws -> (status: Int, body: Data) {
        do {
            let url = request.url!
            switch url.host ?? "" {
            case "overpass-api.de":
                let body = formBody(request)
                if body.contains("relation[") { return (200, DiscoveryFixture.data("overpass-boundary-glacier.json")) }
                if body.contains("waterfall") { return (200, DiscoveryFixture.data("overpass-waterfalls-yosemite.json")) }
                return (200, DiscoveryFixture.data("overpass-peaks-glacier.json"))
            case "en.wikipedia.org":
                let q = queryText(request)
                if q.contains("list=geosearch") {
                    return (200, yosemite ? Data(#"{"batchcomplete":true,"query":{"geosearch":[]}}"#.utf8) : DiscoveryFixture.data("wikipedia-geosearch-glacier.json"))
                }
                return (200, DiscoveryFixture.data("wikipedia-extracts-glacier.json"))
            case "en.wikivoyage.org":
                let q = queryText(request)
                if q.contains("list=search") {
                    return (200, Data((yosemite ? #"{"query":{"search":[]}}"# : #"{"query":{"search":[{"title":"Glacier National Park (Montana)"}]}}"#).utf8))
                }
                if q.contains("page=Glacier National Park (Montana)") { return (200, DiscoveryFixture.data("wikivoyage-glacier-see.json")) }
                return (200, Data(#"{"error":{"code":"missingtitle","info":"The page you specified doesn't exist."}}"#.utf8))
            case "www.reddit.com":
                return try reddit(request)
            default:
                return (404, Data())
            }
        }
    }

    static func hosts(_ transport: FakeTransport) -> [String] { transport.requests.compactMap { $0.url?.host } }
}

let glacierRegionCentre = Coordinate(latitude: 48.7596, longitude: -113.787)
