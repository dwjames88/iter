import Foundation
import IterAI
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

/// Lone Pine as the live run found it: nothing tagged viewpoint, but peaks, arches and hills all around.
struct SparseLonePine {
    var scenario: LonePineScenario = {
        var s = LonePineScenario()
        s.osm.filtersByFeature = true
        s.osm.places = [
            candidate("Mount Whitney", 36.5785, -118.2923, kinds: [.peak], source: osmID, externalID: "node/21"),
            candidate("Lone Pine Peak", 36.5900, -118.2200, kinds: [.peak], source: osmID, externalID: "node/22"),
            candidate("Mobius Arch", 36.6150, -118.1250, kinds: [.arch], source: osmID, externalID: "node/23"),
            candidate("Lone Pine Lake", 36.5700, -118.2400, kinds: [.lake], source: osmID, externalID: "node/24"),
            candidate("Some Old Castle", 36.62, -118.0, kinds: [.castle], source: osmID, externalID: "node/25"),
        ]
        s.poi.places = []
        s.search.answers = [:]
        s.wikipedia.docs = [
            doc("Alabama Hills", "A range of low hills known for arches.", at: Coordinate(latitude: 36.6, longitude: -118.12)),
            doc("Sierra Nevada", "A big range.", at: Coordinate(latitude: 37.0, longitude: -119.0)),   // outside the area
        ]
        return s
    }()
}

@Suite("Widening to related subjects")
struct WideningTests {
    @Test func aStrictPassWithNothingWidensToRelatedSubjects() async {
        let s = SparseLonePine().scenario
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.widened)
        let names = Set(result.places.map(\.name))
        #expect(names.isSuperset(of: ["Mount Whitney", "Lone Pine Peak", "Mobius Arch", "Lone Pine Lake", "Alabama Hills"]))
        #expect(!names.contains("Sierra Nevada"))                                   // outside the area
        let whitney = result.places.first { $0.name == "Mount Whitney" }
        #expect(whitney?.rank.featureMatch.note == "related: peak")
        #expect(whitney?.rank.matchTier == .related)
        #expect(result.places.first { $0.name == "Mobius Arch" }?.rank.featureMatch.note == "related: arch")
        // The hills article names no kind: it is kept, as an unknown kind.
        #expect(result.places.first { $0.name == "Alabama Hills" }?.rank.matchTier == .related)
        // A castle is neither requested nor in the related list, so the widening pass never asks for it.
        #expect(!names.contains("Some Old Castle"))
        // Gazetteer asked twice: strict, then once for related kinds.
        #expect(s.osm.log.calls.count == 2)
        #expect(s.osm.log.calls[0] == "gazetteer:viewpoint")
        #expect(s.osm.log.calls[1].contains("peak") && s.osm.log.calls[1].contains("arch") && !s.osm.log.calls[1].contains("viewpoint"))
        assertGrounded(result.places, supplied: s.supplied)
    }

    @Test func strictMatchesAreNeverDisplacedByRelatedOnes() async {
        var s = SparseLonePine().scenario
        s.search.answers = ["viewpoints": [candidate("Quiet Lookout", 36.62, -118.05, kinds: [.viewpoint], source: mapkitSearchID, externalID: "mk")]]
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query, ordering: .popular))
        #expect(result.places.first?.name == "Quiet Lookout")                      // a lone single-source strict match leads famous peaks
        let tiers = result.places.map(\.rank.matchTier)
        #expect(tiers == tiers.sorted())
    }

    @Test func enoughStrictMatchesMeansNoSecondGazetteerQuery() async {
        var s = LonePineScenario()
        s.osm.places = (0..<6).map { candidate("Overlook \($0)", 36.60 + Double($0) * 0.004, -118.10, kinds: [.viewpoint], source: osmID, externalID: "n/\($0)") }
        s.osm.filtersByFeature = true
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(!result.widened)
        #expect(s.osm.log.calls.count == 1)
    }

    @Test func aGazetteerThatFailedIsNotAskedAgain() async {
        var s = SparseLonePine().scenario
        s.osm.script = Script(error: .http(status: 504, excerpt: nil))
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(s.osm.log.calls.count == 1)
        #expect(result.statuses.first { $0.source == osmID }?.state != nil)
    }

    @Test func deterministicTextNamesOfRelatedKindsAreLocatedToo() async {
        var s = SparseLonePine().scenario
        s.wikipedia.docs = [doc("Alabama Hills guide", "Hikers love Mobius Arch Overlook and Lone Pine Peak at dawn.")]
        s.geocoder.answers["mobius arch overlook"] = [GeocodeResult(name: "Mobius Arch Overlook", coordinate: Coordinate(latitude: 36.6155, longitude: -118.1255))]
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.places.contains { $0.name == "Mobius Arch Overlook" })
        assertGrounded(result.places, supplied: s.supplied)
    }

    @Test func relatednessTableIsSymmetricEnoughAndNeverSelfRelated() {
        for k in FeatureKind.allCases {
            #expect(!FeatureRelatedness.related(to: k).contains(k))
            #expect(!FeatureRelatedness.related(to: k).isEmpty)
        }
        #expect(Set(FeatureRelatedness.related(to: .viewpoint)).isSuperset(of: [.peak, .arch, .canyon, .lake, .waterfall, .glacier]))
        #expect(FeatureRelatedness.looksLikeNaturalFeature(title: "Alabama Hills"))
        #expect(FeatureRelatedness.looksLikeNaturalFeature(title: "Owens Valley"))
        #expect(!FeatureRelatedness.looksLikeNaturalFeature(title: "Lone Pine, California"))
    }

    @Test func droppedCandidatesAreReportedWithAReason() async {
        let s = LonePineScenario()
        var gz = s.osm
        gz.places.append(PlaceCandidate(name: "No Spot", source: osmID))
        var sc = s
        sc.osm = gz
        let result = await sc.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(result.dropped.contains(DroppedCandidate(name: "Far Away View", source: osmID, reason: .outsideArea)))
        #expect(result.dropped.contains(DroppedCandidate(name: "No Spot", source: osmID, reason: .noCoordinate)))
    }
}

