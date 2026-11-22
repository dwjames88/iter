import Testing
import Foundation
import IterModel
import IterSources
@testable import IterSourcesLive

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
/// Wide enough that the radius clamps to the API maximum of 10 000 m, as in the recorded request.
private func wideArea(boundary: GeoPolygon? = nil) -> DiscoveryArea {
    DiscoveryArea(name: "Mount Whitney", region: GeoRegion(center: whitney, latitudeDelta: 0.5, longitudeDelta: 0.5), boundary: boundary)
}

/// SYNTHETIC: hand-written in the documented `prop=extracts` shape; no such response was recorded.
private let syntheticExtracts = """
{"batchcomplete":"","query":{"pages":{
 "238615":{"pageid":238615,"ns":0,"title":"Mount Whitney","extract":"Mount Whitney is the highest summit in the contiguous United States.\\n","coordinates":[{"lat":36.578581,"lon":-118.291995,"primary":""}]},
 "7587800":{"pageid":7587800,"ns":0,"title":"Whitney Classic","extract":""},
 "2976842":{"pageid":2976842,"ns":0,"title":"Mount Muir"}
}}}
"""

@Suite("Wikipedia mapping")
struct WikipediaMappingTests {
    let d = SourceCatalogue.wikipedia

    @Test func geosearchFixtureW() throws {
        let hits = try WikipediaMapping.hits(from: try Fixtures.data("Wikimedia/wikipedia-geosearch-W.json"))
        #expect(hits.count == 10)
        #expect(hits[0].title == "Smithsonian Institution Shelter" && hits[0].pageID == 20610201)
        #expect(hits[2].title == "Mount Whitney" && hits[2].pageID == 238615)
        #expect(hits[2].distanceM == 28.7)
        #expect(hits[2].coordinate == Coordinate(latitude: 36.578580925, longitude: -118.29199495))
    }

    @Test func geosearchFixtureS() throws {
        let hits = try WikipediaMapping.hits(from: try Fixtures.data("Wikimedia/wikipedia-geosearch-S.json"))
        #expect(hits.map(\.title).prefix(3) == ["Swiss Alps", "Gotthard Pass", "Lago di Lucendro"])
        #expect(hits.count == 10)
    }

    @Test func syntheticExtractsShape() throws {
        let e = try WikipediaMapping.extracts(from: Data(syntheticExtracts.utf8))
        #expect(e == [238615: "Mount Whitney is the highest summit in the contiguous United States."])
        let v2 = #"{"query":{"pages":[{"pageid":5,"title":"A","extract":"Text"}]}}"#
        #expect(try WikipediaMapping.extracts(from: Data(v2.utf8)) == [5: "Text"])
    }

    @Test func apiErrorBodyThrows() {
        #expect(throws: SourceError.self) { try WikipediaMapping.hits(from: Data(#"{"error":{"code":"badvalue","info":"x"}}"#.utf8)) }
        #expect(throws: SourceError.self) { try WikipediaMapping.hits(from: Data("nope".utf8)) }
    }

    @Test func documentsCarryCitationAndTitleFallback() throws {
        let hits = try WikipediaMapping.hits(from: try Fixtures.data("Wikimedia/wikipedia-geosearch-W.json"))
        let extracts = try WikipediaMapping.extracts(from: Data(syntheticExtracts.utf8))
        let docs = WikipediaMapping.documents(hits: hits, extracts: extracts, area: wideArea(), terms: [], limit: 20, descriptor: d, retrievedAt: t0)
        #expect(docs.count == 10)
        let mw = try #require(docs.first { $0.title == "Mount Whitney" })
        #expect(mw.text.hasPrefix("Mount Whitney is the highest summit"))
        #expect(mw.url?.absoluteString == "https://en.wikipedia.org/?curid=238615")
        #expect(mw.citation.source == .wikipedia && mw.citation.title == "Mount Whitney" && mw.citation.retrievedAt == t0)
        #expect(mw.citation.licence?.key == LicenceKey.wikipedia)
        #expect(mw.citation.url == mw.url)
        let muir = try #require(docs.first { $0.title == "Mount Muir" })
        #expect(muir.text == "Mount Muir")
    }

    @Test func termsRankFirstWithoutDroppingOthers() throws {
        let hits = try WikipediaMapping.hits(from: try Fixtures.data("Wikimedia/wikipedia-geosearch-W.json"))
        let docs = WikipediaMapping.documents(hits: hits, extracts: [:], area: wideArea(), terms: ["muir", "Classic"], limit: 20, descriptor: d, retrievedAt: t0)
        #expect(docs.count == 10)
        #expect(docs.prefix(2).map(\.title) == ["Whitney Classic", "Mount Muir"])
        #expect(docs[2].title == "Smithsonian Institution Shelter")
    }

