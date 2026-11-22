// Platform adapter: PNG bytes -> exact stored RGB bytes, using ImageIO and CoreGraphics (macOS and iOS, no AppKit
// or UIKit, no third-party code).
//
// Why not just draw into a bitmap context? Terrarium stores an elevation in the channel values themselves
// (R * 256 + G + B / 256). Drawing a CGImage into a context converts between colour spaces, applies gamma from
// gAMA/iCCP/sRGB chunks and premultiplies alpha; any of these silently changes channel values and so shifts
// elevations by metres. Instead this adapter decodes with ImageIO (kCGImageSourceShouldCache: false), takes the
// CGImage's raw backing bytes from its dataProvider, and interprets bitsPerPixel, bytesPerRow, alpha info and
// byte order itself. Supported: RGB 24-bit and RGBA/RGBX 32-bit in either channel and byte order, 8 bits per
// component. Anything else (16-bit, float, grey, palette that ImageIO did not expand) throws a typed error.
// Premultiplied alpha is accepted only if every alpha byte is 255 (then premultiplication is the identity).
//
// Verified against an independent pure-Python PNG decoder on real tiles (see Fixtures/Terrarium/).
import Foundation

#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics

public struct ImageIOPNGDecoder: RGBImageDecoding {
    public init() {}

    public func decodeRGB8(_ png: Data) throws -> RGB8Image {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(png as CFData, options as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { throw RGBImageDecodingError.notAnImage }
        guard let data = image.dataProvider?.data else { throw RGBImageDecodingError.noPixelData }
        let bytes = [UInt8](data as Data)
        return try Self.extractRGB(
            bytes: bytes, width: image.width, height: image.height,
            bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow, bitmapInfo: image.bitmapInfo, alphaInfo: image.alphaInfo,
            colorModel: image.colorSpace?.model)
    }

    /// The pure layout logic, separated so it can be exercised with synthetic buffers.
    static func extractRGB(bytes: [UInt8], width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int,
                           bytesPerRow: Int, bitmapInfo: CGBitmapInfo, alphaInfo: CGImageAlphaInfo,
                           colorModel: CGColorSpaceModel?) throws -> RGB8Image {
        guard colorModel == .rgb else { throw RGBImageDecodingError.unsupportedColorModel(String(describing: colorModel)) }
        guard bitsPerComponent == 8 else { throw RGBImageDecodingError.unsupportedBitsPerComponent(bitsPerComponent) }
        if bitmapInfo.contains(.floatComponents) { throw RGBImageDecodingError.floatComponents }
        let order = bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        guard order == 0 || order == CGBitmapInfo.byteOrder32Little.rawValue || order == CGBitmapInfo.byteOrder32Big.rawValue
        else { throw RGBImageDecodingError.unsupportedByteOrder }
        let little = order == CGBitmapInfo.byteOrder32Little.rawValue
        guard bytesPerRow >= width * (bitsPerPixel / 8), bytes.count >= bytesPerRow * (height - 1) + width * (bitsPerPixel / 8)
        else { throw RGBImageDecodingError.truncatedPixelData }

        // Byte offsets of R, G, B (and alpha, if any) inside one pixel as stored in memory.
        let offsets: (r: Int, g: Int, b: Int, a: Int?)
        switch bitsPerPixel {
        case 24:
            guard alphaInfo == .none else { throw RGBImageDecodingError.unsupportedBitsPerPixel(bitsPerPixel) }
            // 24-bit pixels are stored R, G, B (kCGBitmapByteOrderDefault).
            offsets = little ? (2, 1, 0, nil) : (0, 1, 2, nil)
        case 32:
            let alphaFirst: Bool
            let hasAlpha: Bool
            switch alphaInfo {
            case .premultipliedFirst, .first: alphaFirst = true; hasAlpha = true
            case .premultipliedLast, .last: alphaFirst = false; hasAlpha = true
            case .noneSkipFirst: alphaFirst = true; hasAlpha = false
            case .noneSkipLast: alphaFirst = false; hasAlpha = false
            default: throw RGBImageDecodingError.unsupportedBitsPerPixel(bitsPerPixel)
            }
            // Big-endian word: ARGB or RGBA in memory order. Little-endian 32-bit word reverses the bytes.
            var o: (r: Int, g: Int, b: Int, a: Int) = alphaFirst ? (1, 2, 3, 0) : (0, 1, 2, 3)
            if little { o = (3 - o.r, 3 - o.g, 3 - o.b, 3 - o.a) }
            offsets = (o.r, o.g, o.b, hasAlpha ? o.a : nil)
        default:
            throw RGBImageDecodingError.unsupportedBitsPerPixel(bitsPerPixel)
        }

        let premultiplied = alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
        let stride = bitsPerPixel / 8
        var out = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            var src = y * bytesPerRow
            var dst = y * width * 3
            for _ in 0..<width {
                if premultiplied, let a = offsets.a, bytes[src + a] != 255 {
                    throw RGBImageDecodingError.premultipliedAlphaChangedPixels
                }
                out[dst] = bytes[src + offsets.r]
                out[dst + 1] = bytes[src + offsets.g]
                out[dst + 2] = bytes[src + offsets.b]
                src += stride
                dst += 3
            }
        }
        guard let image = RGB8Image(width: width, height: height, pixels: out) else { throw RGBImageDecodingError.noPixelData }
        return image
    }
}
#else
/// ImageIO is unavailable on this platform: decoding always throws.
public struct ImageIOPNGDecoder: RGBImageDecoding {
    public init() {}
    public func decodeRGB8(_ png: Data) throws -> RGB8Image { throw RGBImageDecodingError.imageIOUnavailable }
}
#endif