@Suite("Boundary, labels and wording")
struct BoundaryAndLabelTests {
    func yosemiteWithSharedOverpassID(boundary: NamedBoundary?, geocodeRegion: GeoRegion?) -> YosemiteScenario {
        var s = YosemiteScenario()
        s.geocoder.answers = ["yosemite": [GeocodeResult(name: "Yosemite National Park", coordinate: Geo.yosemite, region: geocodeRegion)]]
        // The live Overpass boundary source has the same id as the Overpass gazetteer.
        s.boundary = FakeBoundary(descriptor: descriptor(osmID, "OpenStreetMap (Overpass)", kinds: [.boundary]), answer: boundary)
        return s
    }

    @Test func aParkNameAsksTheBoundaryProviderAndShowsItsStatusBesideTheGazetteer() async {
        let nb = NamedBoundary(name: "Yosemite National Park", polygon: YosemiteScenario.triangle, citation: citation(osmID, "b"))
        let s = yosemiteWithSharedOverpassID(boundary: nb, geocodeRegion: nil)
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: "waterfalls in Yosemite National Park"))
        #expect(s.boundary.log.calls == ["boundary:Yosemite National Park"])
        #expect(result.area?.hasRealBoundary == true)
        let rows = result.statuses.filter { $0.source == osmID }
        #expect(Set(rows.map(\.role)) == [.boundary, .gazetteer])                // one source, two roles, two rows
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(rows.first { $0.role == .boundary }?.state == .found(1))
    }

    @Test func noOutlineGivesAnHonestParkBoxNotATown() async {
        let s = yosemiteWithSharedOverpassID(boundary: nil, geocodeRegion: nil)
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: "waterfalls in Yosemite National Park"))
        #expect(result.area?.basis == .parkBox(radiusKm: 50))
        #expect(result.area?.basis.label == "area box, no outline found")
        #expect(abs((result.area?.area.region.latitudeDelta ?? 0) / 2 * 111 - 50) < 1)
        #expect(result.statuses.first { $0.role == .boundary }?.state == .empty)

        let region = GeoRegion(center: Geo.yosemite, latitudeDelta: 0.2, longitudeDelta: 0.25)
        let s2 = yosemiteWithSharedOverpassID(boundary: nil, geocodeRegion: region)
        let r2 = await s2.engine(model: nil).discover(DiscoveryRequest(text: "waterfalls in Yosemite National Park"))
        #expect(r2.area?.basis == .parkBox(radiusKm: nil))
        #expect(r2.area?.area.region == region)                                  // the geocoder's own region, even when small
    }

    @Test func aFailingBoundarySourceStillShowsItsStatus() async {
        var s = yosemiteWithSharedOverpassID(boundary: nil, geocodeRegion: nil)
        s.boundary.script = Script(error: .http(status: 504, excerpt: nil))
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: "waterfalls in Yosemite National Park"))
        guard case .failed? = result.statuses.first(where: { $0.role == .boundary })?.state else { Issue.record("no boundary failure row"); return }
        #expect(result.area?.basis == .parkBox(radiusKm: 50))
    }

    @Test func forestMonumentWildernessAndRecreationAreaNamesAskForOutlines() {
        for n in ["Inyo National Forest", "Devils Postpile National Monument", "John Muir Wilderness", "Mono Basin National Scenic Area",
                  "Lake Mead National Recreation Area", "Point Reyes National Seashore"] {
            #expect(AreaResolver.looksLikeArea(n), "\(n)")
        }
    }

    @Test func labelsDistinguishNoModelFromAnUnavailableOne() async {
        let s = LonePineScenario()
        let none = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(none.planOrigin == .basicNoModel)
        #expect(none.planOrigin.label == "Basic search: AI not set up")
        #expect(none.statuses.first { $0.source == FixedSources.ai }?.state == .unavailable("Basic search: AI not set up"))
        let off = await s.engine(model: FakeModel(availability: .unavailable(.deviceNotEligible))).discover(DiscoveryRequest(text: LonePineScenario.query))
        #expect(off.planOrigin == .basic(reason: .deviceNotEligible))
        #expect(off.planOrigin.label == "Basic search: AI unavailable (this device cannot run Apple Intelligence)")
        #expect(PlanOrigin.basicNoModel.isBasic && PlanOrigin.basic(reason: nil).isBasic && !PlanOrigin.ai.isBasic)
    }

    @Test func templateWhyLineIsSingularForOnePhoto() async {
        var s = LonePineScenario()
        s.photos.counts = ["36.590,-118.120": 1]
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        let p = result.places.first { $0.name == "Whitney Portal Overlook" }
        #expect(p?.photoCount == 1)
        #expect(p?.why?.text.contains("1 geotagged photo nearby") == true)
        #expect(p?.why?.text.contains("1 geotagged photos") == false)
        #expect(p?.rank.evidence.note.contains("1 geotagged photo,") == true)
    }
}
