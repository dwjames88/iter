// Terrarium elevation tiles (Tilezen/Mapzen "joerd", served from AWS Open Data):
// 256 x 256 web-mercator PNG tiles, elevation_m = (R * 256 + G + B / 256) - 32768.
// This file is pure: tile maths, pixel to elevation, nearest and bilinear sampling, and a mosaic of tiles.
// Foundation only. PNG decoding lives behind `RGBImageDecoding` (see ImageIOPNGDecoder.swift).
import Foundation

public enum Terrarium {
    /// Pixels per tile edge.
    public static let tileSize = 256

    /// Elevation in metres from one Terrarium pixel.
    @inlinable
    public static func elevation(r: UInt8, g: UInt8, b: UInt8) -> Double {
        Double(r) * 256 + Double(g) + Double(b) / 256 - 32768
    }

    /// The pixel that stores `metres` (rounded down to 1/256 m). Clamps to the representable range
    /// -32768 ... 32767.996 m. Handy for building test images.
    public static func encode(elevation metres: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let steps = ((metres + 32768) * 256).rounded(.down)
        let clamped = min(max(steps, 0), 65535.0 * 256 + 255)
        let v = Int(clamped)
        return (UInt8(v >> 16), UInt8((v >> 8) & 255), UInt8(v & 255))
    }

    /// Web-mercator latitude limit (degrees); latitudes beyond it have no tile.
    public static let maxLatitude = 85.0511287798066

    /// The tile and fractional pixel position of a coordinate. Longitude wraps; latitude is clamped to the
    /// web-mercator limit. Pixel `i` covers `[i, i + 1)` and its centre is `i + 0.5`.
    public static func position(latitude: Double, longitude: Double, zoom: Int) -> TilePosition {
        let n = Double(1 << zoom)
        let lat = min(max(latitude, -maxLatitude), maxLatitude)
        var lon = (longitude + 180).truncatingRemainder(dividingBy: 360)
        if lon < 0 { lon += 360 }
        let fx = lon / 360 * n
        let latRad = lat * .pi / 180
        let fy = (1 - asinh(tan(latRad)) / .pi) / 2 * n
        let tx = min(max(Int(fx.rounded(.down)), 0), (1 << zoom) - 1)
        let ty = min(max(Int(fy.rounded(.down)), 0), (1 << zoom) - 1)
        return TilePosition(tile: TileCoordinate(zoom: zoom, x: tx, y: ty),
                            pixelX: (fx - Double(tx)) * Double(tileSize),
                            pixelY: (fy - Double(ty)) * Double(tileSize))
    }

    /// Latitude and longitude of the north-west corner of a tile.
    public static func northWestCorner(of tile: TileCoordinate) -> (latitude: Double, longitude: Double) {
        let n = Double(1 << tile.zoom)
        let lon = Double(tile.x) / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * Double(tile.y) / n))) * 180 / .pi
        return (lat, lon)
    }

    /// The URL of a tile on the AWS Open Data bucket.
    public static func url(for tile: TileCoordinate) -> URL {
        URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(tile.zoom)/\(tile.x)/\(tile.y).png")!
    }
}

/// A web-mercator tile index (slippy-map XYZ scheme: y grows southwards).
public struct TileCoordinate: Sendable, Hashable {
    public let zoom: Int
    public let x: Int
    public let y: Int
    public init(zoom: Int, x: Int, y: Int) {
        self.zoom = zoom
        self.x = x
        self.y = y
    }
}

/// A coordinate expressed as a tile plus a fractional pixel position inside it (0 ..< 256).
public struct TilePosition: Sendable, Equatable {
    public let tile: TileCoordinate
    public let pixelX: Double
    public let pixelY: Double
    public init(tile: TileCoordinate, pixelX: Double, pixelY: Double) {
        self.tile = tile
        self.pixelX = pixelX
        self.pixelY = pixelY
    }
}

/// One decoded Terrarium tile.
public struct TerrariumTile: Sendable, Equatable {
    public let coordinate: TileCoordinate
    public let image: RGB8Image

