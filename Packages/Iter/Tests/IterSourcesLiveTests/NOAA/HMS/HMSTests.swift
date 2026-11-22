import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

@Suite("HMS smoke mapping")
struct HMSMappingTests {
    static let summer: [HMSMapping.Placemark] = {
        try! HMSMapping.placemarks(from: Fixtures.data("HMS/hms_smoke20250815.kml"))
    }()
    static let day = w4ISODate("2025-08-15T00:00:00Z")

    @Test func countsPerDensityAndSatellite() {
        let p = Self.summer
        #expect(p.count == 56)
        #expect(p.filter { $0.density == .light }.count == 34)
        #expect(p.filter { $0.density == .medium }.count == 13)
        #expect(p.filter { $0.density == .heavy }.count == 9)
        #expect(p.filter { $0.satellite == "GOES-WEST" }.count == 45)
        #expect(p.filter { $0.satellite == "GOES-EAST" }.count == 11)
        #expect(p.allSatisfy { $0.shapes.count == 1 && $0.start != nil && $0.end != nil })
        // The first polygon in the file: Light, 12:00-14:20 UTC, GOES-West.
        #expect(p[0].density == .light)
        #expect(p[0].start == w4ISODate("2025-08-15T12:00:00Z"))
        #expect(p[0].end == w4ISODate("2025-08-15T14:20:00Z"))
    }

    @Test func emptyDay() throws {
        let p = try HMSMapping.placemarks(from: Fixtures.data("HMS/hms_smoke20261122.kml"))
        #expect(p.isEmpty)
        let a = HMSMapping.analysis(of: p, at: Coordinate(latitude: 40, longitude: -100), day: w4ISODate("2026-11-22T00:00:00Z"))
        #expect(a == SmokeAnalysis(density: .none, day: w4ISODate("2026-11-22T00:00:00Z"), polygonCount: 0))
    }

    @Test func pointInsideAHeavyPolygon() {
        // (61.9477, -112.1360) is inside Light, Medium and Heavy polygons: the densest wins.
        let a = HMSMapping.analysis(of: Self.summer, at: Coordinate(latitude: 61.9477, longitude: -112.1360), day: Self.day)
        #expect(a.density == .heavy)
        #expect(a.polygonCount == 56)
        #expect(a.validFrom == w4ISODate("2025-08-15T12:00:00Z"))
        #expect(a.validTo == w4ISODate("2025-08-15T14:20:00Z"))
    }

    @Test func pointInsideOnlyALightPolygon() {
        let a = HMSMapping.analysis(of: Self.summer, at: Coordinate(latitude: 62.5, longitude: -137.5), day: Self.day)
        #expect(a.density == .light)
        #expect(a.validFrom == w4ISODate("2025-08-15T12:00:00Z"))
        #expect(a.validTo == w4ISODate("2025-08-15T14:20:00Z"))
    }

    @Test func pointsOutsideEverything() {
        // Whitney and the Gulf of Mexico are clear on that day.
        for c in [Coordinate(latitude: 36.5785, longitude: -118.2923), Coordinate(latitude: 25, longitude: -90)] {
            let a = HMSMapping.analysis(of: Self.summer, at: c, day: Self.day)
            #expect(a.density == .none)
            #expect(a.polygonCount == 56)
            #expect(a.validFrom == nil && a.validTo == nil)
        }
    }

    @Test func timesAreYearDayOfYearHHMM() {
        #expect(HMSMapping.parseTime("2025227 1200UTC") == w4ISODate("2025-08-15T12:00:00Z"))
        #expect(HMSMapping.parseTime("2024366 2359UTC") == w4ISODate("2024-12-31T23:59:00Z"))
        #expect(HMSMapping.parseTime("2025001 0000UTC") == w4ISODate("2025-01-01T00:00:00Z"))
        #expect(HMSMapping.parseTime("2025227 1200") == nil)
        #expect(HMSMapping.parseTime("2025227 2500UTC") == nil)
    }

    @Test func holesAndMultiplePolygonsOnSyntheticKML() throws {
        let kml = """
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document><Folder><name>Smoke (Medium)</name>
        <Placemark><description><![CDATA[<div>Start Time: 2025227 1200UTC<br>End Time: 2025227 1300UTC<br>Satellite: X</div>]]></description>
        <MultiGeometry>
        <Polygon><outerBoundaryIs><LinearRing><coordinates>0,0,0 10,0,0 10,10,0 0,10,0 0,0,0</coordinates></LinearRing></outerBoundaryIs>
        <innerBoundaryIs><LinearRing><coordinates>4,4 6,4 6,6 4,6 4,4</coordinates></LinearRing></innerBoundaryIs></Polygon>
        <Polygon><outerBoundaryIs><LinearRing><coordinates>20,0 30,0 30,10 20,10 20,0</coordinates></LinearRing></outerBoundaryIs></Polygon>
        </MultiGeometry></Placemark></Folder></Document></kml>
        """
        let p = try HMSMapping.placemarks(from: Data(kml.utf8))
        #expect(p.count == 1)
        #expect(p[0].density == .medium)        // from the folder name: the description has no Density line
        #expect(p[0].shapes.count == 2)
        let day = w4ISODate("2025-08-15T00:00:00Z")
        func density(_ lat: Double, _ lon: Double) -> SmokeAnalysis.Density {
            HMSMapping.analysis(of: p, at: Coordinate(latitude: lat, longitude: lon), day: day).density
        }
        #expect(density(2, 2) == .medium)
        #expect(density(5, 5) == .none)         // inside the hole
        #expect(density(5, 25) == .medium)      // second polygon
        #expect(density(5, 15) == .none)
    }

