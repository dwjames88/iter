import Foundation
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

let wideArea = DiscoveryArea(name: "Lone Pine, California", region: GeoRegion(center: Geo.lonePine, latitudeDelta: 1, longitudeDelta: 1))

/// Verified candidates for tests. `GroundedCoordinate` has no public or internal initialiser, so the only way to get one is
/// to go through the verifier, exactly as the pipeline does.
func verified(_ cs: [PlaceCandidate], in area: DiscoveryArea = wideArea) -> [VerifiedCandidate] {
    cs.compactMap { CandidateVerifier.verifyStructured($0, in: area) }
}

@Suite("Verification")
struct VerificationTests {
    @Test func structuredCandidatesKeepTheirOwnCoordinateInsideTheArea() {
        let inside = candidate("Mobius Arch", 36.61, -118.12, kinds: [.arch], source: osmID, externalID: "node/1")
        let outside = candidate("Far Arch", 40.0, -110.0, kinds: [.arch], source: osmID, externalID: "node/2")
        let noCoordinate = PlaceCandidate(name: "No Spot", source: mapkitSearchID)
        let out = verified([inside, outside, noCoordinate])
        #expect(out.count == 1)
        #expect(out[0].coordinate.value == inside.coordinate)
        #expect(out[0].coordinate.source == osmID)
        #expect(out[0].coordinate.basis == .structuredSource)
    }

    @Test func aCandidateInsideTheBoxButOutsideThePolygonIsDropped() {
        let poly = AreaResolverTests.triangle
        let area = DiscoveryArea(name: "Yosemite", region: poly.boundingRegion, boundary: poly)
        let inPoly = candidate("Vernal Fall", 37.8, -119.55, kinds: [.waterfall], source: osmID, externalID: "n/1")
        let inBoxOnly = candidate("Corner Fall", 37.55, -119.78, kinds: [.waterfall], source: osmID, externalID: "n/2")
        #expect(area.region.contains(inBoxOnly.coordinate!))
        let out = verified([inPoly, inBoxOnly], in: area)
        #expect(out.map(\.name) == ["Vernal Fall"])
    }

    @Test func namesAreCleanedAndCoordinateLookingNamesRejected() {
        #expect(CandidateVerifier.cleanName("  Hidden Falls (37.7, -119.6) ") == "Hidden Falls")
        #expect(CandidateVerifier.cleanName("Hidden Falls 37.7512 -119.6234") == nil)
        #expect(CandidateVerifier.cleanName("X") == nil)
        #expect(CandidateVerifier.cleanName("Highway 120 Overlook") == "Highway 120 Overlook")
        #expect(CandidateVerifier.cleanName("   ") == nil)
    }

    @Test func statusConfirmedNeedsTwoIndependentSourcesOrAStableId() {
        let osm = verified([candidate("A Lake", 36.6, -118.1, kinds: [.lake], source: osmID, externalID: "n/1")])[0]
        #expect(osm.verification == .confirmed)                       // one structured source with a stable id
        let mk = verified([candidate("B Lake", 36.6, -118.1, kinds: [.lake], source: mapkitSearchID, externalID: "mk-1")])[0]
        #expect(mk.verification == .singleSource)                     // MapKit ids are not stable
        let wiki = verified([candidate("C Lake", 36.6, -118.1, kinds: [.lake], source: wikiID, externalID: "42")])[0]
        #expect(wiki.verification == .confirmed)
        let noID = verified([candidate("D Lake", 36.6, -118.1, kinds: [.lake], source: osmID)])[0]
        #expect(noID.verification == .singleSource)                   // no stable id, no confirmation
        // Two MapKit sources are one family, not two witnesses.
        let both = DiscoveryMerger.merge(verified([
            candidate("E Lake", 36.6, -118.1, kinds: [.lake], source: mapkitSearchID, externalID: "a"),
            candidate("E Lake", 36.6001, -118.1, kinds: [.lake], source: .applePOI, externalID: "b"),
        ]))
        #expect(both.count == 1 && both[0].verification == .singleSource)
        // Two families agree: confirmed.
        let agree = DiscoveryMerger.merge(verified([
            candidate("F Lake", 36.6, -118.1, kinds: [.lake], source: mapkitSearchID, externalID: "a"),
            candidate("F Lake", 36.6001, -118.1, kinds: [.lake], source: .applePOI, externalID: "b"),
            candidate("F Lake", 36.6002, -118.1, kinds: [.lake], source: .wikipedia),
        ]))
        #expect(agree.count == 1 && agree[0].verification == .confirmed)
    }

