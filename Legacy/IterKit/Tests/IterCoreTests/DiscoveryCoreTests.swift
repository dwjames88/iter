import Foundation
import Testing
@testable import IterCore

// MARK: FeatureAreaQuery

@Suite struct FeatureAreaQueryTests {
    @Test(arguments: [
        ("mountains in Glacier National Park", FeatureKind.peak, "Glacier National Park"),
        ("all the mountains in glacier national park", .peak, "glacier national park"),
        ("Show me all of the peaks around Banff", .peak, "Banff"),
        ("waterfalls of Yosemite", .waterfall, "Yosemite"),
        ("peaks around Banff", .peak, "Banff"),
        ("lighthouses on the oregon coast", .lighthouse, "oregon coast"),
        ("What are the best arches near Moab?", .arch, "Moab"),
        ("hot springs in Iceland.", .hotSpring, "Iceland"),
        ("natural arches within Arches National Park", .arch, "Arches National Park"),
        ("glaciers across Alaska", .glacier, "Alaska"),
        ("lakes in the Lake District", .lake, "Lake District"),
        ("viewpoints close to Lisbon", .viewpoint, "Lisbon"),
        ("Volcanoes in Hawaii Volcanoes National Park", .peak, "Hawaii Volcanoes National Park"),
        ("covered bridges at Vermont", .bridge, "Vermont"),
        ("castles in Scotland", .castle, "Scotland"),
        ("slot canyons near Page, Arizona", .canyon, "Page, Arizona"),
        ("caves in Mammoth Cave", .cave, "Mammoth Cave"),
        ("beaches of the Olympic Peninsula", .beach, "Olympic Peninsula"),
        ("peaks in Glacier National Park at sunset", .peak, "Glacier National Park"),
        ("waterfalls in Yosemite for sunrise", .waterfall, "Yosemite"),
        ("lakes near Banff at golden hour", .lake, "Banff"),
        ("arches in Moab for blue hour tomorrow", .arch, "Moab"),
        ("beaches in Oregon this weekend", .beach, "Oregon"),
        ("lighthouses on the Maine coast tonight", .lighthouse, "Maine coast"),
    ])
    func parses(text: String, feature: FeatureKind, area: String) {
        #expect(FeatureAreaQuery.parse(text) == FeatureAreaQuery(feature: feature, area: area))
    }

    @Test(arguments: [
        "sunrise spots in Glacier National Park",     // no known feature
        "mountains",                                  // no area
        "waterfalls near me",                         // not a named area
        "waterfalls near here for sunrise",           // a map phrase, not a place
        "peaks around here at sunset",
        "lakes in this area",
        "viewpoints in the map tonight",
        "arches nearby",
        "beaches near my location",
        "waterfalls in",                              // empty area
        "Glacier National Park mountains",            // no preposition
        "good light for a lake tomorrow",             // feature, but no preposition after it
        "",
    ])
    func rejects(text: String) {
        #expect(FeatureAreaQuery.parse(text) == nil)
    }

    @Test func everyFeatureHasSynonymsAndOSMTags() {
        for kind in FeatureKind.allCases {
            #expect(!kind.synonyms.isEmpty)
            #expect(!kind.osmTags.isEmpty)
            #expect(FeatureKind.from(phrase: kind.synonyms[0]) == kind)
            #expect(kind.osmTags.allSatisfy { $0.overpassFilters.contains("\"name\"") })
        }
    }

    @Test func overpassFilters() {
        #expect(FeatureKind.peak.osmTags[0].overpassFilters == "[\"natural\"~\"^(peak|volcano)$\"][\"name\"]")
        #expect(FeatureKind.waterfall.osmTags[0].overpassFilters == "[\"waterway\"=\"waterfall\"][\"name\"]")
        #expect(FeatureKind.lake.osmTags[0].overpassFilters == "[\"natural\"=\"water\"][\"water\"~\"^(lake|reservoir)$\"][\"name\"]")
        #expect(FeatureKind.canyon.osmTags[0].overpassFilters == "[\"natural\"=\"valley\"][\"name\"~\"Canyon\"]")
    }
}

// MARK: Geometry