    @Test func notXMLIsADecodingError() {
        #expect(throws: SourceError.self) { try HMSMapping.placemarks(from: Data("<html><body>nope".utf8)) }
        #expect(throws: SourceError.self) { try HMSMapping.placemarks(from: Data()) }
    }

    @Test func fileURLUsesTheUTCDay() {
        // 2025-08-15 23:30 UTC and 2025-08-16 00:30 UTC are different days even though both are the 15th in US time zones.
        #expect(HMSMapping.fileURL(forDay: w4ISODate("2025-08-15T23:30:00Z")).absoluteString
                == "https://satepsanone.nesdis.noaa.gov/pub/FIRE/web/HMS/Smoke_Polygons/KML/2025/08/hms_smoke20250815.kml")
        #expect(HMSMapping.fileURL(forDay: w4ISODate("2025-08-16T00:30:00Z")).lastPathComponent == "hms_smoke20250816.kml")
        #expect(HMSMapping.utcDay(of: w4ISODate("2025-08-15T23:30:00Z")) == w4ISODate("2025-08-15T00:00:00Z"))
    }
}

@Suite("HMS smoke provider")
struct HMSProviderTests {
    @Test func denseSmokeEndToEnd() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "hms_smoke20250815.kml", reply: .ok(try Fixtures.data("HMS/hms_smoke20250815.kml")))
        let clock = ManualSourceClock(now: w4ISODate("2025-08-16T11:00:00Z"))
        let r = try await HMSSmokeProvider(http: http, clock: clock)
            .smoke(at: Coordinate(latitude: 61.9477, longitude: -112.1360), on: w4ISODate("2025-08-15T20:15:00Z"))
        #expect(r.value.density == .heavy)
        #expect(r.value.day == w4ISODate("2025-08-15T00:00:00Z"))
        #expect(r.value.polygonCount == 56)
        #expect(r.provenance.source == .hmsSmoke)
        #expect(r.provenance.fetchedAt == w4ISODate("2025-08-16T11:00:00Z"))
        #expect(r.provenance.url?.lastPathComponent == "hms_smoke20250815.kml")
        #expect(http.requests.map(\.url.absoluteString) == [
            "https://satepsanone.nesdis.noaa.gov/pub/FIRE/web/HMS/Smoke_Polygons/KML/2025/08/hms_smoke20250815.kml"])
    }

    @Test func emptyDayIsNoneNotAnError() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "hms_smoke20261122.kml", reply: .ok(try Fixtures.data("HMS/hms_smoke20261122.kml")))
        let r = try await HMSSmokeProvider(http: http)
            .smoke(at: Coordinate(latitude: 40, longitude: -105), on: w4ISODate("2026-11-22T09:00:00Z"))
        #expect(r.value.density == .none)
        #expect(r.value.polygonCount == 0)
    }

    @Test func aDayNotYetPublishedIsNotPublished() async throws {
        let http = StubHTTPClient()   // no routes: every request is a 404
        do {
            _ = try await HMSSmokeProvider(http: http).smoke(at: Coordinate(latitude: 40, longitude: -105), on: w4ISODate("2026-11-23T09:00:00Z"))
            Issue.record("expected notPublished")
        } catch let e as SourceError {
            guard case .notPublished(let what) = e else { Issue.record("wrong error \(e)"); return }
            #expect(what.contains("hms_smoke20261123.kml"))
        }
    }

    @Test func outsideNorthAmericaMakesNoRequest() async throws {
        let http = StubHTTPClient()
        await #expect(throws: SourceError.outsideCoverage) {
            try await HMSSmokeProvider(http: http).smoke(at: Coordinate(latitude: 46.5586, longitude: 8.561), on: w4ISODate("2025-08-15T00:00:00Z"))
        }
        #expect(http.requests.isEmpty)
    }

    @Test func otherHTTPErrorsPassThrough() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "hms_smoke", reply: .status(500))
        await #expect(throws: SourceError.http(status: 500, excerpt: "")) {
            try await HMSSmokeProvider(http: http).smoke(at: Coordinate(latitude: 40, longitude: -105), on: w4ISODate("2025-08-15T00:00:00Z"))
        }
    }
}