    public init(coordinate: TileCoordinate, image: RGB8Image) {
        self.coordinate = coordinate
        self.image = image
    }

    /// Decodes PNG bytes with the given decoder.
    public init(coordinate: TileCoordinate, png: Data, decoder: any RGBImageDecoding) throws {
        self.init(coordinate: coordinate, image: try decoder.decodeRGB8(png))
    }

    /// Elevation (m) of one pixel; nil when out of range.
    public func elevation(pixelX x: Int, pixelY y: Int) -> Double? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let p = image.rgb(x: x, y: y)
        return Terrarium.elevation(r: p.r, g: p.g, b: p.b)
    }

    /// Nearest-pixel elevation at a coordinate; nil when the coordinate is outside this tile.
    public func nearestElevation(latitude: Double, longitude: Double) -> Double? {
        let p = Terrarium.position(latitude: latitude, longitude: longitude, zoom: coordinate.zoom)
        guard p.tile == coordinate else { return nil }
        return elevation(pixelX: Int(p.pixelX), pixelY: Int(p.pixelY))
    }

    /// Bilinear elevation at a fractional pixel position (pixel centres at i + 0.5). Neighbours beyond the
    /// tile edge are clamped to the edge pixel; use `TerrariumMosaic` to read across tile borders.
    public func bilinearElevation(pixelX: Double, pixelY: Double) -> Double {
        let u = pixelX - 0.5, v = pixelY - 0.5
        let x0 = Int(u.rounded(.down)), y0 = Int(v.rounded(.down))
        let tx = u - Double(x0), ty = v - Double(y0)
        func at(_ x: Int, _ y: Int) -> Double {
            elevation(pixelX: min(max(x, 0), image.width - 1), pixelY: min(max(y, 0), image.height - 1)) ?? 0
        }
        let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
        let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
        return top * (1 - ty) + bottom * ty
    }

    /// Bilinear elevation at a coordinate; nil when the coordinate is outside this tile.
    public func bilinearElevation(latitude: Double, longitude: Double) -> Double? {
        let p = Terrarium.position(latitude: latitude, longitude: longitude, zoom: coordinate.zoom)
        guard p.tile == coordinate else { return nil }
        return bilinearElevation(pixelX: p.pixelX, pixelY: p.pixelY)
    }

    /// All pixels as elevations, row-major, top row first.
    public func elevations() -> [Double] {
        var out = [Double](repeating: 0, count: image.width * image.height)
        for i in 0..<out.count {
            out[i] = Terrarium.elevation(r: image.pixels[i * 3], g: image.pixels[i * 3 + 1], b: image.pixels[i * 3 + 2])
        }
        return out
    }
}

/// Several tiles of one zoom level addressed as one continuous raster, so sampling and gridding work across
/// tile borders (the horizon calculation needs 4 to 9 tiles around a spot).
public struct TerrariumMosaic: Sendable {
    public let zoom: Int
    private let tiles: [TileCoordinate: TerrariumTile]

    /// All tiles must share one zoom level; returns nil for an empty or mixed set.
    public init?(tiles: [TerrariumTile]) {
        guard let first = tiles.first, tiles.allSatisfy({ $0.coordinate.zoom == first.coordinate.zoom }) else { return nil }
        self.zoom = first.coordinate.zoom
        self.tiles = Dictionary(tiles.map { ($0.coordinate, $0) }, uniquingKeysWith: { _, new in new })
    }

    /// Elevation of the global pixel `(gx, gy)` at this zoom; longitude wraps, nil if the tile is missing
    /// or `gy` is off the map.
    public func elevation(globalPixelX gx: Int, globalPixelY gy: Int) -> Double? {
        let size = Terrarium.tileSize
        let tilesAcross = 1 << zoom
        guard gy >= 0, gy < tilesAcross * size else { return nil }
        let wrappedX = ((gx % (tilesAcross * size)) + tilesAcross * size) % (tilesAcross * size)
        let coord = TileCoordinate(zoom: zoom, x: wrappedX / size, y: gy / size)
        return tiles[coord]?.elevation(pixelX: wrappedX % size, pixelY: gy % size)
    }