@Suite struct GeoPolygonTests {
    private func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }

    @Test func containsSquareAndHole() {
        let outer = [c(0, 0), c(0, 10), c(10, 10), c(10, 0), c(0, 0)]
        let hole = [c(4, 4), c(4, 6), c(6, 6), c(6, 4), c(4, 4)]
        let p = GeoPolygon(rings: [outer, hole])
        #expect(p.contains(c(2, 2)))
        #expect(!p.contains(c(5, 5)))
        #expect(!p.contains(c(11, 5)))
        #expect(!p.contains(c(5, -1)))
    }

    @Test func concaveAndTwoParts() {
        let ell = [c(0, 0), c(0, 10), c(4, 10), c(4, 4), c(10, 4), c(10, 0)]
        let far = [c(20, 20), c(20, 22), c(22, 22), c(22, 20)]
        let p = GeoPolygon(rings: [ell, far])
        #expect(p.contains(c(8, 2)))
        #expect(!p.contains(c(8, 8)))
        #expect(p.contains(c(21, 21)))
    }

    @Test func boundingRegionAndEmpty() {
        let p = GeoPolygon(rings: [[c(48.2, -114.5), c(49.0, -114.5), c(49.0, -113.2), c(48.2, -113.2)]])
        let r = p.boundingRegion
        #expect(abs(r.center.latitude - 48.6) < 1e-9)
        #expect(abs(r.longitudeDelta - 1.3) < 1e-9)
        #expect(GeoPolygon(rings: [[c(0, 0), c(1, 1)]]).isEmpty)   // fewer than three vertices is no ring
        #expect(!GeoPolygon(rings: []).contains(c(0, 0)))
    }

    @Test func areaPrefersBoundaryOverRegion() {
        let region = GeoRegion(center: c(5, 5), latitudeDelta: 10, longitudeDelta: 10)
        let triangle = GeoPolygon(rings: [[c(0, 0), c(0, 10), c(10, 0)]])
        #expect(DiscoveryArea(name: "x", region: region).contains(c(9, 9)))
        #expect(!DiscoveryArea(name: "x", region: region, boundary: triangle).contains(c(9, 9)))
        #expect(DiscoveryArea(name: "x", region: region, boundary: triangle).contains(c(2, 2)))
    }
}

// MARK: Names and elevations

@Suite struct DiscoveryNamesTests {
    @Test func equivalentNames() {
        #expect(DiscoveryNames.matches("Mount Cleveland", "Mt. Cleveland"))
        #expect(DiscoveryNames.matches("Mount Cleveland", "Mt Cleveland"))
        #expect(DiscoveryNames.matches("Mount Cleveland (Montana)", "Cleveland"))
        #expect(DiscoveryNames.matches("Bridalveil Fall", "Bridalveil Falls"))
        #expect(DiscoveryNames.matches("Lake McDonald", "McDonald Lake"))
        #expect(DiscoveryNames.matches("The Narrows", "Narrows"))
        #expect(DiscoveryNames.matches("Éclair Peak", "Eclair Peak"))
        #expect(DiscoveryNames.matches("St. Mary's Lake", "St Marys Lake"))
    }

    @Test func differentNames() {
        #expect(!DiscoveryNames.matches("Lake McDonald", "McDonald Creek"))
        #expect(!DiscoveryNames.matches("Mount Cleveland", "Mount Jackson"))
        #expect(!DiscoveryNames.matches("Upper Yosemite Fall", "Yosemite Falls"))
        #expect(!DiscoveryNames.matches("Mount Reynolds", "Lake Reynolds"))
        #expect(!DiscoveryNames.matches("", ""))
    }

    @Test func looseMatch() {
        #expect(DiscoveryNames.looselyMatches("Hidden Lake Overlook", "Hidden Lake"))
        #expect(DiscoveryNames.looselyMatches("Grinnell Glacier Trailhead", "Grinnell Glacier"))
        #expect(!DiscoveryNames.looselyMatches("Glacier Park Lodge", "Wild Goose Island"))
    }

    @Test func elevations() throws {
        #expect(ElevationParser.metres(from: "3190") == 3190)
        #expect(ElevationParser.metres(from: "3,190 m") == 3190)
        #expect(ElevationParser.metres(from: "2959.5") == 2959.5)
        #expect(ElevationParser.metres(from: "2 959 m") == 2959)
        #expect(try #require(ElevationParser.metres(from: "10466 ft")) - 3190.1 < 0.1)
        #expect(abs(try #require(ElevationParser.metres(from: "10,466 feet")) - 3190.1) < 0.1)
        #expect(ElevationParser.metres(from: "1234,5") == 1234.5)
        #expect(ElevationParser.metres(from: "unknown") == nil)
        #expect(ElevationParser.metres(inProse: "Clements Mountain (8,765 feet (2,672 m)) is located") == 2672)
        #expect(abs(try #require(ElevationParser.metres(inProse: "It rises to 8,765 feet.")) - 2671.6) < 0.1)
        #expect(ElevationParser.metres(inProse: "No figure here") == nil)
    }
}

