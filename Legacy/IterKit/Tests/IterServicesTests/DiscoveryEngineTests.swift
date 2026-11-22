import Foundation
import Testing
import IterCore
@testable import IterServices

// MARK: Extraction filter and validator

@Suite struct DiscoveryExtractionTests {
    private let area = DiscoveryArea(name: "Glacier National Park", region: GeoRegion(center: glacierRegionCentre, latitudeDelta: 0.8, longitudeDelta: 1.3))
    private let texts = [
        DiscoveryText(source: .reddit, title: "Sunrise on Mount Cleveland", body: "Worth the walk. Also saw Reynolds Mountain.", score: 842,
                      url: URL(string: "https://www.reddit.com/r/x/1/")),
        DiscoveryText(source: .google, title: "Photo spots", body: "Try Siyeh Peak for alpenglow; Mount Cleveland too.", score: 0, url: URL(string: "https://example.com/g")),
    ]

    @Test func dropsNamesThatAreNotInTheTexts() {
        let out = DiscoveryExtractionFilter.apply(
            candidates: [("Mount Cleveland", "Tallest."), ("Mount Zork", "Invented."), ("Reynolds Mountain", ""), ("Glacier National Park", "The area."), ("park", "Generic.")],
            texts: texts, area: area, feature: .peak, maximum: 12)
        #expect(out.map(\.name) == ["Mount Cleveland", "Reynolds Mountain"])
        #expect(out[0].sources == [.reddit, .google])
        #expect(out[0].mentions == (1 + 4) + 1)             // an 842-point post counts 1 + 4, the Google result 1
        #expect(out[0].links.count == 2 && out[0].why == "Tallest.")
        #expect(out[1].why == nil && out[1].sources == [.reddit])
        #expect(out.allSatisfy { $0.coordinate == nil && $0.feature == .peak })
    }

    @Test func matchesIgnoringCaseAndAccentsButNotPartialWords() {
        let accented = [DiscoveryText(source: .reddit, title: "Café Grünhorn at DAWN", body: "")]
        #expect(DiscoveryExtractionFilter.apply(candidates: [("cafe grunhorn", "")], texts: accented, area: area, feature: nil, maximum: 5).count == 1)
        #expect(DiscoveryExtractionFilter.apply(candidates: [("Grunhorn at", "")], texts: accented, area: area, feature: nil, maximum: 5).count == 1)
        #expect(DiscoveryExtractionFilter.apply(candidates: [("Grunho", "")], texts: accented, area: area, feature: nil, maximum: 5).isEmpty)
    }

    @Test func capsAndDeduplicates() {
        let many = (0..<20).map { DiscoveryText(source: .reddit, title: "Peak\($0)x", body: "") }
        let names = (0..<20).map { ("Peak\($0)x", "") } + [("peak0x", "")]
        #expect(DiscoveryExtractionFilter.apply(candidates: names, texts: many, area: area, feature: nil, maximum: 12).count == 12)
    }

    @Test func promptIsSmallAndCarriesThePrefix() {
        let big = (0..<200).map { DiscoveryText(source: .reddit, title: "Post \($0) about Mount Cleveland", body: String(repeating: "word ", count: 80), score: $0) }
        var settings = DiscoverySettings(promptPrefix: "Moody light")
        settings.tasteSummary = "Haystack Rock"
        let prompt = FoundationModelsDiscoveryExtractor.prompt(texts: big, area: area, feature: .peak, settings: settings)
        #expect(prompt.hasPrefix("What the user likes to shoot"))
        #expect(prompt.contains("Moody light") && prompt.contains("Haystack Rock"))
        #expect(prompt.contains("Post 199"))              // highest score first
        #expect(!prompt.contains("Post 0 "))
        #expect(prompt.count < 2_500 + 900)
        #expect(prompt.contains("Looking for: mountains"))
    }
}

@Suite struct DiscoveryValidatorTests {
    private let area = DiscoveryArea(name: "Glacier National Park", region: GeoRegion(center: glacierRegionCentre, latitudeDelta: 0.8, longitudeDelta: 1.3))

