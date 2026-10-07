import Foundation
import IterCore
import IterServices

/// Why a downloaded pack is no longer complete or current.
public enum StaleReason: Equatable, Sendable {
    /// The trip was edited (stops, dates or name) after the pack was made.
    case tripChanged
    /// The oldest forecast in the pack is more than 12 hours old.
    case forecastOld
    /// Something could not be downloaded (a forecast, a drive or an image).
    case incomplete
}

/// The per-device offline state of a trip. In memory only; the pack on disk is the source of truth.
public enum OfflinePackStatus: Equatable, Sendable {
    case none
    case downloading(done: Int, total: Int)
    case ready(savedAt: Date)
    case stale(savedAt: Date, reason: StaleReason)
    case failed(String)
}

/// Everything a pinned trip needs to open with no network, except the base map (MapKit cannot download tiles).
public struct OfflinePack: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    /// One saved image. The PNG lives in the pack's image folder under `fileName`.
    public struct Image: Codable, Equatable, Sendable {
        public var fileName: String
        public var spotID: String
        public var source: SpotImageSource
        public var coordinate: Coordinate
        public var pointWidth: Double
        public var pointHeight: Double
        public var scale: Double

        public init(fileName: String, spotID: String, source: SpotImageSource, coordinate: Coordinate,
                    pointWidth: Double, pointHeight: Double, scale: Double) {
            self.fileName = fileName
            self.spotID = spotID
            self.source = source
            self.coordinate = coordinate
            self.pointWidth = pointWidth
            self.pointHeight = pointHeight
            self.scale = scale
        }

        public var key: SpotImageKey {
            SpotImageKey(spotID: spotID, source: source, coordinate: coordinate,
                         pointSize: CGSize(width: pointWidth, height: pointHeight), scale: scale)
        }
    }

    public var version: Int
    public var tripID: UUID
    /// When the download finished.
    public var savedAt: Date
    /// The trip's `updatedAt` when the download started; a later edit makes the pack stale.
    public var tripUpdatedAt: Date
    public var spots: [Spot]
    /// By `Coordinate.cacheKey`.
    public var forecasts: [String: Forecast]
    /// Real routes only (never estimates), with their road geometry.
    public var legs: [DriveLeg]
    /// File names of the saved PNGs (same order as `images`).
    public var imageKeys: [String]
    public var images: [Image]
    /// Human-readable list of what could not be downloaded; non-empty means the pack is incomplete.
    public var failures: [String]

    public init(version: Int = OfflinePack.currentVersion, tripID: UUID, savedAt: Date, tripUpdatedAt: Date, spots: [Spot],
                forecasts: [String: Forecast], legs: [DriveLeg], images: [Image], failures: [String]) {
        self.version = version
        self.tripID = tripID
        self.savedAt = savedAt
        self.tripUpdatedAt = tripUpdatedAt
        self.spots = spots
        self.forecasts = forecasts
        self.legs = legs
        self.images = images
        self.imageKeys = images.map(\.fileName)
        self.failures = failures
    }

    /// The oldest forecast in the pack, nil when it holds none.
    public var oldestForecast: Date? { forecasts.values.map(\.fetchedAt).min() }
}

/// Reads and writes packs under a root directory: `<root>/<tripUUID>.json` plus `<root>/<tripUUID>/<image>.png`.
/// Writes are atomic per file; the JSON is written last so a pack is never visible before its images.
public struct OfflinePackStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Application Support/Iter/OfflinePacks.
    public static func defaultRoot() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Iter/OfflinePacks", directoryHint: .isDirectory)
    }

    private func packURL(_ id: UUID) -> URL { root.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory) }
    private func imageDirectory(_ id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }

    public func read(_ id: UUID) -> OfflinePack? {
        guard let data = try? Data(contentsOf: packURL(id)),
              let pack = try? JSONDecoder().decode(OfflinePack.self, from: data),
              pack.version == OfflinePack.currentVersion, pack.tripID == id else { return nil }
        return pack
    }

    public func readImage(_ id: UUID, fileName: String) -> Data? {
        try? Data(contentsOf: imageDirectory(id).appending(path: fileName, directoryHint: .notDirectory))
    }

    /// Writes the images, then the JSON, then removes images the new pack no longer lists.
    public func write(_ pack: OfflinePack, images: [String: Data]) throws {
        let fm = FileManager.default
        let dir = imageDirectory(pack.tripID)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in images { try data.write(to: dir.appending(path: name, directoryHint: .notDirectory), options: .atomic) }
        try JSONEncoder().encode(pack).write(to: packURL(pack.tripID), options: .atomic)
        let keep = Set(pack.imageKeys)
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(name) {
            try? fm.removeItem(at: dir.appending(path: name, directoryHint: .notDirectory))
        }
    }

    public func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: packURL(id))
        try? FileManager.default.removeItem(at: imageDirectory(id))
    }

    /// Every trip that has anything on disk.
    public func packIDs() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var ids = Set<UUID>()
        for name in names {
            let stem = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
            if let id = UUID(uuidString: stem) { ids.insert(id) }
        }
        return ids.sorted { $0.uuidString < $1.uuidString }
    }
}
