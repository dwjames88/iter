import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

@Suite("EPQS elevation")
struct EPQSTests {
    static let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
    static let swiss = Coordinate(latitude: 46.5586, longitude: 8.5610)

    @Test func mappingReadsTheStringValue() throws {
        let r = try EPQSMapping.elevation(from: Fixtures.data("USGS/epqs-W.json"))
        #expect(abs(r.elevationM - 4416.233886719) < 1e-9)
        #expect(r.resolutionM == 1)
    }

    @Test func outsideTheUSPlainTextIsOutsideCoverage() throws {
        #expect(throws: SourceError.outsideCoverage) { try EPQSMapping.elevation(from: Fixtures.data("USGS/epqs-S.txt")) }
    }

    @Test func noDataValueIsOutsideCoverage() {
        let nodata = #"{"location":{"x":-110,"y":30},"locationId":0,"value":"-1000000","rasterId":-1,"resolution":1}"#
        #expect(throws: SourceError.outsideCoverage) { try EPQSMapping.elevation(from: Data(nodata.utf8)) }
        let numeric = #"{"value":-1000000}"#
        #expect(throws: SourceError.outsideCoverage) { try EPQSMapping.elevation(from: Data(numeric.utf8)) }
    }

    @Test func garbageIsADecodingError() {
        for text in ["<html>oops</html>", #"{"value":"abc"}"#, "{}", ""] {
            do {
                _ = try EPQSMapping.elevation(from: Data(text.utf8))
                Issue.record("expected a throw for \(text)")
            } catch let e as SourceError {
                guard case .decoding = e else { Issue.record("expected decoding for \(text), got \(e)"); continue }
            } catch { Issue.record("wrong error type") }
        }
    }

    @Test func providerAtWhitney() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "epqs.nationalmap.gov/v1/json", reply: .ok(try Fixtures.data("USGS/epqs-W.json")))
        let clock = ManualSourceClock(now: w4ISODate("2026-11-22T14:00:00Z"))
        let r = try await USGSElevationProvider(http: http, clock: clock).elevation(at: Self.whitney)
        #expect(abs(r.value - 4416.233886719) < 1e-9)
        #expect(r.provenance.source == .usgsEPQS)
        #expect(r.provenance.model == "USGS 3DEP DEM, 1 m resolution")
        #expect(http.requests.map(\.url.absoluteString) == [
            "https://epqs.nationalmap.gov/v1/json?x=-118.2923&y=36.5785&units=Meters&wkid=4326"])
    }

    @Test func switzerlandIsRefusedBeforeAnyRequest() async throws {
        let http = StubHTTPClient()
        await #expect(throws: SourceError.outsideCoverage) { try await USGSElevationProvider(http: http).elevation(at: Self.swiss) }
        #expect(http.requests.isEmpty)
    }

    @Test func aUSPointThatEPQSRefusesIsOutsideCoverage() async throws {
        // A point inside our coarse US shape that EPQS still answers with the plain-text failure (coast, border waters).
        let http = StubHTTPClient()
        http.on(urlContaining: "epqs", reply: .ok(try Fixtures.data("USGS/epqs-S.txt")))
        await #expect(throws: SourceError.outsideCoverage) { try await USGSElevationProvider(http: http).elevation(at: Self.whitney) }
    }

    @Test func horizonThrowsNoSourceUnlessInjected() async throws {
        let http = StubHTTPClient()
        await #expect(throws: SourceError.noSource) {
            try await USGSElevationProvider(http: http).horizon(at: Self.whitney, azimuthStep: 5)
        }
    }

    @Test func horizonDelegatesToAnInjectedSource() async throws {
        struct FlatTerrain: TerrainProvider {
            let descriptor = SourceCatalogue.terrariumTiles
            func elevation(at coordinate: Coordinate) async throws -> Sourced<Double> { throw SourceError.noSource }
            func horizon(at coordinate: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile> {
                Sourced(value: .flat, provenance: descriptor.provenance(fetchedAt: Date(timeIntervalSince1970: 0)))
            }
        }
        let provider = USGSElevationProvider(http: StubHTTPClient(), horizonSource: FlatTerrain())
        let h = try await provider.horizon(at: Self.whitney, azimuthStep: 5)
        #expect(h.value.elevationsDegrees.count == 72)
        #expect(h.provenance.source == .terrariumTiles)   // honest: the horizon is Terrarium's, not USGS's
    }
}
