import Testing
import Foundation
@testable import IterSourcesLive

// Pure Terrarium maths on hand-built images: no ImageIO, no files.
@Suite struct TerrariumPureTests {
    @Test func elevationFormula() {
        #expect(Terrarium.elevation(r: 128, g: 0, b: 0) == 0)
        #expect(Terrarium.elevation(r: 0, g: 0, b: 0) == -32768)
        let expected: Double = 145.0 * 256.0 + 12.0 + 0.5 - 32768.0
        #expect(Terrarium.elevation(r: 145, g: 12, b: 128) == expected)
        let top: Double = 32767.0 + 255.0 / 256.0
        #expect(Terrarium.elevation(r: 255, g: 255, b: 255) == top)
    }

    @Test func encodeRoundTrips() {
        for metres in [-418.0, 0, 1.5, 2106.95703125, 4412.37109375, 8848.0] {
            let p = Terrarium.encode(elevation: metres)
            #expect(Terrarium.elevation(r: p.r, g: p.g, b: p.b) == metres)
        }
        let low = Terrarium.encode(elevation: -99999)
        #expect(Terrarium.elevation(r: low.r, g: low.g, b: low.b) == -32768)
        let top: Double = 32767.0 + 255.0 / 256.0
        let high = Terrarium.encode(elevation: 99999)
        #expect(Terrarium.elevation(r: high.r, g: high.g, b: high.b) == top)
    }

    @Test func tileMathForTheTestPoints() {
        let w = Terrarium.position(latitude: 36.5785, longitude: -118.2923, zoom: 12)
        #expect(w.tile == TileCoordinate(zoom: 12, x: 702, y: 1600))
        #expect(w.pixelX >= 0 && w.pixelX < 256 && w.pixelY >= 0 && w.pixelY < 256)
        let s = Terrarium.position(latitude: 46.5586, longitude: 8.5610, zoom: 12)
        #expect(s.tile == TileCoordinate(zoom: 12, x: 2145, y: 1448))
    }

    @Test func zoomZeroIsOneTileAndCentreIsMiddle() {
        let p = Terrarium.position(latitude: 0, longitude: 0, zoom: 0)
        #expect(p.tile == TileCoordinate(zoom: 0, x: 0, y: 0))
        #expect(abs(p.pixelX - 128) < 1e-9 && abs(p.pixelY - 128) < 1e-9)
        // Longitude wraps; latitude beyond the web-mercator limit clamps.
        let q = Terrarium.position(latitude: 89, longitude: 540, zoom: 2)
        #expect(q.tile.x == 0 && q.tile.y == 0)
    }

    @Test func cornerRoundTrip() {
        let tile = TileCoordinate(zoom: 12, x: 702, y: 1600)
        let nw = Terrarium.northWestCorner(of: tile)
        let p = Terrarium.position(latitude: nw.latitude - 1e-9, longitude: nw.longitude + 1e-9, zoom: 12)
        #expect(p.tile == tile)
        #expect(p.pixelX < 0.01 && p.pixelY < 0.01)
    }

    @Test func urlShape() {
        let url = Terrarium.url(for: TileCoordinate(zoom: 12, x: 702, y: 1600))
        #expect(url.absoluteString == "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/702/1600.png")
    }

    /// 4x4 image whose elevation is x * 10 metres.
    private func rampImage(width: Int = 4, height: Int = 4, base: Double = 0) -> RGB8Image {
        var px: [UInt8] = []
        for _ in 0..<height {
            for x in 0..<width {
                let e = Terrarium.encode(elevation: base + Double(x) * 10)
                px += [e.r, e.g, e.b]
            }
        }
        return RGB8Image(width: width, height: height, pixels: px)!
    }

    @Test func imageValidation() {
        #expect(RGB8Image(width: 2, height: 2, pixels: [0, 1, 2]) == nil)
        #expect(RGB8Image(width: 0, height: 2, pixels: []) == nil)
        #expect(RGB8Image(width: 2, height: 1, fill: (1, 2, 3))?.pixels == [1, 2, 3, 1, 2, 3])
    }