    @Test func resolvesInsideDropsOutsideAndMismatches() async throws {
        let search = ScriptedSearch { query in
            if query.hasPrefix("Mount Cleveland") { return [place("Mount Cleveland", 48.925, -113.848)] }
            if query.hasPrefix("Mount Rainier") { return [place("Mount Rainier", 46.853, -121.760)] }                 // outside the area
            if query.hasPrefix("Hidden Lake") { return [place("Glacier Park Lodge", 48.68, -113.8), place("Hidden Lake Overlook", 48.695, -113.73)] }
            if query.hasPrefix("Nowhere Peak") { return [place("Completely Different Name", 48.7, -113.7)] }
            return []
        }
        let validator = DiscoveryValidator(placeSearch: search)
        let input = [
            DiscoveredPlace(name: "Mount Cleveland", sources: [.reddit], mentions: 5),
            DiscoveredPlace(name: "Mount Rainier", sources: [.reddit], mentions: 3),
            DiscoveredPlace(name: "Hidden Lake", sources: [.wikivoyage]),
            DiscoveredPlace(name: "Nowhere Peak", sources: [.google]),
            DiscoveredPlace(name: "Located Inside", coordinate: Coordinate(latitude: 48.6, longitude: -113.8), sources: [.openStreetMap]),
            DiscoveredPlace(name: "Located Outside", coordinate: Coordinate(latitude: 40, longitude: -100), sources: [.openStreetMap]),
        ]
        let result = try await validator.validate(input, in: area)
        #expect(Set(result.places.map(\.name)) == ["Mount Cleveland", "Hidden Lake", "Located Inside"])
        #expect(result.resolved == 2)
        let cleveland = try #require(result.places.first { $0.name == "Mount Cleveland" })
        #expect(cleveland.coordinate == Coordinate(latitude: 48.925, longitude: -113.848))
        #expect(cleveland.sources == [.reddit, .appleMaps])
        #expect(result.places.first { $0.name == "Hidden Lake" }?.coordinate == Coordinate(latitude: 48.695, longitude: -113.73))
        #expect(search.queries.contains("Mount Cleveland Glacier National Park"))
    }

    @Test func capsLookupsBestMentionedFirst() async throws {
        let search = ScriptedSearch { q in [place(String(q.dropLast(" Glacier National Park".count)), 48.6, -113.8)] }
        let validator = DiscoveryValidator(placeSearch: search, maximumLookups: 2)
        let input = [("Low One", 1), ("Top One", 9), ("Mid One", 5), ("Top One", 4)].map { DiscoveredPlace(name: $0.0, sources: [.reddit], mentions: $0.1) }
        let result = try await validator.validate(input, in: area)
        #expect(search.queries.count == 2)
        #expect(Set(result.places.map(\.name)) == ["Top One", "Mid One"])
        #expect(result.places.filter { $0.name == "Top One" }.count == 2)         // duplicates share one lookup
    }

    @Test func aFailingSearchDropsThePlaceNotTheRun() async throws {
        struct Boom: PlaceSearching {
            func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { throw URLError(.notConnectedToInternet) }
            func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
        }
        let result = try await DiscoveryValidator(placeSearch: Boom()).validate([DiscoveredPlace(name: "A Peak", sources: [.reddit])], in: area)
        #expect(result.places.isEmpty && result.resolved == 0)
    }
}

// MARK: Engine

@Suite struct DiscoveryEngineTests {
    private let centre = place("Glacier National Park", 48.7596, -113.787)

