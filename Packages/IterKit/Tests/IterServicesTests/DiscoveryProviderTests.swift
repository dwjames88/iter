import Foundation
import Testing
import IterCore
@testable import IterServices

// MARK: HTTP helper

@Suite struct DiscoveryHTTPTests {
    @Test func userAgentIsHonestAndAnonymous() {
        #expect(DiscoveryHTTP.userAgent(version: "1.2") == "Iter/1.2 (photography trip planner; https://github.com/dwjames88)")
        #expect(DiscoveryHTTP.userAgent(version: nil).hasPrefix("Iter/dev "))
        #expect(!DiscoveryHTTP.userAgent(version: "1").contains("@"))
    }

    @Test func sendsUserAgentAndCachesWithinTheTimeToLive() async throws {
        let transport = FakeTransport { _ in (200, Data("{}".utf8)) }
        let clock = TestClock()
        let http = quietHTTP(transport, cache: DiscoveryCache(now: { clock.now }))
        let url = URL(string: "https://www.reddit.com/search.json?q=a")!
        _ = try await http.get(url, host: .reddit)
        _ = try await http.get(url, host: .reddit)
        #expect(transport.callCount == 1)
        #expect(transport.requests[0].value(forHTTPHeaderField: "User-Agent") == DiscoveryHTTP.userAgent(version: "test"))
        #expect(transport.requests[0].timeoutInterval == 10)
        clock.advance(5 * 3600)       // Reddit is good for 6 hours
        _ = try await http.get(url, host: .reddit)
        #expect(transport.callCount == 1)
        clock.advance(2 * 3600)
        _ = try await http.get(url, host: .reddit)
        #expect(transport.callCount == 2)
        // Wikipedia is good for a week.
        let wiki = URL(string: "https://en.wikipedia.org/w/api.php?x=1")!
        _ = try await http.get(wiki, host: .wikipedia)
        clock.advance(6 * 86_400)
        _ = try await http.get(wiki, host: .wikipedia)
        #expect(transport.callCount == 3)
        clock.advance(2 * 86_400)
        _ = try await http.get(wiki, host: .wikipedia)
        #expect(transport.callCount == 4)
    }