    @Test func pixelAndBilinearSampling() {
        let tile = TerrariumTile(coordinate: TileCoordinate(zoom: 0, x: 0, y: 0), image: rampImage())
        #expect(tile.elevation(pixelX: 2, pixelY: 1) == 20)
        #expect(tile.elevation(pixelX: 4, pixelY: 0) == nil)
        // Pixel centres at i + 0.5: exactly on a centre gives that pixel, halfway gives the mean.
        #expect(tile.bilinearElevation(pixelX: 1.5, pixelY: 1.5) == 10)
        #expect(tile.bilinearElevation(pixelX: 2.0, pixelY: 1.5) == 15)
        #expect(abs(tile.bilinearElevation(pixelX: 1.75, pixelY: 3.9) - 12.5) < 1e-9)
        // Beyond the first and last centres the edge pixel is held.
        #expect(tile.bilinearElevation(pixelX: 0.1, pixelY: 0.1) == 0)
        #expect(tile.bilinearElevation(pixelX: 3.9, pixelY: 0.1) == 30)
    }

    @Test func elevationsListIsRowMajor() {
        let tile = TerrariumTile(coordinate: TileCoordinate(zoom: 0, x: 0, y: 0), image: rampImage(width: 3, height: 2))
        #expect(tile.elevations() == [0, 10, 20, 0, 10, 20])
    }

    @Test func nearestAndBilinearByCoordinate() {
        // A zoom-0 tile with a 256-wide image whose elevation is the column index: column = (lon+180)/360*256.
        var px: [UInt8] = []
        for _ in 0..<256 { for x in 0..<256 { let e = Terrarium.encode(elevation: Double(x)); px += [e.r, e.g, e.b] } }
        let tile = TerrariumTile(coordinate: TileCoordinate(zoom: 0, x: 0, y: 0), image: RGB8Image(width: 256, height: 256, pixels: px)!)
        #expect(tile.nearestElevation(latitude: 0, longitude: 0) == 128)
        let b = tile.bilinearElevation(latitude: 0, longitude: 0)!
        #expect(abs(b - 127.5) < 1e-9)   // exactly on the corner between columns 127 and 128
        let other = TerrariumTile(coordinate: TileCoordinate(zoom: 1, x: 0, y: 0), image: tile.image)
        #expect(other.nearestElevation(latitude: 0, longitude: 100) == nil)
    }

    @Test func mosaicReadsAcrossTileBorders() throws {
        // Two side-by-side zoom-1 tiles (x = 0 and 1, y = 0); left is 100 m everywhere, right is 200 m.
        func flat(_ m: Double) -> RGB8Image {
            let e = Terrarium.encode(elevation: m)
            return RGB8Image(width: 256, height: 256, fill: (e.r, e.g, e.b))!
        }
        let left = TerrariumTile(coordinate: TileCoordinate(zoom: 1, x: 0, y: 0), image: flat(100))
        let right = TerrariumTile(coordinate: TileCoordinate(zoom: 1, x: 1, y: 0), image: flat(200))
        let mosaic = try #require(TerrariumMosaic(tiles: [left, right]))
        #expect(mosaic.elevation(globalPixelX: 255, globalPixelY: 10) == 100)
        #expect(mosaic.elevation(globalPixelX: 256, globalPixelY: 10) == 200)
        #expect(mosaic.elevation(globalPixelX: 512, globalPixelY: 10) == 100)   // longitude wraps
        #expect(mosaic.elevation(globalPixelX: 0, globalPixelY: 256) == nil)    // tile (0,1) not loaded
        #expect(mosaic.elevation(globalPixelX: 0, globalPixelY: -1) == nil)     // off the map
        // lon 0 is the shared border: bilinear is the mean of the two flat tiles.
        let mid = try #require(mosaic.bilinearElevation(latitude: 60, longitude: 0))
        #expect(abs(mid - 150) < 1e-9)
        #expect(mosaic.nearestElevation(latitude: 60, longitude: 10) == 200)
        #expect(mosaic.nearestElevation(latitude: -60, longitude: 10) == nil)

        let grid = try #require(mosaic.grid(minTileX: 0, maxTileX: 1, minTileY: 0, maxTileY: 0))
        #expect(grid.width == 512 && grid.height == 256)
        #expect(grid[255, 0] == 100 && grid[256, 255] == 200)
        #expect(mosaic.grid(minTileX: 0, maxTileX: 1, minTileY: 0, maxTileY: 1) == nil)
        #expect(TerrariumMosaic(tiles: []) == nil)
        #expect(TerrariumMosaic(tiles: [left, TerrariumTile(coordinate: TileCoordinate(zoom: 2, x: 0, y: 0), image: flat(1))]) == nil)
    }

