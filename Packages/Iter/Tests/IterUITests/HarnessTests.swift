import CoreGraphics
import SwiftUI
import Testing

@Suite("ImageDiff")
struct ImageDiffTests {
    static func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, w: Int = 20, h: Int = 20,
                      patch: (x: Int, y: Int, w: Int, h: Int, rgb: (UInt8, UInt8, UInt8))? = nil) -> CGImage {
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            var c = (r, g, b)
            if let p = patch, x >= p.x, x < p.x + p.w, y >= p.y, y < p.y + p.h { c = p.rgb }
            let o = (y * w + x) * 4
            buf[o] = c.0; buf[o + 1] = c.1; buf[o + 2] = c.2
        } }
        return buf.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    @Test func identicalPasses() {
        let r = ImageDiff().compare(Self.solid(10, 20, 30), Self.solid(10, 20, 30))
        #expect(r.passed); #expect(r.differing == 0); #expect(r.maxChannelDelta == 0)
    }

    @Test func onePixelWithinToleranceAndSmallChangePasses() {
        // One pixel far off: 1/400 = 0.25% <= 0.5%.
        let one = Self.solid(10, 20, 30, patch: (3, 3, 1, 1, (200, 20, 30)))
        #expect(ImageDiff().compare(Self.solid(10, 20, 30), one).passed)
        // A change below the channel threshold everywhere passes.
        #expect(ImageDiff().compare(Self.solid(10, 20, 30), Self.solid(15, 25, 35)).passed)
    }

    @Test func largeChangeFails() {
        let r = ImageDiff().compare(Self.solid(10, 20, 30), Self.solid(10, 20, 30, patch: (0, 0, 10, 10, (255, 0, 0))))
        #expect(!r.passed); #expect(r.differing == 100); #expect(r.diffImage != nil)
        #expect(!ImageDiff().compare(Self.solid(10, 20, 30), Self.solid(90, 20, 30)).passed)
    }

    @Test func differentSizesFail() {
        let r = ImageDiff().compare(Self.solid(0, 0, 0, w: 20, h: 20), Self.solid(0, 0, 0, w: 21, h: 20))
        #expect(!r.passed); #expect(r.sizeMismatch)
    }
}

@MainActor
@Suite("Snapshot harness")
struct HarnessTests {
    static let swatch = Color(.sRGB, red: 0.8, green: 0.2, blue: 0.1)   // 204, 51, 26

    /// Solid rectangle, text, an SF Symbol and a system glass circle button in a GlassEffectContainer.
    struct SelfTestView: View {
        var body: some View {
            VStack(spacing: 8) {
                Rectangle().fill(HarnessTests.swatch).frame(width: 60, height: 40)
                Text("Golden Hour").font(.headline).foregroundStyle(.primary)
                Image(systemName: "sunset.fill").font(.title).foregroundStyle(.primary)
                GlassEffectContainer {
                    Button {} label: { Image(systemName: "plus").frame(width: 32, height: 32) }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(12)
        }
    }

    static let size = CGSize(width: 160, height: 190)

    @Test(arguments: SnapshotAppearance.allCases)
    func solidRectangleHasExactColour(appearance: SnapshotAppearance) async throws {
        let img = try await Snapshot.image(SelfTestView(), appearance: appearance, size: Self.size)
        #expect(img.width == 320 && img.height == 380)
        let px = try #require(Pixels(img))
        // Rectangle: VStack is centred in 160x190; swatch centre is at x=80, near the top. Search for it by scanning.
        var hits = 0
        for y in stride(from: 0, to: px.height, by: 2) {
            let p = px.rgba(160, y)
            if abs(p.r - 204) <= 1, abs(p.g - 51) <= 1, abs(p.b - 26) <= 1 { hits += 1 }
        }
        // 40pt tall at 2x = 80 rows, sampled every 2nd row = 40.
        #expect(hits >= 38, "swatch rows with expected sRGB: \(hits)")
    }

    @Test func recordSelfTest() async throws {
        let urls = try await Snapshot.record(SelfTestView(), name: "harness-selftest", size: Self.size)
        #expect(urls.count == 2)
        for u in urls { #expect(FileManager.default.fileExists(atPath: u.path)) }
    }

    /// First call records (reference missing), second compares and passes. The throw-away references are deleted.
    @Test func assertMatchesRecordsThenMatches() async throws {
        let name = "harness-tmp-\(UUID().uuidString.prefix(8))"
        defer { for a in SnapshotAppearance.allCases { try? FileManager.default.removeItem(at: Snapshot.referenceURL(name: name, appearance: a)) } }
        try await Snapshot.assertMatches(SelfTestView(), name: name, size: Self.size)
        for a in SnapshotAppearance.allCases { #expect(FileManager.default.fileExists(atPath: Snapshot.referenceURL(name: name, appearance: a).path)) }
        try await Snapshot.assertMatches(SelfTestView(), name: name, size: Self.size)
    }
}
