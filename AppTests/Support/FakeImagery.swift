import SwiftUI
import CoreGraphics
import Testing
import IterCore
import IterData
import IterDesign
import IterFeatures
import IterServices
@testable import Iter

/// Imagery for snapshots without a network: a generated gradient per source, drawn with the source's name so the
/// strip's paging and labels can be reviewed. FIXTURE ONLY; the app never invents images.
struct FakeImagery: SpotImageryProviding {
    var sources: [SpotImageSource]

    func cachedImages(for request: SpotImageRequest) -> [SpotImage]? { make(request) }
    func images(for request: SpotImageRequest) async -> [SpotImage] { make(request) }
    func hasLookAround(spotID: String, coordinate: Coordinate) async -> Bool { sources.contains(.lookAround) }

    private func make(_ request: SpotImageRequest) -> [SpotImage] {
        sources.compactMap { source in
            let key = request.key(source)
            guard let image = Self.gradient(width: key.pixelWidth, height: key.pixelHeight, source: source) else { return nil }
            return SpotImage(key: key, image: image)
        }
    }

    private static func gradient(width: Int, height: Int, source: SpotImageSource) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors: [CGColor] = source == .lookAround
            ? [CGColor(red: 0.95, green: 0.62, blue: 0.35, alpha: 1), CGColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)]
            : [CGColor(red: 0.30, green: 0.45, blue: 0.30, alpha: 1), CGColor(red: 0.75, green: 0.70, blue: 0.55, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        return ctx.makeImage()
    }
}