    private func engine(_ transport: FakeTransport, extractor: (any DiscoveryExtracting)? = nil,
                        keys: InMemoryDiscoveryKeyStore = InMemoryDiscoveryKeyStore(), search: ScriptedSearch? = nil, boundary: Bool = true) -> DiscoveryEngine {
        let http = quietHTTP(transport)
        let names = ["Mount Cleveland", "Reynolds Mountain", "Mount Jackson", "Mount Rainier", "Going-to-the-Sun Mountain", "Mount Hidden", "Mount Zork"]
        let lookup = search ?? ScriptedSearch { q in
            let table: [(String, Double, Double)] = [("Mount Cleveland", 48.9251, -113.8481), ("Reynolds Mountain", 48.6719, -113.7235),
                                                     ("Mount Jackson", 48.6006, -113.7221), ("Mount Rainier", 46.853, -121.760),
                                                     ("Going-to-the-Sun Mountain", 48.6908, -113.6365)]
            return table.filter { q.hasPrefix($0.0) }.map { place($0.0, $0.1, $0.2) }
        }
        return DiscoveryEngine(
            providers: [OverpassProvider(http: http), WikipediaProvider(http: http), WikivoyageProvider(http: http)],
            textSources: [RedditSource(http: http), GoogleSearchSource(http: http, keys: keys)],
            extractor: extractor ?? ListExtractor(names: names), placeSearch: lookup, geocoder: ScriptedGeocoder(results: [centre]),
            boundary: boundary ? OverpassBoundary(http: http) : nil)
    }

    private var settings: DiscoverySettings { DiscoverySettings(preference: .popular, maxResults: 60) }

