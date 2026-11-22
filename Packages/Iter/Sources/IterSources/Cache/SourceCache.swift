import Foundation
import IterModel

/// How current a cache hit is. A value is fresh while its age is below the TTL; at exactly the TTL it is stale.
public enum CacheFreshness: Sendable, Hashable {
    case fresh
    case stale(age: Duration)
}

/// A cached value, when it was stored, and whether it is still fresh.
public struct CacheHit<Value: Sendable>: Sendable {
    public var value: Value
    public var storedAt: Date
    public var freshness: CacheFreshness

    public init(value: Value, storedAt: Date, freshness: CacheFreshness) {
        self.value = value
        self.storedAt = storedAt
        self.freshness = freshness
    }
}

/// Memory LRU plus an optional disk directory, with stale-while-revalidate and joined in-flight fetches.
///
/// - Values are stored JSON-encoded, so a typed entry and a raw blob share one store (`BlobCaching`).
/// - `licence.mayStore == false` keeps the entry in memory only; nothing of it reaches the directory.
/// - On disk each key is `<CacheKey.fileName>.blob` plus a `<fileName>.meta.json` sidecar (key description, storedAt,
///   licence key). A file whose sidecar names a different key (hash collision) is ignored.
/// - Memory eviction drops only the memory copy; a disk copy is read back on the next lookup.
/// - All time comes from the injected clock.
public actor SourceCache: BlobCaching {
    private struct Entry {
        var data: Data
        var storedAt: Date
        var lastUsed: UInt64
    }

    private struct Meta: Codable {
        var key: String
        var storedAt: Date
        var licence: String
    }

    private struct Stored: Sendable {
        var data: Data
        var storedAt: Date
    }

    private struct InFlight {
        var id: UInt64
        var task: Task<Stored, any Error>
    }

    private let directory: URL?
    private let clock: any SourceClock
    private let memoryCapacity: Int
    private var memory: [CacheKey: Entry] = [:]
    private var inflight: [CacheKey: InFlight] = [:]
    private var useCounter: UInt64 = 0
    private var fetchCounter: UInt64 = 0

    /// - Parameters:
    ///   - directory: where disk copies live (created when first needed); nil keeps everything in memory.
    ///   - memoryCapacity: most entries kept in memory.
    public init(directory: URL? = nil, memoryCapacity: Int = 256, clock: any SourceClock = SystemSourceClock()) {
        self.directory = directory
        self.memoryCapacity = max(1, memoryCapacity)
        self.clock = clock
    }

    // MARK: Typed values

    /// The stored value and when it was stored, whatever its age; nil when absent or unreadable.
    public func entry<V: Codable & Sendable>(_ key: CacheKey, as: V.Type) -> (value: V, storedAt: Date)? {
        guard let e = read(key) else { return nil }
        guard let v = try? JSONDecoder().decode(V.self, from: e.data) else { return nil }
        return (v, e.storedAt)
    }

    /// Stores a value now. Disk only when `licence.mayStore`.
    public func store<V: Codable & Sendable>(_ value: V, for key: CacheKey, licence: LicenceTag) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        put(key, data: data, storedAt: clock.now, licence: licence)
    }

    /// The cached value if fresh (no fetch); the cached value at once as stale with exactly one background refresh
    /// started (later calls join it); or, on a miss, the result of `fetch` (concurrent identical misses share one
    /// fetch). A failed refresh keeps the old entry. A failed miss throws.
    public func load<V: Codable & Sendable>(_ key: CacheKey, ttl: Duration, licence: LicenceTag,
                                            fetch: @escaping @Sendable () async throws -> V) async throws -> CacheHit<V> {
        if let cached = entry(key, as: V.self) {
            let age = clock.now.timeIntervalSince(cached.storedAt)
            if age < ttl.timeInterval {
                return CacheHit(value: cached.value, storedAt: cached.storedAt, freshness: .fresh)
            }
            _ = startFetch(key, licence: licence, fetch: fetch)
            return CacheHit(value: cached.value, storedAt: cached.storedAt, freshness: .stale(age: .interval(age)))
        }
        let flight = startFetch(key, licence: licence, fetch: fetch)
        let stored = try await flight.task.value
        let value = try JSONDecoder().decode(V.self, from: stored.data)
        return CacheHit(value: value, storedAt: stored.storedAt, freshness: .fresh)
    }

    /// A `DataState` for a source's answer. Fresh entry: `.fresh` without a fetch. Stale entry: `.stale` with its age at
    /// once, while one background refetch (joined by identical callers) replaces it on success. Missing: fetch and wait;
    /// success gives `.fresh`, failure `.none` with the reason.
    public func dataState<T: Codable & Sendable>(_ key: CacheKey, descriptor: SourceDescriptor,
                                                 fetch: @escaping @Sendable () async throws -> Sourced<T>) async -> DataState<T> {
        let old = entry(key, as: Sourced<T>.self)
        if let old, clock.now.timeIntervalSince(old.storedAt) < descriptor.cacheTTL.timeInterval {
            return .fresh(old.value)
        }
        let flight = startFetch(key, licence: descriptor.licence, fetch: fetch)
        // Stale-while-revalidate (BLUEPRINT §6.4): an old value is shown at once with its age while the one refetch
        // (joined by any identical caller) runs in the background and replaces it on success.
        if let old {
            return .stale(old.value, age: .interval(max(0, clock.now.timeIntervalSince(old.storedAt))))
        }
        do {
            let stored = try await flight.task.value
            return .fresh(try JSONDecoder().decode(Sourced<T>.self, from: stored.data))
        } catch {
            let wrapped = SourceError.wrap(error)
            if let old {
                return .stale(old.value, age: .interval(max(0, clock.now.timeIntervalSince(old.storedAt))))
            }
            return .none([wrapped.noDataReason(source: descriptor.id, lastGood: nil)])
        }
    }

    // MARK: Blobs

    public func blob(for key: CacheKey, maxAge: Duration?) async -> CachedBlob? {
        guard let e = read(key) else { return nil }
        if let maxAge, clock.now.timeIntervalSince(e.storedAt) > maxAge.timeInterval { return nil }
        return CachedBlob(data: e.data, storedAt: e.storedAt)
    }

    public func storeBlob(_ data: Data, for key: CacheKey, licence: LicenceTag) async {
        put(key, data: data, storedAt: clock.now, licence: licence)
    }

    // MARK: Maintenance

    /// Waits until no fetch (background refresh or otherwise) is running. For tests.
    public func waitForBackgroundRefreshes() async {
        while !inflight.isEmpty {
            let tasks = inflight.values.map(\.task)
            for t in tasks { _ = try? await t.value }
            await Task.yield()
        }
    }

    /// Removes every entry stored more than `age` ago, from memory and disk.
    public func purge(olderThan age: Duration) {
        let cutoff = clock.now.addingTimeInterval(-age.timeInterval)
        for (k, e) in memory where e.storedAt < cutoff { memory[k] = nil }
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for f in files where f.lastPathComponent.hasSuffix(".meta.json") {
            guard let data = try? Data(contentsOf: f), let meta = try? JSONDecoder().decode(Meta.self, from: data),
                  meta.storedAt < cutoff else { continue }
            let base = String(f.lastPathComponent.dropLast(".meta.json".count))
            try? FileManager.default.removeItem(at: f)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(base + ".blob"))
        }
    }

    /// Empties memory and the disk directory. In-flight fetches are left to finish.
    public func removeAll() {
        memory.removeAll()
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    /// Entries held in memory (tests).
    public var memoryCount: Int { memory.count }

    // MARK: Internals

    private func startFetch<V: Codable & Sendable>(_ key: CacheKey, licence: LicenceTag,
                                                   fetch: @escaping @Sendable () async throws -> V) -> InFlight {
        if let existing = inflight[key] { return existing }
        fetchCounter += 1
        let id = fetchCounter
        let task = Task<Stored, any Error> { [self] in
            do {
                let value = try await fetch()
                let data = try JSONEncoder().encode(value)
                let at = clock.now
                put(key, data: data, storedAt: at, licence: licence)
                finish(key, id: id)
                return Stored(data: data, storedAt: at)
            } catch {
                finish(key, id: id)
                throw error
            }
        }
        let flight = InFlight(id: id, task: task)
        inflight[key] = flight
        return flight
    }

    private func finish(_ key: CacheKey, id: UInt64) {
        if inflight[key]?.id == id { inflight[key] = nil }
    }

    private func put(_ key: CacheKey, data: Data, storedAt: Date, licence: LicenceTag) {
        useCounter += 1
        memory[key] = Entry(data: data, storedAt: storedAt, lastUsed: useCounter)
        evictIfNeeded()
        guard licence.mayStore, let directory else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let meta = Meta(key: key.description, storedAt: storedAt, licence: licence.key)
        try? data.write(to: directory.appendingPathComponent(key.fileName + ".blob"), options: .atomic)
        if let m = try? JSONEncoder().encode(meta) {
            try? m.write(to: directory.appendingPathComponent(key.fileName + ".meta.json"), options: .atomic)
        }
    }

    private func read(_ key: CacheKey) -> Entry? {
        if var e = memory[key] {
            useCounter += 1
            e.lastUsed = useCounter
            memory[key] = e
            return e
        }
        guard let directory,
              let metaData = try? Data(contentsOf: directory.appendingPathComponent(key.fileName + ".meta.json")),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData), meta.key == key.description,
              let data = try? Data(contentsOf: directory.appendingPathComponent(key.fileName + ".blob"))
        else { return nil }
        useCounter += 1
        let e = Entry(data: data, storedAt: meta.storedAt, lastUsed: useCounter)
        memory[key] = e
        evictIfNeeded()
        return e
    }

    private func evictIfNeeded() {
        while memory.count > memoryCapacity, let oldest = memory.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            memory[oldest] = nil
        }
    }
}