// MARK: Merge

@Suite struct DiscoveryMergeTests {
    private func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }
    private let area = DiscoveryArea(name: "Park", region: GeoRegion(center: Coordinate(latitude: 48.6, longitude: -113.8), latitudeDelta: 0.8, longitudeDelta: 1.3))

    private func place(_ name: String, _ lat: Double, _ lon: Double, sources: Set<DiscoverySourceID> = [.openStreetMap], mentions: Int = 0,
                       ele: Double? = nil, links: [String] = []) -> DiscoveredPlace {
        DiscoveredPlace(name: name, coordinate: c(lat, lon), elevationMeters: ele, feature: .peak, sources: sources,
                        links: links.compactMap(URL.init(string:)), mentions: mentions)
    }

    @Test func mergesSameNameWithin1500m() {
        let a = place("Mount Cleveland", 48.9250, -113.8480, sources: [.openStreetMap], ele: 3190, links: ["https://a.example/1"])
        var b = place("Mt. Cleveland", 48.9300, -113.8490, sources: [.reddit], mentions: 7, links: ["https://b.example/2"])   // about 560 m
        b.why = "A big view."
        let merged = DiscoveryMerge.deduplicate([a, b])
        #expect(merged.count == 1)
        #expect(merged[0].sources == [.openStreetMap, .reddit])
        #expect(merged[0].mentions == 7)
        #expect(merged[0].elevationMeters == 3190)
        #expect(merged[0].name == "Mount Cleveland")        // the longer, OSM-sourced spelling
        #expect(merged[0].coordinate == c(48.9250, -113.8480))
        #expect(merged[0].why == "A big view.")
        #expect(merged[0].links.count == 2)
    }

    @Test func prefersWikipediaNameAndKeepsDistinctPlaces() {
        let osm = place("Cleveland Peak", 48.925, -113.848, sources: [.openStreetMap])
        let wiki = place("Mount Cleveland", 48.9252, -113.8481, sources: [.wikipedia], mentions: 1)   // under 60 m: same place whatever it is called
        let other = place("Mount Cleveland", 48.80, -113.50, sources: [.reddit])                       // 30 km away: a different place
        let merged = DiscoveryMerge.deduplicate([osm, wiki, other])
        #expect(merged.count == 2)
        let main = merged.first { $0.sources.contains(.wikipedia) }
        #expect(main?.name == "Mount Cleveland")
        #expect(main?.sources == [.wikipedia, .openStreetMap])
    }

    @Test func lakeAndCreekWithSameBaseStayApart() {
        let lake = place("Lake McDonald", 48.60, -113.90)
        let creek = place("McDonald Creek", 48.605, -113.89)      // about 1 km away, different name
        #expect(DiscoveryMerge.deduplicate([lake, creek]).count == 2)
    }

    @Test func dropsOutsideAreaAndUnlocated() {
        let inside = place("Inside Peak", 48.6, -113.8)
        let outside = place("Outside Peak", 50.0, -113.8)
        let nameless = DiscoveredPlace(name: "Nowhere", sources: [.reddit])
        let polygonArea = DiscoveryArea(name: "Park", region: area.region, boundary: GeoPolygon(rings: [[c(48.5, -113.9), c(48.5, -113.7), c(48.7, -113.7), c(48.7, -113.9)]]))
        let inBox = place("In Box Not Park", 48.9, -113.5)
        let settings = DiscoverySettings()
        #expect(DiscoveryMerge.merge([inside, outside, nameless, inBox], area: area, settings: settings).map(\.name).sorted() == ["In Box Not Park", "Inside Peak"])
        #expect(DiscoveryMerge.merge([inside, outside, nameless, inBox], area: polygonArea, settings: settings).map(\.name) == ["Inside Peak"])
    }

    private var sample: [DiscoveredPlace] {
        [
            place("Alpha", 48.60, -113.80, sources: [.wikipedia, .openStreetMap], mentions: 9, ele: 3000),
            place("Bravo", 48.61, -113.70, sources: [.openStreetMap], mentions: 0, ele: 2800),
            place("Charlie", 48.62, -113.60, sources: [.reddit], mentions: 2),
            place("Delta", 48.63, -113.50, sources: [.wikipedia], mentions: 1, ele: 2000),
            place("Echo", 48.64, -113.90, sources: [.openStreetMap], mentions: 0, ele: 1500),
            place("Foxtrot", 48.65, -113.95, sources: [.openStreetMap, .reddit], mentions: 4),
        ]
    }

    @Test func popularRanking() {
        let r = DiscoveryMerge.rank(sample, preference: .popular).map(\.name)
        #expect(r == ["Alpha", "Foxtrot", "Charlie", "Delta", "Bravo", "Echo"])
    }

    @Test func uniqueRanking() {
        let r = DiscoveryMerge.rank(sample, preference: .unique).map(\.name)
        #expect(r == ["Bravo", "Echo", "Delta", "Charlie", "Foxtrot", "Alpha"])
    }

    @Test func mixedInterleavesWithoutRepeats() {
        let r = DiscoveryMerge.rank(sample, preference: .mixed).map(\.name)
        #expect(r.count == 6 && Set(r).count == 6)
        #expect(r[0] == "Alpha")            // popular first
        #expect(r[1] == "Bravo")            // then the most unique
        #expect(r[2] == "Foxtrot")
    }

    @Test func orderDoesNotMatterAndCapApplies() {
        var settings = DiscoverySettings(preference: .popular, maxResults: 5)
        #expect(settings.maxResults == 5)
        let forward = DiscoveryMerge.merge(sample, area: area, settings: settings)
        let backward = DiscoveryMerge.merge(sample.reversed(), area: area, settings: settings)
        #expect(forward == backward)
        #expect(forward.count == 5)
        settings.maxResults = 1
        #expect(settings.maxResults == 5)
        settings.maxResults = 500
        #expect(settings.maxResults == 60)
    }
}

