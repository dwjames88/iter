// A plain 8-bit RGB raster and the tiny protocol that turns PNG bytes into one. Pure value types, Foundation only.
// The Terrarium maths never touches ImageIO: it works on `RGB8Image`, so tests can hand-build pixels.
import Foundation

/// An 8-bit-per-channel RGB image: `width * height` pixels, rows top to bottom, three bytes (R, G, B) per pixel,
/// no row padding, no alpha.
public struct RGB8Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// `width * height * 3` bytes, rows top to bottom, R then G then B.
    public let pixels: [UInt8]

    /// Returns nil when the dimensions are not positive or `pixels.count != width * height * 3`.
    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height * 3 else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// An image where every pixel is the same colour.
    public init?(width: Int, height: Int, fill: (r: UInt8, g: UInt8, b: UInt8)) {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            bytes[i * 3] = fill.r
            bytes[i * 3 + 1] = fill.g
            bytes[i * 3 + 2] = fill.b
        }
        self.init(width: width, height: height, pixels: bytes)
    }

    /// The colour at column `x`, row `y`. Both must be in range (checked by the caller).
    @inlinable
    public func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 3
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }
}

/// Turns PNG bytes into the exact stored RGB bytes. Implementations must not colour-manage, gamma-correct or
/// premultiply: Terrarium packs an elevation into the channel values, so any change shifts elevations by metres.
public protocol RGBImageDecoding: Sendable {
    func decodeRGB8(_ png: Data) throws -> RGB8Image
}

/// Why a PNG could not be turned into exact 8-bit RGB.
public enum RGBImageDecodingError: Error, Sendable, Equatable {
    case notAnImage
    case noPixelData
    case unsupportedColorModel(String)
    case unsupportedBitsPerComponent(Int)
    case unsupportedBitsPerPixel(Int)
    case floatComponents
    case unsupportedByteOrder
    case premultipliedAlphaChangedPixels
    case truncatedPixelData
    case imageIOUnavailable
}
