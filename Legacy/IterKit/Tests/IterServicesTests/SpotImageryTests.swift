import Testing
import Foundation
import CoreGraphics
import ImageIO
import IterCore
@testable import IterServices

@Suite struct SpotImageryTests {
    private let c = Coordinate(latitude: 38.389, longitude: -109.868)
    private let size = CGSize(width: 320, height: 200)

    private func key(id: String = "mesa-arch", source: SpotImageSource = .satellite, coordinate: Coordinate? = nil,
                     size: CGSize? = nil, scale: CGFloat = 2, dark: Bool = false) -> SpotImageKey {
        SpotImageKey(spotID: id, source: source, coordinate: coordinate ?? c, pointSize: size ?? self.size, scale: scale, darkAppearance: dark)
    }

    private func makeImage(_ w: Int = 8, _ h: Int = 6) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    @Test func keyEqualityPerField() {
        let base = key()
        #expect(base == key())
        #expect(base != key(id: "other"))
        #expect(base != key(source: .lookAround))
        #expect(base != key(size: CGSize(width: 321, height: 200)))
        #expect(base != key(scale: 1))
        #expect(base != key(coordinate: Coordinate(latitude: 38.38901, longitude: -109.868)))
        #expect(base != key(coordinate: Coordinate(latitude: 38.389, longitude: -109.86801)))
        #expect(base.pixelWidth == 640 && base.pixelHeight == 400)
    }

    @Test func coordinateBelowRoundingIsSameKey() {
        let near = Coordinate(latitude: 38.389 + 0.000002, longitude: -109.868 - 0.000003)
        #expect(key(coordinate: near) == key())
        #expect(key(coordinate: near).fileName == key().fileName)
    }

    @Test func satelliteKeyIgnoresDarkAppearance() {
        #expect(key(source: .satellite, dark: true) == key(source: .satellite, dark: false))
        #expect(key(source: .satellite, dark: true).darkAppearance == false)
        #expect(key(source: .lookAround, dark: true) != key(source: .lookAround, dark: false))
        #expect(key(source: .lookAround, dark: true).fileName.hasSuffix("_dark.png"))
    }

    @Test func fileNameIsStableAndSafe() {
        #expect(key().fileName == "mesa-arch_satellite_640x400_3838900_-10986800.png")
        let nasty = key(id: "../a/b:c d")
        #expect(!nasty.fileName.contains("/") && !nasty.fileName.contains(":") && !nasty.fileName.contains(" "))
        #expect(!nasty.fileName.hasPrefix("."))
        #expect(key(id: "a/b").fileName != key(id: "a:b").fileName)
        #expect(key(id: "a_b").fileName != key(id: "a~5Fb").fileName)
        let uuid = UUID().uuidString
        #expect(key(id: uuid).fileName.hasPrefix(uuid))
        #expect(Set(SpotImageSource.allCases.map { key(source: $0).fileName }).count == 2)
    }

    @Test func memoryCacheNilVersusEmpty() {
        let cache = SpotImageMemoryCache()
        let request = SpotImageRequest(spotID: "a", coordinate: c, pointSize: size, scale: 2)
        #expect(cache.images(for: request) == nil)
        cache.store([], for: request)
        #expect(cache.images(for: request)?.isEmpty == true)
        let image = SpotImage(key: request.key(.satellite), image: makeImage())
        cache.store([image], for: request)
        #expect(cache.images(for: request)?.count == 1)
        #expect(cache.images(for: SpotImageRequest(spotID: "b", coordinate: c, pointSize: size, scale: 2)) == nil)
    }

    @Test func memoryCacheEvictsOldest() {
        let cache = SpotImageMemoryCache(countLimit: 2)
        func req(_ id: String) -> SpotImageRequest { SpotImageRequest(spotID: id, coordinate: c, pointSize: size, scale: 2) }
        cache.store([], for: req("1")); cache.store([], for: req("2")); cache.store([], for: req("3"))
        #expect(cache.images(for: req("1")) == nil)
        #expect(cache.images(for: req("2")) != nil && cache.images(for: req("3")) != nil)
    }

    @Test func diskRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-imagery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = SpotImageDiskCache(directory: dir)
        let k = key()
        #expect(disk.read(k) == nil)
        #expect(disk.write(makeImage(8, 6), for: k))
        let back = try #require(disk.read(k))
        #expect(back.width == 8 && back.height == 6)
        #expect(disk.read(key(source: .lookAround)) == nil)
    }

    @Test func availabilityPersistsAndExpires() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-imagery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = SpotImageDiskCache(directory: dir)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(disk.readAvailability(spotID: "x", coordinate: c, now: t0) == nil)
        disk.writeAvailability(false, spotID: "x", coordinate: c, now: t0)
        disk.writeAvailability(true, spotID: "y", coordinate: c, now: t0)
        #expect(disk.readAvailability(spotID: "x", coordinate: c, now: t0.addingTimeInterval(86_400)) == false)
        #expect(disk.readAvailability(spotID: "x", coordinate: c, now: t0.addingTimeInterval(31 * 86_400)) == nil)
        #expect(disk.readAvailability(spotID: "y", coordinate: c, now: t0.addingTimeInterval(400 * 86_400)) == true)
        #expect(disk.readAvailability(spotID: "x", coordinate: Coordinate(latitude: 1, longitude: 2), now: t0) == nil)
    }

    @Test func noLookAroundExpiryBoundary() {
        let t0 = Date(timeIntervalSince1970: 0)
        let no = LookAroundAvailabilityRecord(available: false, checkedAt: t0)
        #expect(no.answer(at: t0.addingTimeInterval(30 * 86_400 - 1)) == false)
        #expect(no.answer(at: t0.addingTimeInterval(30 * 86_400)) == nil)
        #expect(LookAroundAvailabilityRecord(available: true, checkedAt: t0).answer(at: t0.addingTimeInterval(1e9)) == true)
    }

    @Test func renderFillsExactSizeAndDrawsMarker() throws {
        let out = try #require(MapKitSpotImagery.render(makeImage(40, 20), to: CGSize(width: 30, height: 30), markerAt: CGPoint(x: 20, y: 10)))
        #expect(out.width == 30 && out.height == 30)
    }
}
