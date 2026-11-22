import Testing
import Foundation
import IterModel
import IterSources
@testable import IterSourcesLive

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
/// The recorded envelope: -118.40,36.50,-118.20,36.65.
private let envelopeW = DiscoveryArea(name: nil, region: GeoRegion(center: Coordinate(latitude: 36.575, longitude: -118.30),
                                                                    latitudeDelta: 0.15, longitudeDelta: 0.20))

@Suite("GNIS mapping")
struct GNISMappingTests {
    let d = SourceCatalogue.usgsGNIS

    @Test func fixtureHolds83FeaturesWith48MappablePeaks() throws {
        // 83 features: Summit 46, Range 22, Gap 6, Flat 5, Pillar 2, Plain 1, Ridge 1. Summit and Pillar map to peaks.
        let data = try Fixtures.data("GNIS/gnis-envelope-W.json")
        let page = try GNISMapping.page(from: data, area: envelopeW, features: [], descriptor: d, fetchedAt: t0)
        #expect(page.featureCount == 83)
        #expect(!page.exceededTransferLimit)
        #expect(page.candidates.count == 33)  // 48 summit/pillar rows share 33 distinct gaz_ids
        #expect(page.candidates.allSatisfy { $0.featureKinds == [.peak] })
    }

    @Test func mountWhitneyIsThere() throws {
        let data = try Fixtures.data("GNIS/gnis-envelope-W.json")
        let page = try GNISMapping.page(from: data, area: envelopeW, features: [.peak], descriptor: d, fetchedAt: t0)
        let m = try #require(page.candidates.first { $0.name == "Mount Whitney" })
        #expect(m.externalID == "gnis/269051")
        let c = try #require(m.coordinate)
        #expect(abs(c.latitude - 36.578575123) < 1e-6 && abs(c.longitude + 118.292434227) < 1e-6)
        #expect(m.source == .usgsGNIS)
        let cite = try #require(m.citations.first)
        #expect(cite.url?.absoluteString == "https://edits.nationalmap.gov/apps/gaz-domestic/public/summary/269051")
        #expect(cite.licence == d.licence)
        #expect(page.candidates.contains { $0.name == "Keeler Needle" })  // a Pillar
        #expect(!page.candidates.contains { $0.name == "Whitney Pass" })   // a Gap, not a canyon
    }

    @Test func requestedFeaturesFilter() throws {
        let data = try Fixtures.data("GNIS/gnis-envelope-W.json")
        let lakes = try GNISMapping.page(from: data, area: envelopeW, features: [.lake], descriptor: d, fetchedAt: t0)
        #expect(lakes.candidates.isEmpty)
    }

    @Test func featureClassMapping() {
        #expect(GNISMapping.kind(featureClass: "Summit", name: "X") == .peak)
        #expect(GNISMapping.kind(featureClass: "Pillar", name: "X") == .peak)
        #expect(GNISMapping.kind(featureClass: "Ridge", name: "X") == nil)
        #expect(GNISMapping.kind(featureClass: "Range", name: "X") == nil)
        #expect(GNISMapping.kind(featureClass: "Lake", name: "X") == .lake)
        #expect(GNISMapping.kind(featureClass: "Reservoir", name: "X") == .lake)
        #expect(GNISMapping.kind(featureClass: "Falls", name: "X") == .waterfall)
        #expect(GNISMapping.kind(featureClass: "Arch", name: "X") == .arch)
        #expect(GNISMapping.kind(featureClass: "Beach", name: "X") == .beach)
        #expect(GNISMapping.kind(featureClass: "Glacier", name: "X") == .glacier)
        #expect(GNISMapping.kind(featureClass: "Cave", name: "X") == .cave)
        #expect(GNISMapping.kind(featureClass: "Bridge", name: "X") == .bridge)
        #expect(GNISMapping.kind(featureClass: "Spring", name: "Hot Creek Springs") == .hotSpring)
        #expect(GNISMapping.kind(featureClass: "Spring", name: "Cold Spring") == nil)
        #expect(GNISMapping.kind(featureClass: "Valley", name: "Taylor Canyon") == .canyon)
        #expect(GNISMapping.kind(featureClass: "Gap", name: "Whitney Pass") == nil)
    }

    @Test func singlePointGeometryErrorsAndTransferLimit() throws {
        let json = """
        {"exceededTransferLimit":true,"features":[
         {"attributes":{"gaz_id":1,"gaz_name":"A Falls","gaz_featureclass":"Falls"},"geometry":{"x":-118.3,"y":36.57}},
         {"attributes":{"gaz_id":2,"gaz_name":"No Geometry","gaz_featureclass":"Falls"}}]}
        """
        let page = try GNISMapping.page(from: Data(json.utf8), area: envelopeW, features: [], descriptor: d, fetchedAt: t0)
        #expect(page.exceededTransferLimit && page.featureCount == 2)
        #expect(page.candidates.map(\.name) == ["A Falls"])
        #expect(page.candidates[0].coordinate == Coordinate(latitude: 36.57, longitude: -118.3))
        #expect(throws: SourceError.self) {
            try GNISMapping.page(from: Data(#"{"error":{"code":400,"message":"bad"}}"#.utf8), area: envelopeW, features: [], descriptor: d, fetchedAt: t0)
        }
    }
}

@Suite("GNIS provider")
struct GNISProviderTests {
    @Test func requestsTheEnvelopeAndMaps() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "carto.nationalmap.gov", reply: .ok(try Fixtures.data("GNIS/gnis-envelope-W.json")))
        let provider = GNISProvider(http: http, clock: ManualSourceClock(now: t0))
        let r = try await provider.candidates(in: envelopeW, features: [.peak], limit: 100)
        #expect(r.count == 33)
        #expect(http.requests.count == 1)
        #expect(http.requests[0].method == "GET")
        #expect(http.requests[0].url.absoluteString == "https://carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer/5/query?geometry=-118.40000,36.50000,-118.20000,36.65000&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=gaz_id,gaz_name,gaz_featureclass&returnGeometry=true&outSR=4326&f=json")
        let capped = try await provider.candidates(in: envelopeW, features: [.peak], limit: 5)
        #expect(capped.count == 5)
    }

    @Test func outsideUnitedStatesMakesNoRequest() async throws {
        let http = StubHTTPClient()
        let swiss = DiscoveryArea(name: nil, region: GeoRegion(center: Coordinate(latitude: 46.5586, longitude: 8.5610), latitudeDelta: 0.1, longitudeDelta: 0.1))
        await #expect(throws: SourceError.outsideCoverage) {
            try await GNISProvider(http: http).candidates(in: swiss, features: [.peak], limit: 10)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func followsExceededTransferLimitWithOffset() async throws {
        let page1 = #"{"exceededTransferLimit":true,"features":[{"attributes":{"gaz_id":1,"gaz_name":"One Falls","gaz_featureclass":"Falls"},"geometry":{"points":[[-118.3,36.57]]}}]}"#
        let page2 = #"{"features":[{"attributes":{"gaz_id":2,"gaz_name":"Two Falls","gaz_featureclass":"Falls"},"geometry":{"points":[[-118.31,36.58]]}}]}"#
        let http = StubHTTPClient()
        http.on({ $0.url.absoluteString.contains("resultOffset=1") }, reply: .ok(Data(page2.utf8)))
        http.on(urlContaining: "carto.nationalmap.gov", reply: .ok(Data(page1.utf8)))
        let r = try await GNISProvider(http: http).candidates(in: envelopeW, features: [.waterfall], limit: 10)
        #expect(r.map(\.name) == ["One Falls", "Two Falls"])
        #expect(http.requests.count == 2)
    }
}