    @Test func diskCacheSurvivesANewInstance() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport { _ in (200, Data(#"{"ok":1}"#.utf8)) }
        let url = URL(string: "https://en.wikipedia.org/w/api.php?disk=1")!
        _ = try await quietHTTP(transport, cache: DiscoveryCache(directory: directory)).get(url, host: .wikipedia)
        let again = try await quietHTTP(transport, cache: DiscoveryCache(directory: directory)).get(url, host: .wikipedia)
        #expect(transport.callCount == 1)
        #expect(String(decoding: again, as: UTF8.self) == #"{"ok":1}"#)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1 && files[0].hasSuffix(".cache") && !files[0].contains("wikipedia"))
    }

    @Test func statusCodesBecomeShortReasons() async {
        for (status, expected) in [(429, DiscoveryError.rateLimited), (403, .rateLimited), (404, .notFound), (503, .busy), (500, .http(500))] {
            let http = quietHTTP(FakeTransport { _ in (status, Data()) })
            do { _ = try await http.get(URL(string: "https://www.reddit.com/x")!, host: .reddit); Issue.record("no error for \(status)") }
            catch { #expect(error as? DiscoveryError == expected) }
        }
        #expect(DiscoveryError.rateLimited.reason == "Rate limited")
        #expect(DiscoveryError.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(DiscoveryError.map(URLError(.timedOut)) == .timedOut)
    }

    @Test func postEncodesTheFormAndSkipsCachingBadBodies() async throws {
        let transport = FakeTransport { _ in (200, Data("<html>busy</html>".utf8)) }
        let http = quietHTTP(transport)
        let url = URL(string: OverpassProvider.endpoint)!
        _ = try await http.post(url, form: ["data": "[out:json];node[\"a\"=\"b c\"];out;"], host: .overpass, isCacheable: OverpassParser.looksLikeJSON)
        _ = try await http.post(url, form: ["data": "[out:json];node[\"a\"=\"b c\"];out;"], host: .overpass, isCacheable: OverpassParser.looksLikeJSON)
        #expect(transport.callCount == 2)        // the HTML page was not cached
        let sent = String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(sent.hasPrefix("data=%5Bout%3Ajson%5D"))
        #expect(!sent.contains(" "))
        #expect(transport.requests[0].httpMethod == "POST")
    }

    @Test func limiterSpacesRequestsAndSerialisesPerHost() async throws {
        let limiter = DiscoveryRateLimiter(intervals: [.reddit: 0.12])
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<3 { try await limiter.acquire(.reddit); await limiter.release(.reddit) }
        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(230))

        // Overpass allows one at a time: the second caller waits for the first to release.
        let quiet = DiscoveryRateLimiter(intervals: [.overpass: 0])
        try await quiet.acquire(.overpass)
        let second = Task { try await quiet.acquire(.overpass); return clock.now }
        try await Task.sleep(for: .milliseconds(80))
        let released = clock.now
        await quiet.release(.overpass)
        let acquiredAt = try await second.value
        #expect(acquiredAt >= released)
        await quiet.release(.overpass)
    }

    @Test func hostPolicy() {
        #expect(DiscoveryHost.reddit.minimumInterval >= 2)
        #expect(DiscoveryHost.overpass.minimumInterval >= 1 && DiscoveryHost.overpass.maximumConcurrent == 1)
        #expect(DiscoveryHost.wikipedia.minimumInterval >= 0.2)
        #expect(DiscoveryHost.reddit.timeToLive == 6 * 3600)
        #expect(DiscoveryHost.overpass.timeToLive == 7 * 86_400 && DiscoveryHost.wikivoyage.timeToLive == 7 * 86_400)
    }
}

// MARK: Overpass

@Suite struct OverpassTests {
    @Test func parsesGlacierPeaks() throws {
        let places = try OverpassParser.places(from: DiscoveryFixture.data("overpass-peaks-glacier.json"), defaultFeature: .peak)
        func find(_ n: String) -> DiscoveredPlace? { places.first { $0.name == n } }
        let cleveland = try #require(find("Mount Cleveland"))
        #expect(cleveland.elevationMeters == 3190)
        #expect(cleveland.coordinate == Coordinate(latitude: 48.925, longitude: -113.8480556))
        #expect(cleveland.sources == [.openStreetMap] && cleveland.feature == .peak)
        #expect(cleveland.links.map(\.absoluteString).contains("https://en.wikipedia.org/wiki/Mount_Cleveland_(Montana)"))
        #expect(cleveland.links.map(\.absoluteString).contains("https://www.wikidata.org/wiki/Q3321762"))
        #expect(find("Mount Jackson")?.elevationMeters == 3064)
        #expect(find("Going-to-the-Sun Mountain")?.elevationMeters == 2939)
        #expect(find("Reynolds Mountain")?.elevationMeters == 2666)
        let feet = try #require(find("Fixture Ridge (synthetic ele test)"))
        #expect(abs((feet.elevationMeters ?? 0) - 3190.1) < 0.1)
    }

    @Test func parsesWaterfallsAndWayCentres() throws {
        let falls = try OverpassParser.places(from: DiscoveryFixture.data("overpass-waterfalls-yosemite.json"), defaultFeature: .waterfall)
        let names = Set(falls.map(\.name))
        #expect(["Upper Yosemite Fall", "Lower Yosemite Fall", "Bridalveil Fall", "Vernal Fall", "Nevada Fall"].allSatisfy(names.contains))
        #expect(falls.first { $0.name == "Illilouette Fall" }?.elevationMeters == nil)
        #expect(falls.first { $0.name == "Vernal Fall" }?.elevationMeters == 1538)

        let json = #"""
        {"elements":[
          {"type":"way","id":1,"center":{"lat":37.5,"lon":-119.5},"tags":{"name":"Way Falls","waterway":"waterfall","ele":"1,200 m"}},
          {"type":"relation","id":2,"center":{"lat":37.6,"lon":-119.6},"tags":{"name":"Relation Lake","natural":"water","water":"lake"}},
          {"type":"node","id":3,"lat":37.7,"lon":-119.7,"tags":{"waterway":"waterfall"}},
          {"type":"way","id":4,"tags":{"name":"No Centre"}}
        ]}
        """#
        let parsed = try OverpassParser.places(from: Data(json.utf8), defaultFeature: nil)
        #expect(parsed.map(\.name) == ["Way Falls", "Relation Lake"])
        #expect(parsed[0].coordinate == Coordinate(latitude: 37.5, longitude: -119.5))
        #expect(parsed[0].elevationMeters == 1200 && parsed[0].feature == .waterfall)
        #expect(parsed[1].feature == .lake)
    }

    @Test func busyServerHTMLIsAnErrorNotAnEmptyAnswer() {
        let html = Data("<?xml version=\"1.0\"?><html><body><p>The server is probably too busy to handle your request.</p></body></html>".utf8)
        #expect(throws: DiscoveryError.busy) { try OverpassParser.places(from: html, defaultFeature: nil) }
        #expect(throws: DiscoveryError.badResponse) { try OverpassParser.places(from: Data("hello".utf8), defaultFeature: nil) }
    }

    @Test func buildsTheQuery() {
        let region = GeoRegion(center: Coordinate(latitude: 48.6, longitude: -113.85), latitudeDelta: 0.8, longitudeDelta: 1.3)
        let q = OverpassProvider.query(region: region, feature: .peak)
        #expect(q.contains("[out:json][timeout:20]"))
        #expect(q.contains("nwr[\"natural\"~\"^(peak|volcano)$\"][\"name\"](48.20000,-114.50000,49.00000,-113.20000)"))
        #expect(q.contains("out center tags 400;"))
        let any = OverpassProvider.query(region: region, feature: nil)
        for tag in ["tourism", "waterway", "natural"] { #expect(any.contains("[\"\(tag)\"")) }
        #expect(any.components(separatedBy: "out center tags 100;").count == 5)
    }

    @Test func providerPostsOnceAndCaches() async throws {
        let transport = Wire.make()
        let provider = OverpassProvider(http: quietHTTP(transport))
        let area = DiscoveryArea(name: "Glacier National Park", region: GeoRegion(center: Coordinate(latitude: 48.6, longitude: -113.85), latitudeDelta: 0.8, longitudeDelta: 1.3))
        let a = try await provider.discover(in: area, feature: .peak, text: nil, settings: DiscoverySettings())
        let b = try await provider.discover(in: area, feature: .peak, text: nil, settings: DiscoverySettings())
        #expect(a == b && !a.isEmpty)
        #expect(transport.callCount == 1)
        #expect(transport.requests[0].httpMethod == "POST")
        #expect(transport.requests[0].url?.host == "overpass-api.de")
    }

    // MARK: Boundary

    @Test func boundaryFromFixtureContainsParkAndExcludesNeighbours() throws {
        let polygon = try #require(OverpassBoundary.polygon(from: DiscoveryFixture.data("overpass-boundary-glacier.json"), near: glacierRegionCentre))
        #expect(polygon.rings.count == 1)
        #expect(polygon.rings[0].first == polygon.rings[0].last)
        for inside in [(48.925, -113.848), (48.6908, -113.6365), (48.6005, -113.7221), (48.6719, -113.7234)] {
            #expect(polygon.contains(Coordinate(latitude: inside.0, longitude: inside.1)))
        }
        for outside in [(48.2622, -114.4671), (48.5064, -114.3482), (48.5275, -113.3051), (48.4608, -113.2704), (49.5, -113.8), (47.0, -113.8)] {
            #expect(!polygon.contains(Coordinate(latitude: outside.0, longitude: outside.1)))
        }
        let box = polygon.boundingRegion
        #expect(abs(box.center.latitude - 48.6) < 0.2 && box.longitudeDelta > 0.8)
    }

    @Test func ringAssemblyJoinsReversedWaysAndDropsOpenChains() {
        func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }
        let top = [c(0, 0), c(0, 5), c(0, 10)]
        let right = [c(10, 10), c(5, 10), c(0, 10)]       // runs the other way
        let bottom = [c(10, 10), c(10, 5), c(10, 0)]
        let left = [c(10, 0), c(5, 0), c(0, 0)]
        let rings = OverpassBoundary.assembleRings([top, right, bottom, left])
        #expect(rings.count == 1 && rings[0].first == rings[0].last && rings[0].count == 9)
        #expect(GeoPolygon(rings: rings).contains(c(5, 5)))
        #expect(OverpassBoundary.assembleRings([top, bottom]).isEmpty)                 // never closes
        #expect(OverpassBoundary.assembleRings([[c(0, 0), c(0, 1), c(1, 1), c(0, 0)]]).count == 1)   // already closed
    }

    @Test func boundaryResolverReturnsNilOnFailure() async {
        let busy = OverpassBoundary(http: quietHTTP(FakeTransport { _ in (504, Data()) }))
        #expect(await busy.resolveBoundary(areaName: "Glacier National Park", near: nil) == nil)
        let html = OverpassBoundary(http: quietHTTP(FakeTransport { _ in (200, Data("<html/>".utf8)) }))
        #expect(await html.resolveBoundary(areaName: "Glacier National Park", near: nil) == nil)
        let empty = OverpassBoundary(http: quietHTTP(FakeTransport { _ in (200, Data(#"{"elements":[]}"#.utf8)) }))
        #expect(await empty.resolveBoundary(areaName: "Atlantis", near: nil) == nil)
    }

    @Test func boundaryQueryMatchesWithAndWithoutNationalPark() {
        let region = GeoRegion(center: Coordinate(latitude: 48.7, longitude: -113.8), latitudeDelta: 0.3, longitudeDelta: 0.4)
        let q = OverpassBoundary.query(areaName: "Glacier National Park", near: region)
        #expect(q.contains("\"^Glacier( National Park)?$\",i"))
        #expect(q.contains("boundary") && q.contains("nature_reserve") && q.contains("out geom;"))
        let weird = OverpassBoundary.query(areaName: "St. \"Mary\" (Lake)", near: nil)
        #expect(weird.contains("\\\\(Lake\\\\)") && weird.contains("\\\"Mary\\\""))
    }
}

// MARK: Wikipedia and Wikivoyage

@Suite struct WikipediaTests {
    @Test func parsesGeosearchAndExtracts() throws {
        let hits = try WikipediaParser.geosearch(DiscoveryFixture.data("wikipedia-geosearch-glacier.json"))
        #expect(hits.count == 25)
        #expect(hits[0].title == "Logan Pass" && abs(hits[0].coordinate.latitude - 48.6967) < 0.001)
        let extracts = WikipediaParser.extracts(DiscoveryFixture.data("wikipedia-extracts-glacier.json"))
        #expect(extracts.count == 3)
        #expect(extracts.first { $0.pageID == 26455772 }?.text?.contains("Lewis Range") == true)
    }

    @Test func titleFilterAndCleaning() {
        #expect(WikipediaParser.titleMatches("Mount Oberlin", feature: .peak))
        #expect(WikipediaParser.titleMatches("Clements Mountain", feature: .peak))
        #expect(!WikipediaParser.titleMatches("Logan Pass Visitor Center", feature: .peak))
        #expect(WikipediaParser.titleMatches("Bird Woman Falls", feature: .waterfall))
        #expect(!WikipediaParser.titleMatches("Bird Woman Falls", feature: .lake))
        #expect(WikipediaParser.titleMatches("Hidden Lake (Flathead County, Montana)", feature: .lake))
        #expect(WikipediaParser.titleMatches("Logan Pass", feature: nil))
        #expect(WikipediaParser.cleanTitle("Hidden Lake (Flathead County, Montana)") == "Hidden Lake")
        #expect(WikipediaParser.inferFeature(from: "Piegan Glacier") == .glacier)
    }

    @Test func samplingGrid() {
        func region(_ lat: Double, _ latDelta: Double, _ lonDelta: Double) -> GeoRegion {
            GeoRegion(center: Coordinate(latitude: lat, longitude: -113.8), latitudeDelta: latDelta, longitudeDelta: lonDelta)
        }
        #expect(WikipediaProvider.samplePoints(for: region(48.7, 0.1, 0.1)).count == 1)
        let big = WikipediaProvider.samplePoints(for: region(48.6, 0.8, 1.3))
        #expect(big.count == 9)
        #expect(WikipediaProvider.samplePoints(for: region(48.6, 5, 5)).count == 9)
        #expect(Set(big.map(\.cacheKey)).count == 9)
    }

    @Test func providerFiltersByFeatureAndAreaAndAddsSnippets() async throws {
        let transport = Wire.make()
        let provider = WikipediaProvider(http: quietHTTP(transport))
        let area = DiscoveryArea(name: "Glacier National Park", region: GeoRegion(center: glacierRegionCentre, latitudeDelta: 0.3, longitudeDelta: 0.45))
        let places = try await provider.discover(in: area, feature: .peak, text: nil, settings: DiscoverySettings())
        let names = places.map(\.name)
        #expect(names.contains("Clements Mountain") && names.contains("Mount Oberlin") && names.contains("Reynolds Mountain"))
        #expect(!names.contains("Logan Pass") && !names.contains("Bird Woman Falls"))
        let clements = try #require(places.first { $0.name == "Clements Mountain" })
        #expect(clements.elevationMeters == 2672)
        #expect(clements.snippet?.contains("Lewis Range") == true)
        #expect(clements.mentions == 1 && clements.sources == [.wikipedia])
        #expect(clements.links.first?.absoluteString == "https://en.wikipedia.org/wiki/Clements_Mountain")
        #expect(Wire.hosts(transport).allSatisfy { $0 == "en.wikipedia.org" })
        let first = try #require(transport.requests.first)
        #expect(queryText(first).contains("gsradius=10000") && queryText(first).contains("gslimit=50") && queryText(first).contains("formatversion=2"))
    }

    @Test func failureOfEveryGeosearchThrows() async {
        let provider = WikipediaProvider(http: quietHTTP(FakeTransport { _ in (503, Data()) }))
        let area = DiscoveryArea(name: "x", region: GeoRegion(center: glacierRegionCentre, latitudeDelta: 0.1, longitudeDelta: 0.1))
        await #expect(throws: DiscoveryError.busy) { try await provider.discover(in: area, feature: nil, text: nil, settings: DiscoverySettings()) }
    }
}

@Suite struct WikivoyageTests {
    @Test func parsesSeeListings() {
        let wikitext = (try? WikivoyageParser.wikitext(DiscoveryFixture.data("wikivoyage-glacier-see.json"))) ?? ""
        let listings = WikivoyageParser.seeListings(in: wikitext)
        #expect(listings.count == 13)
        let road = listings.first { $0.name == "Going-to-the-Sun Road" }
        #expect(road?.coordinate == Coordinate(latitude: 48.695, longitude: -113.817))
        #expect(road?.summary?.contains("most spectacular viewpoints") == true)
        #expect(road?.summary?.contains("[") == false)
        #expect(listings.contains { $0.name == "Iceberg Lake" && $0.coordinate != nil })
    }

    @Test func listingWithoutCoordinatesAndNestedMarkup() {
        let text = """
        == Understand ==
        {{see|name=Not Here|lat=1|long=2}}
        == See ==
        * {{see | name=[[Hidden Lake]] | lat= | long= | content=A '''lovely''' lake with a [[boardwalk|walkway]] and {{convert|3|km}} trail. [http://x.example Details].}}
        * {{listing|type=see|name=Bad Coordinates|lat=900|long=0|content=Nope.}}
        * {{do|name=Skipped|lat=1|long=2}}
        === Sub ===
        * {{see|name=Sub Item|lat=48.5|long=-113.5}}
        == Do ==
        * {{see|name=Out Of Section|lat=1|long=1}}
        """
        let listings = WikivoyageParser.seeListings(in: text)
        #expect(listings.map(\.name) == ["Hidden Lake", "Bad Coordinates", "Sub Item"])
        #expect(listings[0].coordinate == nil)
        #expect(listings[0].summary == "A lovely lake with a walkway and trail. Details.")
        #expect(listings[1].coordinate == nil)
        #expect(listings[2].coordinate == Coordinate(latitude: 48.5, longitude: -113.5))
    }

    @Test func providerFallsBackToSearchWhenTheTitleIsMissing() async throws {
        let transport = Wire.make()
        let provider = WikivoyageProvider(http: quietHTTP(transport))
        let area = DiscoveryArea(name: "Glacier National Park", region: GeoRegion(center: glacierRegionCentre, latitudeDelta: 0.3, longitudeDelta: 0.45))
        let places = try await provider.discover(in: area, feature: nil, text: nil, settings: DiscoverySettings())
        #expect(places.count == 13 && places.allSatisfy { $0.sources == [.wikivoyage] && $0.mentions == 2 })
        #expect(transport.callCount == 3)        // direct page (missing), search, page
        let lakes = try await provider.discover(in: area, feature: .lake, text: nil, settings: DiscoverySettings())
        #expect(Set(lakes.map(\.name)) == ["Swiftcurrent Lake", "Iceberg Lake"])
    }

    @Test func missingPageEverywhereIsNotFound() async {
        let transport = Wire.make(yosemite: true)
        let provider = WikivoyageProvider(http: quietHTTP(transport))
        let area = DiscoveryArea(name: "Yosemite", region: GeoRegion(center: Coordinate(latitude: 37.7, longitude: -119.6), latitudeDelta: 0.3, longitudeDelta: 0.4))
        await #expect(throws: DiscoveryError.notFound) { try await provider.discover(in: area, feature: .waterfall, text: nil, settings: DiscoverySettings()) }
        let unnamed = DiscoveryArea(name: nil, region: area.region)
        await #expect(throws: DiscoveryError.notFound) { try await provider.discover(in: unnamed, feature: nil, text: nil, settings: DiscoverySettings()) }
    }
}

// MARK: Reddit and Google

@Suite struct TextSourceTests {
    private let area = DiscoveryArea(name: "Glacier National Park", region: GeoRegion(center: glacierRegionCentre, latitudeDelta: 0.3, longitudeDelta: 0.45))

    @Test func parsesRedditPostsAndSkipsNSFW() throws {
        let posts = try RedditParser.posts(DiscoveryFixture.data("reddit-search-glacier.json"))
        #expect(posts.count == 5)
        #expect(posts[0].source == .reddit && posts[0].score == 842)
        #expect(posts[0].title.contains("Mount Cleveland"))
        #expect(posts[0].url?.absoluteString == "https://www.reddit.com/r/GlacierNationalPark/comments/aaa111/post/")
        #expect(!posts.contains { $0.title.contains("NSFW") })
        #expect(throws: DiscoveryError.badResponse) { try RedditParser.posts(Data("<html>blocked</html>".utf8)) }
    }

    @Test func redditRequestsAndToleratesAMissingSubreddit() async throws {
        let transport = Wire.make()
        let source = RedditSource(http: quietHTTP(transport))
        let posts = try await source.posts(in: area, feature: .peak, text: nil)
        #expect(transport.callCount == 3)
        #expect(posts.count == 5)           // the same posts from two searches are de-duplicated by link
        let urls = transport.requests.compactMap(\.url)
        #expect(urls[0].path == "/search.json")
        #expect(queryText(transport.requests[0]).contains("q=mountains Glacier National Park"))
        #expect(queryText(transport.requests[0]).contains("limit=25") && queryText(transport.requests[0]).contains("sort=relevance") && queryText(transport.requests[0]).contains("t=all"))
        #expect(urls[1].path == "/r/EarthPorn+itookapicture+photography+landscapephotography+NationalPark+hiking/search.json")
        #expect(queryText(transport.requests[1]).contains("restrict_sr=1"))
        #expect(urls[2].path == "/r/GlacierNationalPark/search.json")
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Iter/test") == true })
    }

    @Test func redditBlockingBecomesRateLimited() async {
        let source = RedditSource(http: quietHTTP(Wire.make(reddit: { _ in (403, Data("<html>blocked</html>".utf8)) })))
        await #expect(throws: DiscoveryError.rateLimited) { try await source.posts(in: area, feature: nil, text: "sunrise") }
        let throttled = Wire.make(reddit: { _ in (429, Data()) })
        let limited = RedditSource(http: quietHTTP(throttled))
        await #expect(throws: DiscoveryError.rateLimited) { try await limited.posts(in: area, feature: nil, text: nil) }
        #expect(throttled.callCount == 1)         // stops after the first refusal
    }

    @Test func subredditGuess() {
        #expect(RedditSource.guessSubreddit("Glacier National Park") == "GlacierNationalPark")
        #expect(RedditSource.guessSubreddit("oregon coast") == "OregonCoast")
        #expect(RedditSource.guessSubreddit("Banff, Alberta") == "BanffAlberta")
        #expect(RedditSource.guessSubreddit("A") == nil)
        #expect(RedditSource.guessSubreddit(nil) == nil)
    }

    @Test func googleParsesTheDocumentedShape() throws {
        let texts = try GoogleParser.results(DiscoveryFixture.data("google-customsearch-glacier.json"))
        #expect(texts.count == 3 && texts.allSatisfy { $0.source == .google })
        #expect(texts[0].body.contains("Mount Cleveland"))
        #expect(texts[1].url?.absoluteString == "https://example.com/siyeh")
        #expect(throws: DiscoveryError.badResponse) { try GoogleParser.results(DiscoveryFixture.data("google-customsearch-error.json")) }
    }

    @Test func googleWithoutAKeyMakesNoRequest() async {
        let transport = FakeTransport()
        for keys in [InMemoryDiscoveryKeyStore(), InMemoryDiscoveryKeyStore(googleAPIKey: "only-a-key"), InMemoryDiscoveryKeyStore(googleEngineID: "only-an-engine")] {
            let source = GoogleSearchSource(http: quietHTTP(transport), keys: keys)
            #expect(source.readiness() == .needsKey)
            await #expect(throws: DiscoveryError.self) { try await source.texts(in: area, feature: .peak, text: nil, settings: DiscoverySettings()) }
        }
        #expect(transport.callCount == 0)
    }

    @Test func googleWithAKeyRequestsAndNeverLeaksIt() async throws {
        let secret = "AIzaSECRET-0123456789"
        let transport = FakeTransport { _ in (200, DiscoveryFixture.data("google-customsearch-glacier.json")) }
        let source = GoogleSearchSource(http: quietHTTP(transport), keys: InMemoryDiscoveryKeyStore(googleAPIKey: secret, googleEngineID: "cx123"))
        #expect(source.readiness() == nil)
        let texts = try await source.texts(in: area, feature: .peak, text: nil, settings: DiscoverySettings())
        #expect(texts.count == 3)
        let q = queryText(transport.requests[0])
        #expect(transport.requests[0].url?.host == "www.googleapis.com")
        #expect(q.contains("key=\(secret)") && q.contains("cx=cx123") && q.contains("best photography spots mountains Glacier National Park"))

        let failing = GoogleSearchSource(http: quietHTTP(FakeTransport { _ in (400, DiscoveryFixture.data("google-customsearch-error.json")) }),
                                         keys: InMemoryDiscoveryKeyStore(googleAPIKey: secret, googleEngineID: "cx123"))
        do { _ = try await failing.texts(in: area, feature: nil, text: nil, settings: DiscoverySettings()); Issue.record("expected an error") }
        catch { #expect(!"\(error)".contains(secret) && !(error as? DiscoveryError)!.reason.contains(secret)) }
        #expect(DiscoveryError.map(URLError(.badURL), redacting: [secret]).reason.contains(secret) == false)
    }

    @Test func keyStoreRoundTrip() throws {
        let store = InMemoryDiscoveryKeyStore()
        #expect(!store.hasGoogleCredentials)
        try store.setGoogleAPIKey("k")
        #expect(!store.hasGoogleCredentials)
        try store.setGoogleEngineID("e")
        #expect(store.hasGoogleCredentials)
        try store.removeGoogleCredentials()
        #expect(store.googleAPIKey == nil && store.googleEngineID == nil)
        #expect(KeychainDiscoveryKeyStore.defaultService != KeychainAPIKeyStore.defaultService)
    }
}