    /// Nearest-pixel elevation at a coordinate; nil when its tile is not loaded.
    public func nearestElevation(latitude: Double, longitude: Double) -> Double? {
        let g = globalPixel(latitude: latitude, longitude: longitude)
        return elevation(globalPixelX: Int(g.x.rounded(.down)), globalPixelY: Int(g.y.rounded(.down)))
    }

    /// Bilinear elevation at a coordinate, reading neighbours across tile borders; nil if any of the four
    /// neighbouring pixels is in a tile that is not loaded.
    public func bilinearElevation(latitude: Double, longitude: Double) -> Double? {
        let g = globalPixel(latitude: latitude, longitude: longitude)
        let u = g.x - 0.5, v = g.y - 0.5
        let x0 = Int(u.rounded(.down)), y0 = Int(v.rounded(.down))
        let tx = u - Double(x0), ty = v - Double(y0)
        let maxY = (1 << zoom) * Terrarium.tileSize - 1
        guard let a = elevation(globalPixelX: x0, globalPixelY: min(max(y0, 0), maxY)),
              let b = elevation(globalPixelX: x0 + 1, globalPixelY: min(max(y0, 0), maxY)),
              let c = elevation(globalPixelX: x0, globalPixelY: min(max(y0 + 1, 0), maxY)),
              let d = elevation(globalPixelX: x0 + 1, globalPixelY: min(max(y0 + 1, 0), maxY))
        else { return nil }
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    /// Global (whole-map) fractional pixel coordinates of a latitude and longitude at this zoom.
    public func globalPixel(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let p = Terrarium.position(latitude: latitude, longitude: longitude, zoom: zoom)
        return (Double(p.tile.x * Terrarium.tileSize) + p.pixelX, Double(p.tile.y * Terrarium.tileSize) + p.pixelY)
    }

    /// The whole-tile rectangle `[minX...maxX] x [minY...maxY]` as one elevation grid (row-major, north first).
    /// Nil if any tile of the rectangle is missing.
    public func grid(minTileX: Int, maxTileX: Int, minTileY: Int, maxTileY: Int) -> ElevationGrid? {
        guard minTileX <= maxTileX, minTileY <= maxTileY else { return nil }
        let size = Terrarium.tileSize
        let width = (maxTileX - minTileX + 1) * size, height = (maxTileY - minTileY + 1) * size
        var values = [Double](repeating: 0, count: width * height)
        for ty in minTileY...maxTileY {
            for tx in minTileX...maxTileX {
                guard let tile = tiles[TileCoordinate(zoom: zoom, x: tx, y: ty)] else { return nil }
                let e = tile.elevations()
                for row in 0..<size {
                    let dst = ((ty - minTileY) * size + row) * width + (tx - minTileX) * size
                    let src = row * size
                    values.replaceSubrange(dst..<(dst + size), with: e[src..<(src + size)])
                }
            }
        }
        return ElevationGrid(zoom: zoom, originPixelX: minTileX * size, originPixelY: minTileY * size,
                             width: width, height: height, values: values)
    }
}

/// A rectangle of elevations in metres at one zoom level, row-major, north row first.
public struct ElevationGrid: Sendable, Equatable {
    public let zoom: Int
    /// Global pixel coordinates of the grid's top-left sample.
    public let originPixelX: Int
    public let originPixelY: Int
    public let width: Int
    public let height: Int
    public let values: [Double]

    public init(zoom: Int, originPixelX: Int, originPixelY: Int, width: Int, height: Int, values: [Double]) {
        self.zoom = zoom
        self.originPixelX = originPixelX
        self.originPixelY = originPixelY
        self.width = width
        self.height = height
        self.values = values
    }

    public subscript(column: Int, row: Int) -> Double { values[row * width + column] }

    /// Ground distance in metres covered by one pixel at a latitude (web-mercator, spherical Earth radius 6378137 m).
    public static func metresPerPixel(latitude: Double, zoom: Int) -> Double {
        2 * .pi * 6_378_137 * cos(latitude * .pi / 180) / (Double(Terrarium.tileSize) * Double(1 << zoom))
    }
}