    @Test func mountainsInGlacierNationalPark() async throws {
        let transport = Wire.make()
        let engine = engine(transport)
        let query = try #require(FeatureAreaQuery.parse("mountains in Glacier National Park"))
        let area = try #require(await engine.resolveArea(named: query.area))
        #expect(area.boundary != nil && area.name == "Glacier National Park")
        #expect(area.region == area.boundary?.boundingRegion || area.region.latitudeDelta >= 0.02)

        let report = try await engine.discover(area: area, feature: query.feature, text: nil, settings: settings)
        let byName = Dictionary(report.places.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        // Every fixture peak that lies inside the boundary is present, with its elevation, from OpenStreetMap.
        let osm = try OverpassParser.places(from: DiscoveryFixture.data("overpass-peaks-glacier.json"), defaultFeature: .peak)
        let boundary = try #require(area.boundary)
        let inside = osm.filter { boundary.contains($0.coordinate!) }
        #expect(inside.count >= 15 && inside.count < osm.count)
        for expected in inside {
            let got = try #require(byName[expected.name], "\(expected.name) missing")
            #expect(got.sources.contains(.openStreetMap))
            #expect(got.elevationMeters == expected.elevationMeters)
        }
        for name in ["Mount Cleveland": 3190.0, "Mount Jackson": 3064, "Going-to-the-Sun Mountain": 2939, "Reynolds Mountain": 2666].sorted(by: { $0.key < $1.key }).map({ ($0.key, $0.value) }) {
            #expect(byName[name.0]?.elevationMeters == name.1)
        }
        // Outside the boundary: dropped.
        for name in ["Bald Rock", "Big Mountain", "Looking Glass Hill", "Red Blanket Butte", "Bald Hill", "Mount Rainier"] { #expect(byName[name] == nil, "\(name) should be dropped") }
        // Hallucination and the NSFW-only name never appear.
        #expect(byName["Mount Zork"] == nil && byName["Mount Hidden"] == nil)
        // Everything reported is real and inside.
        #expect(report.places.allSatisfy { $0.coordinate.map(area.contains) == true })
        #expect(Set(report.places.map(\.id)).count == report.places.count)

        // Sources are labelled per place.
        #expect(byName["Mount Cleveland"]?.sources.isSuperset(of: [.openStreetMap, .reddit]) == true)
        #expect(byName["Mount Cleveland"]?.mentions == 5)
        #expect(byName["Reynolds Mountain"]?.sources.isSuperset(of: [.openStreetMap, .wikipedia, .reddit]) == true)
        #expect(byName["Clements Mountain"]?.sources.contains(.wikipedia) == true)

        // And per source.
        guard case .ok(let osmCount) = report.statuses[.openStreetMap] else { Issue.record("osm status"); return }
        #expect(osmCount == inside.count)
        for id: DiscoverySourceID in [.wikipedia, .reddit] { if case .ok(let n) = report.statuses[id] { #expect(n > 0) } else { Issue.record("\(id) not ok") } }
        #expect(report.statuses[.google] == .disabled)
        if case .ok(let n) = report.statuses[.appleMaps] { #expect(n >= 4) } else { Issue.record("apple maps status") }

        // Most talked about first.
        #expect(report.places.first?.name == "Mount Cleveland")
        #expect(report.places.prefix(3).map(\.mentions) == report.places.prefix(3).map(\.mentions).sorted(by: >))
    }

    @Test func waterfallsInYosemite() async throws {
        let transport = Wire.make(yosemite: true)
        let yosemite = place("Yosemite National Park", 37.7339, -119.6020)
        let http = quietHTTP(transport)
        let engine = DiscoveryEngine(providers: [OverpassProvider(http: http), WikipediaProvider(http: http), WikivoyageProvider(http: http)],
                                     textSources: [RedditSource(http: http)], extractor: ListExtractor(names: []),
                                     placeSearch: ScriptedSearch(), geocoder: ScriptedGeocoder(results: [yosemite]), boundary: nil)
        let query = try #require(FeatureAreaQuery.parse("waterfalls of Yosemite"))
        let area = try #require(await engine.resolveArea(named: query.area))
        #expect(area.boundary == nil)
        #expect(area.region.latitudeDelta == DiscoveryEngine.defaultAreaSpanDegrees)
        let report = try await engine.discover(area: area, feature: query.feature, text: nil, settings: settings)
        let names = Set(report.places.map(\.name))
        #expect(["Upper Yosemite Fall", "Lower Yosemite Fall", "Bridalveil Fall", "Vernal Fall", "Nevada Fall"].allSatisfy(names.contains))
        #expect(report.places.first { $0.name == "Vernal Fall" }?.elevationMeters == 1538)
        #expect(report.places.allSatisfy { $0.feature == .waterfall && $0.sources == [.openStreetMap] })
        #expect(report.statuses[.wikivoyage] == .skipped)
        #expect(report.statuses[.wikipedia] == .ok(0))
        #expect(report.statuses[.reddit] == .ok(0))
    }

    @Test func aFailingSourceBecomesAStatusAndTheRestSurvive() async throws {
        let offline = Wire.make(reddit: { _ in throw URLError(.notConnectedToInternet) })
        let e = engine(offline)
        let area = try #require(await e.resolveArea(named: "Glacier National Park"))
        let report = try await e.discover(area: area, feature: .peak, text: nil, settings: settings)
        #expect(report.statuses[.reddit] == .unavailable("Offline"))
        #expect(report.places.contains { $0.name == "Mount Cleveland" && $0.elevationMeters == 3190 })
        #expect(report.places.contains { $0.sources.contains(.wikipedia) })

        let blocked = engine(Wire.make(reddit: { _ in (403, Data("<html/>".utf8)) }))
        let r2 = try await blocked.discover(area: area, feature: .peak, text: nil, settings: settings)
        #expect(r2.statuses[.reddit] == .unavailable("Rate limited"))
        #expect(!r2.places.isEmpty)

        let overloaded = FakeTransport { request in
            request.url?.host == "overpass-api.de" ? (504, Data()) : try replay(request)
        }
        let r3 = try await engine(overloaded, boundary: false).discover(area: area, feature: .peak, text: nil, settings: settings)
        #expect(r3.statuses[.openStreetMap] == .unavailable("Server busy"))
        #expect(r3.places.contains { $0.name == "Reynolds Mountain" && $0.sources.contains(.wikipedia) })
        #expect(r3.places.allSatisfy { !$0.sources.contains(.openStreetMap) })
    }

    @Test func unavailableExtractorKeepsStructuredSources() async throws {
        let e = engine(Wire.make(), extractor: FailingExtractor())
        let area = try #require(await e.resolveArea(named: "Glacier National Park"))
        let report = try await e.discover(area: area, feature: .peak, text: nil, settings: settings)
        #expect(report.statuses[.reddit] == .unavailable("Apple Intelligence unavailable"))
        guard case .ok(let n) = report.statuses[.openStreetMap] else { Issue.record("osm"); return }
        #expect(n >= 15)
        #expect(report.places.allSatisfy { !$0.sources.contains(.reddit) })
    }

    @Test func googleWithoutAKeyIsNeedsKeyAndNeverCallsGoogle() async throws {
        let transport = Wire.make()
        let e = engine(transport)
        var withGoogle = settings
        withGoogle.enabledSources.insert(.google)
        let area = try #require(await e.resolveArea(named: "Glacier National Park"))
        let report = try await e.discover(area: area, feature: .peak, text: nil, settings: withGoogle)
        #expect(report.statuses[.google] == .needsKey)
        #expect(!Wire.hosts(transport).contains("www.googleapis.com"))
    }

    @Test func googleWithAKeyFeedsTheExtractor() async throws {
        let transport = FakeTransport { request in
            request.url?.host == "www.googleapis.com" ? (200, DiscoveryFixture.data("google-customsearch-glacier.json")) : try replay(request)
        }
        let keys = InMemoryDiscoveryKeyStore(googleAPIKey: "k", googleEngineID: "cx")
        let search = ScriptedSearch { q in q.hasPrefix("Siyeh Peak") ? [place("Siyeh Peak", 48.7, -113.68)] : [] }
        let e = engine(transport, extractor: ListExtractor(names: ["Siyeh Peak"]), keys: keys, search: search)
        var withGoogle = settings
        withGoogle.enabledSources.insert(.google)
        let area = try #require(await e.resolveArea(named: "Glacier National Park"))
        let report = try await e.discover(area: area, feature: .peak, text: nil, settings: withGoogle)
        let siyeh = try #require(report.places.first { $0.name == "Siyeh Peak" })
        #expect(siyeh.sources.contains(.google))
        #expect(report.statuses[.google] == .ok(1))
    }

    @Test func disabledSourcesMakeNoRequests() async throws {
        let transport = Wire.make()
        let e = engine(transport)
        var only = settings
        only.enabledSources = [.openStreetMap]
        let area = try #require(await e.resolveArea(named: "Glacier National Park"))
        let before = transport.callCount
        let report = try await e.discover(area: area, feature: .peak, text: nil, settings: only)
        #expect(Wire.hosts(transport).dropFirst(before).allSatisfy { $0 == "overpass-api.de" })
        #expect(report.statuses[.reddit] == .disabled && report.statuses[.wikipedia] == .disabled && report.statuses[.wikivoyage] == .disabled)
        #expect(report.places.allSatisfy { $0.sources == [.openStreetMap] })
    }

    @Test func maxResultsAndPreferenceApply() async throws {
        let e = engine(Wire.make())
        let area = try #require(await e.resolveArea(named: "Glacier National Park"))
        let small = DiscoverySettings(preference: .unique, maxResults: 5)
        let report = try await e.discover(area: area, feature: .peak, text: nil, settings: small)
        #expect(report.places.count == 5)
        #expect(report.places.map(\.mentions) == report.places.map(\.mentions).sorted())
    }

    @Test func resolveAreaFallsBackAndFailsCleanly() async {
        let nothing = DiscoveryEngine(providers: [], placeSearch: ScriptedSearch(), geocoder: ScriptedGeocoder(results: []), boundary: nil)
        #expect(await nothing.resolveArea(named: "Atlantis") == nil)
        #expect(await nothing.resolveArea(named: "  ") == nil)
        let viaSearch = await nothing.resolveArea(named: "Banff", fallbackSearch: ScriptedSearch { _ in [place("Banff", 51.178, -115.57)] })
        #expect(viaSearch?.region.center == Coordinate(latitude: 51.178, longitude: -115.57))
        #expect(viaSearch?.name == "Banff")
    }
}

/// The default Glacier wire, as a transport reply.
private func replay(_ request: URLRequest) throws -> (status: Int, body: Data) { try Wire.route(request) }