    @Test func boundaryFiltersAndLimitCaps() throws {
        let ring = [(36.5780, -118.2925), (36.5780, -118.2915), (36.5790, -118.2915), (36.5790, -118.2925)].map { Coordinate(latitude: $0.0, longitude: $0.1) }
        let hits = try WikipediaMapping.hits(from: try Fixtures.data("Wikimedia/wikipedia-geosearch-W.json"))
        let docs = WikipediaMapping.documents(hits: hits, extracts: [:], area: wideArea(boundary: GeoPolygon(rings: [ring])), terms: [], limit: 20, descriptor: d, retrievedAt: t0)
        #expect(docs.count == 6)
        #expect(!docs.contains { $0.title == "Mount Muir" })
        #expect(WikipediaMapping.documents(hits: hits, extracts: [:], area: wideArea(), terms: [], limit: 3, descriptor: d, retrievedAt: t0).count == 3)
    }
}

@Suite("Wikipedia provider")
struct WikipediaProviderTests {
    let geosearchURL = "https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=36.5785%7C-118.2923&gsradius=10000&gslimit=10&format=json"

    func stub(extractsReply: StubHTTPClient.Reply) throws -> StubHTTPClient {
        let http = StubHTTPClient()
        http.on(urlContaining: "list=geosearch", reply: .ok(try Fixtures.data("Wikimedia/wikipedia-geosearch-W.json")))
        http.on(urlContaining: "prop=extracts", reply: extractsReply)
        return http
    }

    @Test func geosearchRequestMatchesTheRecordedForm() async throws {
        let http = try stub(extractsReply: .ok(Data(syntheticExtracts.utf8)))
        _ = try await WikipediaProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(limit: 10), in: wideArea())
        #expect(http.requests[0].url.absoluteString == geosearchURL)
        #expect(http.requests[0].method == "GET")
    }

    @Test func followUpRequestAsksForIntroExtractsOfTheReturnedPages() async throws {
        let http = try stub(extractsReply: .ok(Data(syntheticExtracts.utf8)))
        let docs = try await WikipediaProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(terms: ["whitney"], limit: 10), in: wideArea())
        #expect(http.requests.count == 2)
        let second = http.requests[1].url.absoluteString
        #expect(second.hasPrefix("https://en.wikipedia.org/w/api.php?action=query&prop=extracts%7Ccoordinates&exintro=1&explaintext=1&exlimit=max&pageids="))
        #expect(second.contains("238615") && second.contains("%7C") && second.hasSuffix("&format=json"))
        #expect(docs.count == 10)
        // Titles with "whitney" first, in API order.
        #expect(docs.prefix(2).map(\.title) == ["Whitney Classic", "Mount Whitney"])
        #expect(docs.first { $0.title == "Mount Whitney" }?.text.hasPrefix("Mount Whitney is the highest") == true)
        #expect(docs.first { $0.title == "Whitney Classic" }?.text == "Whitney Classic")
    }

    @Test func failedExtractRequestFallsBackToTitles() async throws {
        let http = try stub(extractsReply: .status(500, Data("oops".utf8)))
        let docs = try await WikipediaProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(limit: 10), in: wideArea())
        #expect(docs.count == 10)
        #expect(docs.allSatisfy { $0.text == $0.title })
    }

    @Test func geosearchFailureThrows() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "list=geosearch", reply: .error(.offline))
        await #expect(throws: SourceError.offline) {
            try await WikipediaProvider(http: http).documents(for: TextQuery(), in: wideArea())
        }
    }

    @Test func radiusFollowsTheAreaAndNeverExceedsTheApiMax() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "list=geosearch", reply: .ok(Data(#"{"query":{"geosearch":[]}}"#.utf8)))
        let small = DiscoveryArea(name: nil, region: GeoRegion(center: whitney, latitudeDelta: 0.02, longitudeDelta: 0.02))
        let docs = try await WikipediaProvider(http: http).documents(for: TextQuery(limit: 5), in: small)
        #expect(docs.isEmpty)
        #expect(http.requests.count == 1)  // nothing found: no follow-up request
        #expect(http.requests[0].url.absoluteString.contains("gsradius=1113&gslimit=5"))
        #expect(WikimediaAPI.clampRadius(1_000_000) == 10_000)
    }
}
