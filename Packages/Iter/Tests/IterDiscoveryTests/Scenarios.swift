import Foundation
import IterAI
import IterModel
import IterSources
@testable import IterDiscovery

func waitUntil(_ limit: Duration = .seconds(3), _ condition: @Sendable () -> Bool) async -> Bool {
    let end = ContinuousClock.now + limit
    while ContinuousClock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

let fastConfig = DiscoveryConfiguration(sourceTimeoutOverride: .milliseconds(400), planTimeout: .seconds(2), extractionTimeout: .seconds(2),
                                        explanationTimeout: .seconds(2))

/// "viewpoints near Lone Pine, California": OSM, MapKit POI and search, Wikipedia text, Commons photos, one geocoder.
struct LonePineScenario {
    var geocoder = FakeGeocoder(answers: [
        "mobius arch overlook": [GeocodeResult(name: "Mobius Arch Overlook", coordinate: Coordinate(latitude: 36.6150, longitude: -118.1250))],
        "lone pine": [GeocodeResult(name: "Lone Pine", coordinate: Geo.lonePine, formattedAddress: "Lone Pine, CA")],
    ])
    var osm = FakeGazetteer(descriptor: descriptor(osmID, "OpenStreetMap", kinds: [.gazetteer]), places: [
        candidate("Whitney Portal Overlook", 36.5900, -118.1200, kinds: [.viewpoint], source: osmID, externalID: "node/1"),
        candidate("Alabama Hills Viewpoint", 36.6000, -118.1100, kinds: [.viewpoint], source: osmID, externalID: "node/2"),
        candidate("Far Away View", 40.0, -110.0, kinds: [.viewpoint], source: osmID, externalID: "node/3"),
    ])
    var poi = FakeGazetteer(descriptor: descriptor(.applePOI, "Apple Maps POI", kinds: [.gazetteer]), places: [
        candidate("Alabama Hills Viewpoint", 36.60003, -118.1100, kinds: [.viewpoint], source: .applePOI, externalID: "mk-9"),
    ])
    var search = FakePlaceSearch(descriptor: descriptor(mapkitSearchID, "Apple Maps search", kinds: [.places]), answers: [
        "viewpoints": [candidate("Scenic Lookout", 36.6200, -118.0500, kinds: [.viewpoint], source: mapkitSearchID, externalID: "mk-1")],
    ])
    var wikipedia = FakeText(descriptor: descriptor(wikiID, "Wikipedia", kinds: [.textEvidence]), docs: [
        doc("Alabama Hills", "The Alabama Hills are known for arches. Mobius Arch Overlook is popular at sunrise."
            + " Hidden Falls (37.7, -119.6) is a rumour."),
        doc("Lone Pine Peak Viewpoint", "A viewpoint above town.", at: Coordinate(latitude: 36.5800, longitude: -118.0300)),
    ])
    var photos = FakePhotos(counts: ["36.590,-118.120": 20], defaultCount: 2)

    var providers: DiscoveryProviders {
        DiscoveryProviders(geocoders: [geocoder], gazetteers: [osm, poi], placeSearch: [search], textEvidence: [wikipedia], photoEvidence: [photos])
    }

    /// Every coordinate any fake can hand out.
    var supplied: Supplied {
        var s = Supplied()
        s.add(osm.places); s.add(poi.places); s.add(search.answers.values.flatMap { $0 })
        s.add(docs: wikipedia.docs)
        for v in geocoder.answers.values { s.add(v) }
        return s
    }

    static let query = "viewpoints near Lone Pine, California"

    func model(available: Bool = true) -> FakeModel {
        let m = FakeModel(availability: available ? .available : .unavailable(.appleIntelligenceNotEnabled))
        m.set {
            $0.json["QueryPlanDTO"] = #"{"areaMode":"named","areaText":"Lone Pine, California","features":["viewpoint"],"windows":[],"keywords":[],"exclude":[]}"#
            $0.json["ExtractionDTO"] = """
            {"places":[{"name":"Mobius Arch Overlook","documentIndex":0,"featureHint":"viewpoint"},
                       {"name":"Mobius Arch Overlook","documentIndex":1,"featureHint":"viewpoint"},
                       {"name":"Phantom Vista","documentIndex":1,"featureHint":"viewpoint"},
                       {"name":"Phantom Vista","documentIndex":0,"featureHint":"viewpoint"},
                       {"name":"Hidden Falls (37.7, -119.6)","documentIndex":0}]}
            """
            $0.respond = { prompt in
                // Echo a grounded sentence built from the facts: the place name and its area.
                let name = prompt.prompt.split(separator: "\n").first { $0.hasPrefix("Name: ") }.map { String($0.dropFirst(6)) } ?? "This place"
                return "\(name) is a viewpoint in Lone Pine, California."
            }
        }
        return m
    }

    func engine(model: FakeModel?, config: DiscoveryConfiguration = fastConfig) -> DiscoveryEngine {
        DiscoveryEngine(providers: providers, model: model, clock: ManualSourceClock(now: testNow), configuration: config)
    }
}

/// "waterfalls in Yosemite": a geocoder with a large region, a boundary provider with a real triangle.
struct YosemiteScenario {
    static let triangle = AreaResolverTests.triangle
    static let inside1 = Coordinate(latitude: 37.80, longitude: -119.55)
    static let inside2 = Coordinate(latitude: 37.70, longitude: -119.50)
    static let boxOnly = Coordinate(latitude: 37.55, longitude: -119.78)
    static let outsideAll = Coordinate(latitude: 38.5, longitude: -118.0)

    var geocoder = FakeGeocoder(answers: [
        "yosemite": [GeocodeResult(name: "Yosemite", coordinate: Geo.yosemite,
                                   region: GeoRegion(center: Geo.yosemite, latitudeDelta: 0.6, longitudeDelta: 0.7))],
    ])
    var boundary = FakeBoundary(answer: NamedBoundary(name: "Yosemite National Park", polygon: triangle, externalID: "relation/1643367",
                                                      areaKind: "national_park", citation: citation("fake.boundary", "Yosemite National Park boundary")))
    var osm = FakeGazetteer(descriptor: descriptor(osmID, "OpenStreetMap", kinds: [.gazetteer]), places: [
        PlaceCandidate(name: "Vernal Fall", coordinate: inside1, featureKinds: [.waterfall], source: osmID, externalID: "node/10", citations: [citation(osmID, "Vernal Fall")]),
        PlaceCandidate(name: "Nevada Fall", coordinate: inside2, featureKinds: [.waterfall], source: osmID, externalID: "node/11", citations: [citation(osmID, "Nevada Fall")]),
        PlaceCandidate(name: "Corner Fall", coordinate: boxOnly, featureKinds: [.waterfall], source: osmID, externalID: "node/12", citations: [citation(osmID, "Corner Fall")]),
        PlaceCandidate(name: "Distant Fall", coordinate: outsideAll, featureKinds: [.waterfall], source: osmID, externalID: "node/13", citations: [citation(osmID, "Distant Fall")]),
    ])

    var providers: DiscoveryProviders { DiscoveryProviders(geocoders: [geocoder], boundaries: [boundary], gazetteers: [osm]) }
    var supplied: Supplied {
        var s = Supplied(); s.add(osm.places); for v in geocoder.answers.values { s.add(v) }; return s
    }
    func engine(model: FakeModel?) -> DiscoveryEngine {
        DiscoveryEngine(providers: providers, model: model, clock: ManualSourceClock(now: testNow), configuration: fastConfig)
    }
}

@MainActor
func waitUntilMain(_ limit: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let end = ContinuousClock.now + limit
    while ContinuousClock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