    @Test func nameOnlyCandidatesAreGeocodedWithANameMatchInsideTheArea() async {
        let hit = GeocodeResult(name: "Hidden Falls", coordinate: Coordinate(latitude: 36.6, longitude: -118.1))
        let wrongName = GeocodeResult(name: "Hidden Valley Road", coordinate: Coordinate(latitude: 36.6, longitude: -118.1))
        let outside = GeocodeResult(name: "Hidden Falls", coordinate: Coordinate(latitude: 10, longitude: 10))
        let named = ExtractedName(name: "Hidden Falls", featureHint: .waterfall, source: .wikipedia, citation: citation(.wikipedia, "Doc"), snippet: nil)

        func run(_ g: FakeGeocoder, search: [any PlaceSearchProvider] = []) async -> VerifiedCandidate? {
            await CandidateVerifier.verifyNamed(named, area: wideArea, geocoders: [g], placeSearch: search, timeout: { _ in .seconds(1) })
        }
        let ok = await run(FakeGeocoder(answers: ["hidden falls": [hit]]))
        #expect(ok?.coordinate.value == hit.coordinate)
        #expect(ok?.coordinate.basis == .geocodedName)
        #expect(ok?.sources == [.wikipedia, FakeGeocoder().descriptor.id])
        #expect(ok?.verification == .confirmed)                         // text plus an independent geocoder
        #expect(await run(FakeGeocoder(answers: ["hidden falls": [wrongName]])) == nil)
        #expect(await run(FakeGeocoder(answers: ["hidden falls": [outside]])) == nil)
        #expect(await run(FakeGeocoder()) == nil)

        // Place search is the second chance.
        let ps = FakePlaceSearch(descriptor: descriptor(mapkitSearchID, "MapKit", kinds: [.places]),
                                 answers: ["hidden": [candidate("Hidden Falls", 36.62, -118.05, kinds: [.waterfall], source: mapkitSearchID)]])
        let viaSearch = await run(FakeGeocoder(), search: [ps])
        #expect(viaSearch?.coordinate.value == Coordinate(latitude: 36.62, longitude: -118.05))
    }

    @Test func geocodeQueriesNeverCarryNumbersFromTheName() async {
        let g = FakeGeocoder(answers: [:])
        let named = ExtractedName(name: "Hidden Falls (37.7, -119.6)", featureHint: nil, source: .wikipedia, citation: citation(.wikipedia, "D"), snippet: nil)
        _ = await CandidateVerifier.verifyNamed(named, area: wideArea, geocoders: [g], placeSearch: [], timeout: { _ in .seconds(1) })
        #expect(g.log.calls == ["geocode:Hidden Falls, Lone Pine, California"])
    }
}

@Suite("Merge")
struct MergeTests {
    @Test func sameNameWithin1500mMergesDifferentNamesDoNot() {
        let out = DiscoveryMerger.merge(verified([
            candidate("Bridalveil Fall", 36.6000, -118.1, kinds: [.waterfall], source: osmID, externalID: "n/1"),
            candidate("Bridalveil Falls", 36.6100, -118.1, kinds: [.waterfall], source: mapkitSearchID, externalID: "m"),   // 1.1 km, same key
            candidate("Vernal Fall", 36.6100, -118.09, kinds: [.waterfall], source: osmID, externalID: "n/2"),           // 0.9 km, other name
        ]))
        #expect(out.count == 2)
        #expect(out.contains { DiscoveryNames.matches($0.name, "Bridalveil Fall") && $0.sources.count == 2 })
    }

    @Test func anyNameWithin60mMerges() {
        let out = DiscoveryMerger.merge(verified([
            candidate("Tunnel View", 36.6000, -118.1, kinds: [.viewpoint], source: osmID, externalID: "n/1"),
            candidate("Valley View Parking", 36.6003, -118.1, kinds: [.viewpoint], source: mapkitSearchID),   // about 33 m
            candidate("Far View", 36.6010, -118.1, kinds: [.viewpoint], source: mapkitSearchID),              // about 111 m
        ]))
        #expect(out.count == 2)
    }

    @Test func unionsSourcesCitationsMentionsAndTakesTheMostPreciseCoordinate() {
        let osm = candidate("Mobius Arch", 36.60100, -118.1, kinds: [.arch], source: osmID, externalID: "n/1", mentions: 0)
        let mk = candidate("Mobius Arch", 36.60120, -118.1, kinds: [.viewpoint], source: mapkitSearchID, externalID: "m", mentions: 0)
        let wiki = candidate("Mobius Arch", 36.60110, -118.1, kinds: [.arch], source: wikiID, externalID: "w", mentions: 1, snippet: "Mobius Arch is a natural arch.")
        let out = DiscoveryMerger.merge(verified([mk, wiki, osm]))
        #expect(out.count == 1)
        let m = out[0]
        #expect(m.coordinate.value == osm.coordinate)                         // OSM beats Wikipedia beats MapKit
        #expect(m.coordinate.source == osmID)
        #expect(Set(m.sources) == [osmID, mapkitSearchID, wikiID])
        #expect(m.citations.count == 3)
        #expect(m.mentionCount == 1)
        #expect(Set(m.featureKinds) == [.arch, .viewpoint])
        #expect(m.snippet == "Mobius Arch is a natural arch.")
        #expect(m.verification == .confirmed)
    }

    @Test func orderOfArrivalDoesNotMatter() {
        let items = [
            candidate("A Falls", 36.6, -118.1, kinds: [.waterfall], source: osmID, externalID: "1"),
            candidate("A Fall", 36.601, -118.1, kinds: [.waterfall], source: mapkitSearchID, externalID: "2"),
            candidate("B Peak", 36.7, -118.2, kinds: [.peak], source: osmID, externalID: "3"),
            candidate("C Lake", 36.5, -118.0, kinds: [.lake], source: .usgsGNIS, externalID: "4"),
        ]
        let reference = DiscoveryMerger.merge(verified(items))
        for _ in 0..<10 {
            #expect(DiscoveryMerger.merge(verified(items.shuffled())) == reference)
        }
    }

    @Test func mountAndLakeAndFallWordingsMatch() {
        #expect(DiscoveryNames.matches("Mount Cleveland", "Mt. Cleveland"))
        #expect(DiscoveryNames.matches("Lake McDonald", "McDonald Lake"))
        #expect(DiscoveryNames.matches("Bridalveil Fall", "Bridalveil Falls"))
        #expect(!DiscoveryNames.matches("Lake McDonald", "McDonald Creek"))
    }
}