// MARK: Prompt

@Suite struct DiscoveryPromptTests {
    @Test func emptyPrefixLeavesInstructionsAlone() {
        #expect(DiscoveryPrompt.prefixed("Do the thing.", settings: DiscoverySettings()) == "Do the thing.")
        let blank = DiscoverySettings(promptPrefix: "  \n\t ", tasteSummary: "   ")
        #expect(DiscoveryPrompt.prefixed("Do the thing.", settings: blank) == "Do the thing.")
    }

    @Test func prependsPrefixAndTaste() {
        let s = DiscoverySettings(promptPrefix: "Moody coastal light", tasteSummary: "Haystack Rock, Cannon Beach")
        let out = DiscoveryPrompt.prefixed("Do the thing.", settings: s)
        #expect(out.hasSuffix("\n\nDo the thing."))
        #expect(out.contains("Moody coastal light"))
        #expect(out.contains("Haystack Rock, Cannon Beach"))
        #expect(out.range(of: "Moody")!.lowerBound < out.range(of: "Haystack")!.lowerBound)
    }

    @Test func clipsAndSanitises() {
        let long = String(repeating: "a", count: 900)
        let s = DiscoverySettings(promptPrefix: "line one\nline\ttwo\u{0007}\u{200B}end " + long, tasteSummary: String(repeating: "b", count: 900))
        let out = DiscoveryPrompt.prefixed("X", settings: s)
        #expect(!out.dropLast(1).contains("\t"))
        #expect(!out.contains("\u{0007}"))
        #expect(!out.contains("\u{200B}"))
        #expect(out.contains("line one line two end"))
        #expect(!out.contains(String(repeating: "a", count: DiscoveryPrompt.maximumPrefixLength)))   // clipped, and the leading words count too
        #expect(out.contains(String(repeating: "b", count: DiscoveryPrompt.maximumTasteLength)))
        #expect(!out.contains(String(repeating: "b", count: DiscoveryPrompt.maximumTasteLength + 1)))
        #expect(DiscoveryPrompt.clean("x\ny", limit: 400) == "x y")
    }

    @Test func tasteOnly() {
        let s = DiscoverySettings(tasteSummary: "Alpine lakes")
        #expect(DiscoveryPrompt.prefixed("Go.", settings: s).contains("Alpine lakes"))
    }
}

@Suite struct DiscoverySettingsTests {
    @Test func defaults() {
        let s = DiscoverySettings()
        #expect(s.enabledSources == [.reddit, .wikipedia, .wikivoyage, .openStreetMap])
        #expect(!s.enabledSources.contains(.google))
        #expect(s.preference == .mixed && s.maxResults == 20 && s.promptPrefix.isEmpty && s.tasteSummary == nil)
        #expect(DiscoverySettings(maxResults: 1).maxResults == 5)
        #expect(DiscoverySettings(maxResults: 99).maxResults == 60)
    }

    @Test func rawValuesAreStable() {
        #expect(DiscoverySourceID.allCases.map(\.rawValue) == ["appleMaps", "reddit", "wikipedia", "wikivoyage", "openStreetMap", "google"])
        #expect(DiscoveryPreference.allCases.map(\.rawValue) == ["popular", "unique", "mixed"])
    }
}
