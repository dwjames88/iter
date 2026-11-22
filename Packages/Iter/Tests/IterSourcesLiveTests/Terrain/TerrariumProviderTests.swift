import Foundation
import Synchronization
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

#if canImport(ImageIO) && canImport(CoreGraphics)
private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let swiss = Coordinate(latitude: 46.5586, longitude: 8.5610)

private func tileFixtureStub() throws -> StubHTTPClient {
    let http = StubHTTPClient()
    http.on(urlContaining: "/terrarium/12/702/1600.png", reply: .ok(try Fixtures.data("Terrarium/terrarium-12-702-1600-W.png")))
    http.on(urlContaining: "/terrarium/12/2145/1448.png", reply: .ok(try Fixtures.data("Terrarium/terrarium-12-2145-1448-S.png")))
    return http
}

/// Counts requests in flight.
private final class ConcurrencyProbe: HTTPClient {
    private let state = Mutex((inFlight: 0, maxInFlight: 0, total: 0))
    var maxInFlight: Int { state.withLock { $0.maxInFlight } }
    var total: Int { state.withLock { $0.total } }

    func send(_ request: SourceRequest) async throws -> SourceResponse {
        state.withLock { $0.inFlight += 1; $0.total += 1; $0.maxInFlight = max($0.maxInFlight, $0.inFlight) }
        defer { state.withLock { $0.inFlight -= 1 } }
        try await Task.sleep(for: .milliseconds(10))
        throw SourceError.http(status: 404, excerpt: nil)
    }
}

@Suite("TerrariumProvider elevation")
struct TerrariumElevationTests {
    @Test func whitneyAndTheSwissAlpsMatchTheReference() async throws {
        let http = try tileFixtureStub()
        let provider = TerrariumTerrainProvider(http: http, clock: ManualSourceClock(now: w4ISODate("2026-11-22T15:00:00Z")))
        let w = try await provider.elevation(at: whitney)
        let s = try await provider.elevation(at: swiss)
        // Fixtures/README "Terrarium result": W bilinear 4412.951 m, S bilinear 2106.750 m.
        #expect(abs(w.value - 4412.951148095674) < 0.001)
        #expect(abs(s.value - 2106.7497047674883) < 0.001)
        #expect(w.provenance.source == .terrariumTiles)
        #expect(w.provenance.model == "Terrarium z12, bilinear")
        #expect(w.provenance.licence.key == LicenceKey.terrainTiles)
        #expect(http.requests.map(\.url.absoluteString) == [
            "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/702/1600.png",
            "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/2145/1448.png"])
    }

    @Test func decodedTilesAreKeptInMemory() async throws {
        let http = try tileFixtureStub()
        let provider = TerrariumTerrainProvider(http: http)
        _ = try await provider.elevation(at: whitney)
        _ = try await provider.elevation(at: Coordinate(latitude: 36.58, longitude: -118.29))
        #expect(http.requests.count == 1)
    }

    @Test func rawTilesGoThroughTheBlobCache() async throws {
        let cache = InMemoryBlobCache()
        let first = try tileFixtureStub()
        _ = try await TerrariumTerrainProvider(http: first, blobCache: cache).elevation(at: whitney)
        #expect(first.requests.count == 1)
        #expect(cache.count == 1)
        let second = StubHTTPClient()   // would 404 on any request
        let again = try await TerrariumTerrainProvider(http: second, blobCache: cache).elevation(at: whitney)
        #expect(second.requests.isEmpty)
        #expect(abs(again.value - 4412.951148095674) < 0.001)
    }

    @Test func aMissingTileIsOutsideCoverage() async throws {
        await #expect(throws: SourceError.outsideCoverage) {
            try await TerrariumTerrainProvider(http: StubHTTPClient()).elevation(at: Coordinate(latitude: 10, longitude: 10))
        }
        await #expect(throws: SourceError.outsideCoverage) {
            try await TerrariumTerrainProvider(http: StubHTTPClient()).elevation(at: Coordinate(latitude: 89, longitude: 10))
        }
    }

    @Test func serverErrorsAndCorruptTilesAreReported() async throws {
        let broken = StubHTTPClient()
        broken.on(urlContaining: "terrarium", reply: .status(500))
        await #expect(throws: SourceError.http(status: 500, excerpt: "")) {
            try await TerrariumTerrainProvider(http: broken).elevation(at: whitney)
        }
        let junk = StubHTTPClient()
        junk.on(urlContaining: "terrarium", reply: .ok(Data("not a png".utf8)))
        do {
            _ = try await TerrariumTerrainProvider(http: junk).elevation(at: whitney)
            Issue.record("expected a decoding error")
        } catch let e as SourceError {
            guard case .decoding = e else { Issue.record("wrong error \(e)"); return }
        }
    }
}

