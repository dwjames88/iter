import CoreGraphics

/// Tolerance comparison of two images. A pixel "differs" when any channel (R, G, B, A, straight 8-bit sRGB) is more
/// than `channelThreshold` away. The images match when the fraction of differing pixels is at most `maxFraction`.
struct ImageDiff: Sendable {
    /// Per-channel threshold, out of 255 (default 8).
    var channelThreshold: Int = 8
    /// Maximum fraction of differing pixels, 0...1 (default 0.5%).
    var maxFraction: Double = 0.005

    struct Result {
        let sizeMismatch: Bool
        let differing: Int
        let total: Int
        let maxChannelDelta: Int
        let fraction: Double
        let passed: Bool
        /// Red where pixels differ, faint grey copy of the reference elsewhere. nil on a size mismatch.
        let diffImage: CGImage?

        var summary: String {
            if sizeMismatch { return "size mismatch" }
            return "\(differing)/\(total) pixels differ (\(String(format: "%.3f", fraction * 100))%), max channel delta \(maxChannelDelta)"
        }
    }

    func compare(_ a: CGImage, _ b: CGImage) -> Result {
        guard a.width == b.width, a.height == b.height, let pa = Pixels(a), let pb = Pixels(b) else {
            return Result(sizeMismatch: true, differing: 0, total: 0, maxChannelDelta: 0, fraction: 1, passed: false, diffImage: nil)
        }
        let w = pa.width, h = pa.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var differing = 0, maxDelta = 0
        for y in 0..<h {
            for x in 0..<w {
                let p = pa.rgba(x, y), q = pb.rgba(x, y)
                let d = max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
                maxDelta = max(maxDelta, d)
                let o = (y * w + x) * 4
                if d > channelThreshold {
                    differing += 1
                    out[o] = 255; out[o + 3] = 255
                } else {
                    let g = UInt8(60 + Int(pa.luma(x, y) * 120))
                    out[o] = g; out[o + 1] = g; out[o + 2] = g; out[o + 3] = 255
                }
            }
        }
        let total = w * h
        let fraction = total == 0 ? 0 : Double(differing) / Double(total)
        var image: CGImage?
        out.withUnsafeMutableBytes { raw in
            image = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return Result(sizeMismatch: false, differing: differing, total: total, maxChannelDelta: maxDelta,
                      fraction: fraction, passed: fraction <= maxFraction, diffImage: image)
    }
}
