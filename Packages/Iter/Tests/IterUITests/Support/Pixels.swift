import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// A decoded CGImage with RGBA access in pixel coordinates (origin top-left). Cross-platform.
struct Pixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width; self.height = height; data = buffer
    }

    /// Straight (un-premultiplied) sRGB RGBA, 0...255, y counted from the top.
    func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let o = (y * width + x) * 4
        let a = Int(data[o + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        func un(_ v: UInt8) -> Int { min(255, (Int(v) * 255 + a / 2) / a) }
        return (un(data[o]), un(data[o + 1]), un(data[o + 2]), a)
    }

    /// Raw premultiplied bytes of a pixel (used by `ImageDiff`).
    func raw(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let o = (y * width + x) * 4
        return (data[o], data[o + 1], data[o + 2], data[o + 3])
    }

    func luma(_ x: Int, _ y: Int) -> Double {
        let p = rgba(x, y)
        return (0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255
    }
}

enum PNG {
    static func data(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func image(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