    @Test func metresPerPixel() {
        // Equator, z0: 40075016.7 m / 256 px.
        let m = ElevationGrid.metresPerPixel(latitude: 0, zoom: 0)
        #expect(abs(m - 156543.03392804097) < 1e-6)
        #expect(abs(ElevationGrid.metresPerPixel(latitude: 36.5785, zoom: 12) - 30.7) < 0.1)
    }
}

#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics

// The layout logic of the ImageIO adapter, exercised with synthetic buffers (no PNG involved).
@Suite struct ImageIOLayoutTests {
    private func extract(_ bytes: [UInt8], bpp: Int, bpr: Int, info: CGBitmapInfo, alpha: CGImageAlphaInfo,
                         bitsPerComponent: Int = 8, model: CGColorSpaceModel? = .rgb, w: Int = 2, h: Int = 1) throws -> RGB8Image {
        try ImageIOPNGDecoder.extractRGB(bytes: bytes, width: w, height: h, bitsPerComponent: bitsPerComponent,
                                         bitsPerPixel: bpp, bytesPerRow: bpr, bitmapInfo: info, alphaInfo: alpha, colorModel: model)
    }

    @Test func rgb24() throws {
        let img = try extract([1, 2, 3, 4, 5, 6], bpp: 24, bpr: 6, info: [], alpha: .none)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
    }

    @Test func rowPaddingIsSkipped() throws {
        let img = try extract([1, 2, 3, 9, 9, 4, 5, 6, 9, 9], bpp: 24, bpr: 5, info: [], alpha: .none, w: 1, h: 2)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
    }

    @Test func rgba32BothOrders() throws {
        // RGBA in memory (big-endian word, alpha last).
        var img = try extract([1, 2, 3, 255, 4, 5, 6, 255], bpp: 32, bpr: 8, info: .byteOrder32Big, alpha: .premultipliedLast)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
        // RGBX with default order.
        img = try extract([1, 2, 3, 0, 4, 5, 6, 0], bpp: 32, bpr: 8, info: [], alpha: .noneSkipLast)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
        // ARGB in memory.
        img = try extract([255, 1, 2, 3, 255, 4, 5, 6], bpp: 32, bpr: 8, info: .byteOrder32Big, alpha: .first)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
        // Little-endian words: premultiplied-first is BGRA in memory, noneSkipLast is XBGR.
        img = try extract([3, 2, 1, 255, 6, 5, 4, 255], bpp: 32, bpr: 8, info: .byteOrder32Little, alpha: .premultipliedFirst)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
        img = try extract([0, 3, 2, 1, 0, 6, 5, 4], bpp: 32, bpr: 8, info: .byteOrder32Little, alpha: .noneSkipLast)
        #expect(img.pixels == [1, 2, 3, 4, 5, 6])
    }

    @Test func unsupportedLayoutsThrow() {
        #expect(throws: RGBImageDecodingError.unsupportedBitsPerComponent(16)) {
            try extract([UInt8](repeating: 0, count: 12), bpp: 48, bpr: 6, info: [], alpha: .none, bitsPerComponent: 16)
        }
        #expect(throws: RGBImageDecodingError.floatComponents) {
            try extract([UInt8](repeating: 0, count: 6), bpp: 24, bpr: 6, info: .floatComponents, alpha: .none)
        }
        #expect(throws: RGBImageDecodingError.unsupportedBitsPerPixel(8)) {
            try extract([0, 0], bpp: 8, bpr: 2, info: [], alpha: .none)
        }
        #expect(throws: RGBImageDecodingError.premultipliedAlphaChangedPixels) {
            try extract([1, 2, 3, 128, 4, 5, 6, 255], bpp: 32, bpr: 8, info: .byteOrder32Big, alpha: .premultipliedLast)
        }
        #expect(throws: RGBImageDecodingError.truncatedPixelData) {
            try extract([1, 2, 3], bpp: 24, bpr: 6, info: [], alpha: .none)
        }
        #expect(throws: RGBImageDecodingError.self) {
            try extract([0, 0], bpp: 8, bpr: 2, info: [], alpha: .none, model: .indexed)
        }
    }

    @Test func notAPNGThrows() {
        #expect(throws: RGBImageDecodingError.notAnImage) { try ImageIOPNGDecoder().decodeRGB8(Data([1, 2, 3, 4])) }
    }
}
#endif
