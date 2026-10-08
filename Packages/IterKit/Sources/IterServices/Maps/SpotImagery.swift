import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import IterCore

// Images of a spot for the place card. Sources are Apple's own imagery only (Look Around, satellite snapshots);
// the app never invents photos.

/// Where an image of a spot came from.
// Later: `case userPhoto` for photos the user attaches to a spot (roadmap). Keys and the disk cache already
// carry the source, so adding it needs no migration; the provider would read from the spot's own store.
public enum SpotImageSource: String, Sendable, Hashable, Codable, CaseIterable {
    case lookAround
    case satellite
}

public struct SpotImageKey: Hashable, Sendable {
    public let spotID: String
    public let source: SpotImageSource
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Coordinate rounded to 5 decimals (about 1 m), so an edited user spot gets new images.
    public let latitudeE5: Int
    public let longitudeE5: Int
    /// Satellite ignores it (always false in its key); kept for future map styles.
    public let darkAppearance: Bool

    public init(spotID: String, source: SpotImageSource, coordinate: Coordinate, pointSize: CGSize, scale: CGFloat, darkAppearance: Bool = false) {
        self.spotID = spotID
        self.source = source
        self.pixelWidth = max(1, Int((pointSize.width * scale).rounded()))
        self.pixelHeight = max(1, Int((pointSize.height * scale).rounded()))
        self.latitudeE5 = Int((coordinate.latitude * 100_000).rounded())
        self.longitudeE5 = Int((coordinate.longitude * 100_000).rounded())
        self.darkAppearance = source == .satellite ? false : darkAppearance
    }

    /// Filesystem-safe, stable, unique per key: `<id>_<source>_<w>x<h>_<latE5>_<lonE5>[_dark].png`.
    public var fileName: String {
        var name = "\(Self.sanitise(spotID))_\(source.rawValue)_\(pixelWidth)x\(pixelHeight)_\(latitudeE5)_\(longitudeE5)"
        if darkAppearance { name += "_dark" }
        return name + ".png"
    }

    /// Keeps letters, digits and `-`; everything else (including `/`, `:`, `_`, `.`) becomes `~XX` per UTF-8 byte,
    /// so distinct ids never collide and the result cannot escape the cache directory.
    static func sanitise(_ id: String) -> String {
        var out = ""
        for byte in id.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "-"):
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out += String(format: "~%02X", byte)
            }
        }
        return out.isEmpty ? "~" : out
    }
}

public struct SpotImage: Identifiable, Sendable {
    public let key: SpotImageKey
    public var id: SpotImageKey { key }
    public var source: SpotImageSource { key.source }
    public let image: CGImage

    public init(key: SpotImageKey, image: CGImage) {
        self.key = key
        self.image = image
    }
}

public struct SpotImageRequest: Hashable, Sendable {
    public let spotID: String
    public let coordinate: Coordinate
    public let pointSize: CGSize
    public let scale: CGFloat

    public init(spotID: String, coordinate: Coordinate, pointSize: CGSize, scale: CGFloat) {
        self.spotID = spotID
        self.coordinate = coordinate
        self.pointSize = pointSize
        self.scale = scale
    }

    public func key(_ source: SpotImageSource, darkAppearance: Bool = false) -> SpotImageKey {
        SpotImageKey(spotID: spotID, source: source, coordinate: coordinate, pointSize: pointSize, scale: scale, darkAppearance: darkAppearance)
    }
}

/// Provider contract the UI codes against.
public protocol SpotImageryProviding: Sendable {
    /// Synchronous memory-cache lookup. nil if this request has not been resolved yet in this process.
    func cachedImages(for request: SpotImageRequest) -> [SpotImage]?
    /// Look Around first (when Apple has imagery here), then the satellite snapshot. Uses memory, then disk, then MapKit.
    /// Returns [] if neither could be made (offline, etc.). Never throws.
    func images(for request: SpotImageRequest) async -> [SpotImage]
    /// Whether Apple has Look Around imagery at this coordinate (cached per spot/coordinate).
    func hasLookAround(spotID: String, coordinate: Coordinate) async -> Bool
}

