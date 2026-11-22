import Testing
import Foundation
import IterModel
import IterSources
@testable import IterSourcesLive

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let lonePine = Coordinate(latitude: 36.6061, longitude: -118.0628)
private func area() -> DiscoveryArea {
    DiscoveryArea(name: "Lone Pine", region: GeoRegion(center: lonePine, latitudeDelta: 0.5, longitudeDelta: 0.5))
}

private func stub(fullFor3: StubHTTPClient.Reply? = nil) throws -> StubHTTPClient {
    let http = StubHTTPClient()
    http.on(urlContaining: "list=geosearch", reply: .ok(try Fixtures.data("Wikimedia/wikivoyage-geosearch-hand.json")))
    http.on(urlContaining: "exlimit=1&pageids=900001&", reply: .ok(try Fixtures.data("Wikimedia/wikivoyage-extract-full-hand.json")))
    if let fullFor3 { http.on(urlContaining: "exlimit=1&pageids=900003&", reply: fullFor3) }
    http.on(urlContaining: "exlimit=1&pageids=", reply: .ok(Data(#"{"query":{"pages":{}}}"#.utf8)))
    http.on(urlContaining: "exintro=1", reply: .ok(try Fixtures.data("Wikimedia/wikivoyage-extracts-intro-hand.json")))
    return http
}

@Suite("Wikivoyage provider")
struct WikivoyageProviderTests {
    @Test func descriptorIsTheCatalogueOne() {
        let d = SourceCatalogue.wikivoyage
        #expect(d.id == .wikivoyage && d.id.rawValue == "wikivoyage.geosearch")
        #expect(d.kinds == [.textEvidence] && d.ranks[.textEvidence] == 20 && d.tier == .openData)
        #expect(d.licence.key == LicenceKey.wikivoyage && d.licence.mayStore)
        #expect(Attribution.text(for: LicenceKey.wikivoyage)?.short == "Text from Wikivoyage (CC BY-SA 4.0)")
        #expect(SourceCatalogue.descriptor(.wikivoyage) == d)
        #expect(WikivoyageProvider(http: StubHTTPClient()).descriptor == d)
        // Ranked after Wikipedia (rank 10), same politeness.
        #expect(d.policy == SourceCatalogue.wikipedia.policy && SourceCatalogue.wikipedia.ranks[.textEvidence] == 10)
    }

    @Test func requestsGoToWikivoyageNotWikipedia() async throws {
        let http = try stub()
        _ = try await WikivoyageProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(limit: 10), in: area())
        #expect(http.requests.allSatisfy { $0.url.host == "en.wikivoyage.org" && $0.source == .wikivoyage && $0.method == "GET" })
        #expect(http.requests[0].url.absoluteString == "https://en.wikivoyage.org/w/api.php?action=query&list=geosearch&gscoord=36.6061%7C-118.0628&gsradius=10000&gslimit=10&format=json")
    }

    @Test func introsInOneRequestThenWholeArticlesOfTheTopThreeOneEach() async throws {
        let http = try stub()
        _ = try await WikivoyageProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(limit: 10), in: area())
        let urls = http.requests.map(\.url.absoluteString)
        #expect(urls.count == 5)  // geosearch, one intro batch, three whole articles
        #expect(urls[1].contains("exintro=1") && urls[1].contains("exlimit=max") && urls[1].contains("pageids=900001%7C900002%7C900003%7C900004"))
        for (i, id) in [900001, 900002, 900003].enumerated() {
            #expect(urls[2 + i] == "https://en.wikivoyage.org/w/api.php?action=query&prop=extracts%7Ccoordinates&explaintext=1&exlimit=1&pageids=\(id)&format=json")
            #expect(!urls[2 + i].contains("exintro"))
        }
    }

    @Test func documentsCarryTheCondensedArticleAndAWikivoyageCitation() async throws {
        let http = try stub()
        let docs = try await WikivoyageProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(limit: 10), in: area())
        #expect(docs.map(\.title) == ["Lone Pine", "Alabama Hills", "Eastern Sierra", "Manzanar"])
        let lone = docs[0]
        #expect(lone.url?.absoluteString == "https://en.wikivoyage.org/?curid=900001")
        #expect(lone.citation.source == .wikivoyage && lone.citation.title == "Lone Pine" && lone.citation.retrievedAt == t0)
        #expect(lone.citation.licence?.key == LicenceKey.wikivoyage && lone.citation.url == lone.url)
        // The article is about 7,800 characters: cut to about 4,000, with See and Do kept.
        #expect(lone.text.count <= WikivoyageProvider.maxTextCharacters + 2 && lone.text.count > 2_500, "\(lone.text.count)")
        #expect(lone.text.contains("== See ==") && lone.text.contains("Mobius Arch") && lone.text.contains("== Do =="))
        #expect(lone.text.contains("Whitney Portal"))
        #expect(!lone.text.contains("== Sleep =="))
        let order = ["== Understand ==", "== See ==", "== Do =="].compactMap { lone.text.range(of: $0)?.lowerBound }
        #expect(order.count == 3 && order == order.sorted(), "the article's own order is kept")
        // Pages with no whole-article text keep their introduction; one without anything has its title.
        #expect(docs[1].text.hasPrefix("The Alabama Hills are a range"))
        #expect(docs[2].text.hasPrefix("The Eastern Sierra is the region"))
        #expect(docs[3].text == "Manzanar")
    }

    @Test func aFailedWholeArticleKeepsTheIntroduction() async throws {
        let http = try stub(fullFor3: .status(500, Data("oops".utf8)))
        let docs = try await WikivoyageProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(limit: 10), in: area())
        #expect(docs[2].text.hasPrefix("The Eastern Sierra is the region") && docs[0].text.contains("Mobius Arch"))
    }

    @Test func limitAndTermsApplyLikeWikipedia() async throws {
        let http = try stub()
        let docs = try await WikivoyageProvider(http: http, clock: ManualSourceClock(now: t0)).documents(for: TextQuery(terms: ["manzanar"], limit: 2), in: area())
        #expect(docs.map(\.title) == ["Manzanar", "Lone Pine"])
        // Only two documents are returned, so only those two pages get extracts.
        #expect(http.requests[1].url.absoluteString.contains("pageids=900004%7C900001"))
        #expect(http.requests.count == 1 + 1 + 2)
    }

    @Test func geosearchFailureThrowsAndZeroLimitMakesNoRequest() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "list=geosearch", reply: .error(.offline))
        await #expect(throws: SourceError.offline) { try await WikivoyageProvider(http: http).documents(for: TextQuery(), in: area()) }
        let none = try await WikivoyageProvider(http: http).documents(for: TextQuery(limit: 0), in: area())
        #expect(none.isEmpty && http.requests.count == 1)
    }

    @Test func wikipediaStillReadsIntrosOnly() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "list=geosearch", reply: .ok(try Fixtures.data("Wikimedia/wikipedia-geosearch-W.json")))
        http.on(urlContaining: "prop=extracts", reply: .ok(Data(#"{"query":{"pages":{}}}"#.utf8)))
        let docs = try await WikipediaProvider(http: http).documents(for: TextQuery(limit: 10), in: DiscoveryArea(name: nil, region: GeoRegion(center: Coordinate(latitude: 36.5785, longitude: -118.2923), latitudeDelta: 0.5, longitudeDelta: 0.5)))
        #expect(http.requests.count == 2 && http.requests.allSatisfy { $0.url.host == "en.wikipedia.org" })
        #expect(docs.allSatisfy { $0.url?.host == "en.wikipedia.org" && $0.citation.source == .wikipedia })
    }
}

@Suite("Wikivoyage text")
struct WikivoyageTextTests {
    @Test func shortTextIsUntouched() {
        #expect(WikivoyageText.condense("  A short guide.\n\n== See ==\nA hill.  ", limit: 4000) == "A short guide.\n\n== See ==\nA hill.")
    }

    @Test func seeAndDoComeFirstAndOrderIsKept() throws {
        let text = "Intro line.\n\n== Understand ==\n" + String(repeating: "u", count: 500) + "\n\n== See ==\nViewpoint A.\n=== Sub ===\nViewpoint B.\n\n== Do ==\nHike C.\n\n== Eat ==\n" + String(repeating: "e", count: 500)
        let out = WikivoyageText.condense(text, limit: 200)
        #expect(out.count <= 201)
        #expect(out.contains("Intro line.") && out.contains("Viewpoint A.") && out.contains("Viewpoint B.") && out.contains("Hike C."))
        #expect(!out.contains("== Eat ==") && !out.contains("eeee"))
        // Understand did not fit and there was too little room left to cut it.
        #expect(!out.contains("uuuu"))
        let a = try #require(out.range(of: "Intro"))
        let b = try #require(out.range(of: "== See =="))
        let c = try #require(out.range(of: "== Do =="))
        #expect(a.lowerBound < b.lowerBound && b.lowerBound < c.lowerBound)
    }

    @Test func leftoverRoomGoesToTheOtherSectionsCutAtASentence() {
        let text = "Intro.\n\n== Understand ==\n" + (0..<60).map { "Sentence number \($0) is here." }.joined(separator: " ") + "\n\n== See ==\nA place."
        let out = WikivoyageText.condense(text, limit: 600)
        #expect(out.count <= 601 && out.contains("…") && out.contains("== See ==") && out.contains("A place."))
        #expect(out.contains("Sentence number 3 is here."))
        // The cut falls after a full sentence.
        #expect(out.contains("here.…"))
    }

    @Test func headingsSplitOnlyAtTopLevel() {
        let sections = WikivoyageText.split("Intro\n== See ==\nx\n=== Museums ===\ny\n== Do ==\nz")
        #expect(sections.map(\.title) == ["", "see", "do"])
        #expect(sections[1].body.contains("=== Museums ===") && sections[1].body.contains("y"))
        #expect(WikivoyageText.topLevelTitle("== Get in ==") == "get in")
        #expect(WikivoyageText.topLevelTitle("=== Get in ===") == nil)
        #expect(WikivoyageText.topLevelTitle("a == b ==") == nil)
    }

    @Test func textWithoutHeadingsIsCutAtAParagraphOrSentence() {
        let text = (0..<100).map { "Sentence \($0)." }.joined(separator: " ")
        let out = WikivoyageText.condense(text, limit: 300)
        #expect(out.count <= 301 && out.hasSuffix(".…"))
        #expect(WikivoyageText.condense("anything", limit: 0) == "anything")
    }
}