@Suite("TerrariumProvider horizon")
struct TerrariumHorizonTests {
    @Test func tileSelection() {
        let near = TerrariumTerrainProvider.tiles(around: whitney, radiusM: 6000, zoom: 12)
        #expect(near.zoom == 12)
        #expect(near.tiles.contains(TileCoordinate(zoom: 12, x: 702, y: 1600)))
        #expect((4...16).contains(near.tiles.count))
        let far = TerrariumTerrainProvider.tiles(around: whitney, radiusM: 40_000, zoom: 10)
        #expect(far.zoom == 10)
        #expect(far.tiles.contains(TileCoordinate(zoom: 10, x: 175, y: 400)))
        #expect((4...16).contains(far.tiles.count))
        // Narrow tiles near the pole: the zoom is lowered rather than fetching dozens of tiles.
        let polar = TerrariumTerrainProvider.tiles(around: Coordinate(latitude: 78, longitude: 15), radiusM: 40_000, zoom: 10)
        #expect(polar.tiles.count <= 16 && polar.zoom < 10)
        // The antimeridian: columns wrap instead of running off the map.
        let seam = TerrariumTerrainProvider.tiles(around: Coordinate(latitude: 0, longitude: 179.99), radiusM: 6000, zoom: 12)
        #expect(seam.tiles.contains { $0.x == 4095 } && seam.tiles.contains { $0.x == 0 })
    }

    @Test func horizonWithOnlyTheWhitneyTileAvailable() async throws {
        let http = try tileFixtureStub()
        let clock = ManualSourceClock(now: w4ISODate("2026-11-22T15:00:00Z"))
        let provider = TerrariumTerrainProvider(http: http, clock: clock)
        let h = try await provider.horizon(at: whitney, azimuthStep: 5)
        let values = h.value.elevationsDegrees
        #expect(values.count == 72)
        #expect(h.value.azimuthStepDegrees == 5)
        #expect(values.allSatisfy { $0.isFinite })
        let near = TerrariumTerrainProvider.tiles(around: whitney, radiusM: 6000, zoom: 12).tiles.count
        let far = TerrariumTerrainProvider.tiles(around: whitney, radiusM: 40_000, zoom: 10).tiles.count
        let total = near + far
        #expect(h.provenance.model?.contains("tiles 1 of \(total)") == true)
        #expect(h.provenance.model?.contains("coverage reduced: \(total - 1) tiles unavailable") == true)
        #expect(h.provenance.source == .terrariumTiles)
        // Every tile was asked for at most once, with the concurrency cap honoured below.
        let urls = http.requests.map(\.url.absoluteString)
        #expect(Set(urls).count == urls.count && urls.count == total)
    }

    @Test func horizonStepsAndRefusals() async throws {
        let http = try tileFixtureStub()
        let provider = TerrariumTerrainProvider(http: http)
        let h10 = try await provider.horizon(at: whitney, azimuthStep: 10)
        #expect(h10.value.elevationsDegrees.count == 36)
        await #expect(throws: SourceError.invalidRequest("azimuth step 7.0 does not divide 360 degrees into a whole count")) {
            try await provider.horizon(at: whitney, azimuthStep: 7)
        }
        // No tile anywhere: honest failure, not a made-up flat horizon.
        await #expect(throws: SourceError.outsideCoverage) {
            try await TerrariumTerrainProvider(http: StubHTTPClient()).horizon(at: Coordinate(latitude: 10, longitude: 10), azimuthStep: 5)
        }
        let broken = StubHTTPClient()
        broken.on(urlContaining: "terrarium", reply: .status(500))
        await #expect(throws: SourceError.http(status: 500, excerpt: "")) {
            try await TerrariumTerrainProvider(http: broken).horizon(at: whitney, azimuthStep: 5)
        }
    }

    @Test func tilesAreFetchedWithBoundedConcurrency() async throws {
        let probe = ConcurrencyProbe()
        let provider = TerrariumTerrainProvider(http: probe)
        _ = try? await provider.horizon(at: whitney, azimuthStep: 5)
        #expect(probe.total >= 8)
        #expect(probe.maxInFlight <= SourceCatalogue.terrariumTiles.policy.maxConcurrent)
        #expect(probe.maxInFlight > 1)
    }

    /// The summit and its surroundings from the recorded tile only: rays stay inside the 7.8 km tile for the first 700 m to a few km.
    @Test func summitHorizonFromTheRecordedTile() throws {
        let png = try Fixtures.data("Terrarium/terrarium-12-702-1600-W.png")
        let tile = try TerrariumTile(coordinate: TileCoordinate(zoom: 12, x: 702, y: 1600), png: png, decoder: ImageIOPNGDecoder())
        let sampler: (Coordinate) -> Double? = { tile.bilinearElevation(latitude: $0.latitude, longitude: $0.longitude) }
        let ground = try #require(sampler(whitney))
        #expect(abs(ground - 4412.951148095674) < 0.001)
        let computer = HorizonComputer(azimuthStepDegrees: 5, maxDistanceM: 2000)
        let r = try #require(computer.compute(from: whitney, groundElevationM: ground, sampler: sampler))
        let v = r.profile.elevationsDegrees
        #expect(v.count == 72 && r.azimuthsWithoutData == 0)
        // Whitney is the highest point around: nothing rises meaningfully above the observer within 2 km. The 2 m eye and
        // the 30 m pixel smoothing allow a few tenths of a degree near the summit block.
        #expect(v.max()! < 3, "max \(v.max()!)")
        // Steep terrain falls away on most sides: the mean skyline is clearly below level.
        let mean = v.reduce(0, +) / Double(v.count)
        #expect(mean < -5, "mean \(mean)")
    }
}
#endif
