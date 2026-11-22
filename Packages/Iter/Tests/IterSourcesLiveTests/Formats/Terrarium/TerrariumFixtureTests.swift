import Testing
import Foundation
@testable import IterSourcesLive

#if canImport(ImageIO) && canImport(CoreGraphics)
// The recorded real tiles, decoded by ImageIO, must match the independent pure-Python decoder byte for byte.
private struct Reference: Decodable {
    struct Sample: Decodable { let x: Int; let y: Int; let r: UInt8; let g: UInt8; let b: UInt8; let elevation_m: Double }
    struct Tile: Decodable {
        let name: String; let file: String; let x: Int; let y: Int; let width: Int; let height: Int
        let latitude: Double; let longitude: Double
        let nearest_elevation_m_at_point: Double
        let bilinear_elevation_m_at_point: Double
        let checksum_fnv1a64: String
        let samples: [Sample]
    }
    let zoom: Int
    let tiles: [Tile]
}

private func fnv1a64(_ bytes: [UInt8]) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return String(format: "%016llx", h)
}

@Suite struct TerrariumFixtureTests {
    private func reference() throws -> Reference {
        try JSONDecoder().decode(Reference.self, from: Fixtures.data("Terrarium/reference.json"))
    }

    @Test func imageIOMatchesPythonReferenceExactly() throws {
        let ref = try reference()
        #expect(ref.tiles.count == 2)
        for t in ref.tiles {
            let image = try ImageIOPNGDecoder().decodeRGB8(try Fixtures.data("Terrarium/\(t.file)"))
            #expect(image.width == t.width && image.height == t.height)
            #expect(fnv1a64(image.pixels) == t.checksum_fnv1a64, "full-tile RGB checksum, tile \(t.name)")
            #expect(t.samples.count >= 20)
            for s in t.samples {
                let p = image.rgb(x: s.x, y: s.y)
                #expect(p.r == s.r && p.g == s.g && p.b == s.b, "tile \(t.name) pixel \(s.x),\(s.y)")
                #expect(Terrarium.elevation(r: p.r, g: p.g, b: p.b) == s.elevation_m)
            }
        }
    }

    @Test func elevationsAtTheTestPoints() throws {
        let ref = try reference()
        let decoder = ImageIOPNGDecoder()
        for t in ref.tiles {
            let tile = try TerrariumTile(coordinate: TileCoordinate(zoom: ref.zoom, x: t.x, y: t.y),
                                         png: try Fixtures.data("Terrarium/\(t.file)"), decoder: decoder)
            let nearest = try #require(tile.nearestElevation(latitude: t.latitude, longitude: t.longitude))
            let bilinear = try #require(tile.bilinearElevation(latitude: t.latitude, longitude: t.longitude))
            #expect(nearest == t.nearest_elevation_m_at_point)
            #expect(abs(bilinear - t.bilinear_elevation_m_at_point) < 1e-9)
            switch t.name {
            case "W": #expect(abs(nearest - 4412) < 1)   // SOURCES.md: 4412.4 m at z12 (Whitney's true summit ~4421 m)
            case "S": #expect(abs(nearest - 2107) < 1)   // SOURCES.md: 2107.0 m at z12
            default: Issue.record("unexpected tile \(t.name)")
            }
        }
    }

    @Test func comparisonWithUSGSEPQS() throws {
        struct EPQS: Decodable { let value: String }
        let epqs = try JSONDecoder().decode(EPQS.self, from: Fixtures.data("USGS/epqs-W.json"))
        let usgs = try #require(Double(epqs.value))
        let ref = try reference()
        let w = try #require(ref.tiles.first { $0.name == "W" })
        let diff = w.nearest_elevation_m_at_point - usgs
        // Terrarium z12 pixels are ~30 m across at this latitude and blend SRTM/3DEP, so metres of difference are normal.
        #expect(abs(usgs - 4416.2) < 0.1)
        #expect(abs(diff) < 10, "Terrarium minus EPQS at W = \(diff) m")
    }
}
#endif
