import Foundation
import Testing
@testable import IterModel

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