/// Thread-safe in-memory cache, readable synchronously so a SwiftUI view can show cached images on its first frame.
public final class SpotImageMemoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RequestKey: [SpotImage]] = [:]
    private var order: [RequestKey] = []   // oldest first
    private let countLimit: Int

    /// Requests compare by spot, rounded coordinate and pixel size, matching the disk keys.
    private struct RequestKey: Hashable {
        let spotID: String, latE5: Int, lonE5: Int, w: Int, h: Int
        init(_ r: SpotImageRequest) {
            let k = r.key(.satellite)
            spotID = k.spotID; latE5 = k.latitudeE5; lonE5 = k.longitudeE5; w = k.pixelWidth; h = k.pixelHeight
        }
    }

    public init(countLimit: Int = 64) {
        self.countLimit = max(1, countLimit)
    }

    /// nil = never resolved; [] = resolved, nothing available.
    public func images(for request: SpotImageRequest) -> [SpotImage]? {
        lock.lock(); defer { lock.unlock() }
        return storage[RequestKey(request)]
    }

    public func store(_ images: [SpotImage], for request: SpotImageRequest) {
        let key = RequestKey(request)
        lock.lock(); defer { lock.unlock() }
        if storage.updateValue(images, forKey: key) == nil {
            order.append(key)
        } else if let i = order.firstIndex(of: key) {
            order.remove(at: i); order.append(key)
        }
        while order.count > countLimit {
            storage.removeValue(forKey: order.removeFirst())
        }
    }
}

// MARK: - Disk cache

/// PNG per key plus a small JSON record per spot+coordinate for the Look Around availability answer.
struct SpotImageDiskCache: Sendable {
    let directory: URL

    /// The default location: `Caches/com.dwjames.iter/SpotImagery`.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("com.dwjames.iter", isDirectory: true).appendingPathComponent("SpotImagery", isDirectory: true)
    }

    func read(_ key: SpotImageKey) -> CGImage? {
        let url = directory.appendingPathComponent(key.fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Decode now, on the caller's thread: ImageIO would otherwise decode the PNG lazily, at the first draw, which is
        // the main thread when the strip appears.
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    @discardableResult
    func write(_ image: CGImage, for key: SpotImageKey) -> Bool {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return false }
        let url = directory.appendingPathComponent(key.fileName)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)   // writes atomically enough: a torn file simply fails to decode and is re-made
    }

    private func availabilityURL(spotID: String, coordinate: Coordinate) -> URL {
        let lat = Int((coordinate.latitude * 100_000).rounded()), lon = Int((coordinate.longitude * 100_000).rounded())
        return directory.appendingPathComponent("lookaround_\(SpotImageKey.sanitise(spotID))_\(lat)_\(lon).json")
    }

    func readAvailability(spotID: String, coordinate: Coordinate, now: Date = Date()) -> Bool? {
        guard let data = try? Data(contentsOf: availabilityURL(spotID: spotID, coordinate: coordinate)),
              let record = try? JSONDecoder().decode(LookAroundAvailabilityRecord.self, from: data) else { return nil }
        return record.answer(at: now)
    }

    func writeAvailability(_ available: Bool, spotID: String, coordinate: Coordinate, now: Date = Date()) {
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let data = try? JSONEncoder().encode(LookAroundAvailabilityRecord(available: available, checkedAt: now)) else { return }
        try? data.write(to: availabilityURL(spotID: spotID, coordinate: coordinate), options: .atomic)
    }
}

/// The persisted answer to "does Apple have Look Around here". "Yes" is kept; "no" expires after 30 days
/// because Apple extends coverage over time.
struct LookAroundAvailabilityRecord: Codable, Equatable, Sendable {
    static let noExpiry: TimeInterval = 30 * 24 * 3600

    var available: Bool
    var checkedAt: Date

    /// The remembered answer, or nil when it should be asked again.
    func answer(at now: Date) -> Bool? {
        if available { return true }
        return now.timeIntervalSince(checkedAt) < Self.noExpiry ? false : nil
    }
}
