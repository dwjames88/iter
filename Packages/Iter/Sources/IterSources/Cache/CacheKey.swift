import Foundation
import IterModel
import Synchronization

/// `(source, kind, cell, bucket)`: the cell is a coordinate snapped to the source's grid, the bucket a time slot
/// (a model cycle, a UTC day) or any extra discriminator. Two places in the same cell share one cached answer.
public struct CacheKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public var source: SourceID
    public var kind: DataKind
    public var cell: String
    public var bucket: String

    public init(source: SourceID, kind: DataKind, cell: String, bucket: String = "") {
        self.source = source
        self.kind = kind
        self.cell = cell
        self.bucket = bucket
    }

    public var description: String { "\(source.rawValue)|\(kind.rawValue)|\(cell)|\(bucket)" }

    /// A file-system-safe name (a stable FNV-1a 64 hash of `description`, hex).
    public var fileName: String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in description.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return String(h, radix: 16)
    }
}

/// Snaps coordinates to a grid so nearby requests share a cache cell.
public enum GeoCell {
    /// "lat,lon" of the cell's south-west corner at `degrees` resolution, e.g. 0.25 for GFS, 0.01 for ~1 km.
    public static func key(_ c: Coordinate, degrees: Double) -> String {
        precondition(degrees > 0)
        let lat = (c.latitude / degrees).rounded(.down) * degrees
        var lon = c.longitude
        lon = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
        lon = (lon / degrees).rounded(.down) * degrees
        func f(_ v: Double) -> String {
            let s = String(format: "%.4f", v)
            return s == "-0.0000" ? "0.0000" : s
        }
        return "\(f(lat)),\(f(lon))@\(degrees)"
    }
}

/// A raw cached body and when it was stored.
public struct CachedBlob: Sendable, Hashable {
    public var data: Data
    public var storedAt: Date
    public init(data: Data, storedAt: Date) {
        self.data = data
        self.storedAt = storedAt
    }
}

/// Raw-response caching an adapter can use for bodies it reuses (NOMADS GRIB boxes per cycle and hour).
/// `SourceCache` conforms; `InMemoryBlobCache` is for tests and previews.
public protocol BlobCaching: Sendable {
    /// The stored blob, or nil when absent or older than `maxAge` (nil `maxAge` = any age).
    func blob(for key: CacheKey, maxAge: Duration?) async -> CachedBlob?
    /// Stores the blob; when `licence.mayStore` is false it is kept in memory only.
    func storeBlob(_ data: Data, for key: CacheKey, licence: LicenceTag) async
}

/// A process-local blob cache with an injected clock.
public final class InMemoryBlobCache: BlobCaching {
    private let items = Mutex<[CacheKey: CachedBlob]>([:])
    private let clock: any SourceClock

    public init(clock: any SourceClock = SystemSourceClock()) { self.clock = clock }

    public func blob(for key: CacheKey, maxAge: Duration?) async -> CachedBlob? {
        let now = clock.now
        return items.withLock { d in
            guard let b = d[key] else { return nil }
            if let maxAge, now.timeIntervalSince(b.storedAt) > maxAge.timeInterval { return nil }
            return b
        }
    }

    public func storeBlob(_ data: Data, for key: CacheKey, licence: LicenceTag) async {
        let now = clock.now
        items.withLock { $0[key] = CachedBlob(data: data, storedAt: now) }
    }

    public var count: Int { items.withLock { $0.count } }
}
