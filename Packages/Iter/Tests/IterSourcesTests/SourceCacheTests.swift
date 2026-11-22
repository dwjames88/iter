import Foundation
import Testing
import IterModel
@testable import IterSources

@Suite("SourceCache")
struct SourceCacheTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let ttl: Duration = .seconds(600)
    static let open = LicenceTag(key: "test", mayStore: true)
    static let memoryOnly = LicenceTag(key: "test.nostore", mayStore: false)
    static func key(_ n: Int = 0) -> CacheKey { CacheKey(source: "test.source", kind: .forecast, cell: "c\(n)") }

    struct Payload: Codable, Sendable, Hashable { var n: Int }

    /// A temporary directory removed when the test ends.
    final class TempDir: Sendable {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("IterCacheTests-\(UUID().uuidString)")
        }
        deinit { try? FileManager.default.removeItem(at: url) }
        var files: [String] { (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] }
    }

    @Test func freshEntryIsServedWithoutFetching() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let cache = SourceCache(clock: clock)
        await cache.store(Payload(n: 1), for: Self.key(), licence: Self.open)
        clock.advance(by: .seconds(599))
        let calls = Counter()
        let hit = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) { calls.increment(); return Payload(n: 2) }
        #expect(hit.value == Payload(n: 1))
        #expect(hit.freshness == .fresh)
        #expect(hit.storedAt == Self.t0)
        #expect(calls.value == 0)
    }

    @Test func entryIsStaleExactlyAtTheTTL() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let cache = SourceCache(clock: clock)
        await cache.store(Payload(n: 1), for: Self.key(), licence: Self.open)
        clock.advance(by: Self.ttl)
        let hit = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) { Payload(n: 2) }
        #expect(hit.value == Payload(n: 1))
        #expect(hit.freshness == .stale(age: .seconds(600)))
        await cache.waitForBackgroundRefreshes()
        #expect(await cache.entry(Self.key(), as: Payload.self)?.value == Payload(n: 2))
    }

    @Test func staleEntryStartsExactlyOneBackgroundRefresh() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let cache = SourceCache(clock: clock)
        await cache.store(Payload(n: 1), for: Self.key(), licence: Self.open)
        clock.advance(by: .seconds(700))
        let calls = Counter()
        let gate = Gate()
        let fetch: @Sendable () async throws -> Payload = {
            calls.increment()
            await gate.wait()
            return Payload(n: 2)
        }
        let a = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open, fetch: fetch)
        let b = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open, fetch: fetch)
        let c = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open, fetch: fetch)
        for hit in [a, b, c] {
            #expect(hit.value == Payload(n: 1))
            #expect(hit.freshness == .stale(age: .seconds(700)))
        }
        gate.open()
        await cache.waitForBackgroundRefreshes()
        #expect(calls.value == 1)
        let after = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open, fetch: fetch)
        #expect(after.value == Payload(n: 2))
        #expect(after.freshness == .fresh)
        #expect(calls.value == 1)
    }

    @Test func concurrentMissesJoinOneFetch() async throws {
        let cache = SourceCache(clock: ManualSourceClock(now: Self.t0))
        let calls = Counter()
        let gate = Gate()
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) {
                        calls.increment()
                        await gate.wait()
                        return Payload(n: 42)
                    }.value.n
                }
            }
            _ = await eventually { calls.value >= 1 }
            for _ in 0..<20 { await Task.yield() }
            gate.open()
            var out: [Int] = []
            for try await v in group { out.append(v) }
            return out
        }
        #expect(values == Array(repeating: 42, count: 6))
        #expect(calls.value == 1)
    }

    @Test func failingRefreshKeepsTheOldEntry() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let cache = SourceCache(clock: clock)
        await cache.store(Payload(n: 1), for: Self.key(), licence: Self.open)
        clock.advance(by: .seconds(700))
        let hit = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) { () async throws -> Payload in throw SourceError.offline }
        #expect(hit.value == Payload(n: 1))
        await cache.waitForBackgroundRefreshes()
        let kept = await cache.entry(Self.key(), as: Payload.self)
        #expect(kept?.value == Payload(n: 1))
        #expect(kept?.storedAt == Self.t0)
        // The failure is not sticky: the next stale call refreshes again.
        let retry = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) { Payload(n: 3) }
        #expect(retry.value == Payload(n: 1))
        await cache.waitForBackgroundRefreshes()
        #expect(await cache.entry(Self.key(), as: Payload.self)?.value == Payload(n: 3))
    }

    @Test func failedMissThrowsAndCachesNothing() async throws {
        let cache = SourceCache(clock: ManualSourceClock(now: Self.t0))
        await #expect(throws: SourceError.offline) {
            try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) { () async throws -> Payload in throw SourceError.offline }
        }
        #expect(await cache.entry(Self.key(), as: Payload.self) == nil)
        let ok = try await cache.load(Self.key(), ttl: Self.ttl, licence: Self.open) { Payload(n: 5) }
        #expect(ok.value == Payload(n: 5))
    }

    @Test func mayStoreFalseNeverReachesDisk() async throws {
        let dir = TempDir()
        let cache = SourceCache(directory: dir.url, clock: ManualSourceClock(now: Self.t0))
        await cache.store(Payload(n: 1), for: Self.key(1), licence: Self.memoryOnly)
        await cache.storeBlob(Data("tile".utf8), for: Self.key(2), licence: Self.memoryOnly)
        _ = try await cache.load(Self.key(3), ttl: Self.ttl, licence: Self.memoryOnly) { Payload(n: 9) }
        #expect(dir.files.isEmpty)
        #expect(await cache.entry(Self.key(1), as: Payload.self)?.value == Payload(n: 1))
        #expect(await cache.blob(for: Self.key(2), maxAge: nil)?.data == Data("tile".utf8))
        let fresh = SourceCache(directory: dir.url, clock: ManualSourceClock(now: Self.t0))
        #expect(await fresh.entry(Self.key(1), as: Payload.self) == nil)
    }

    @Test func diskSurvivesANewInstance() async throws {
        let dir = TempDir()
        let clock = ManualSourceClock(now: Self.t0)
        let first = SourceCache(directory: dir.url, clock: clock)
        await first.store(Payload(n: 7), for: Self.key(), licence: Self.open)
        await first.storeBlob(Data([1, 2, 3]), for: Self.key(1), licence: Self.open)
        #expect(dir.files.count == 4)
        clock.advance(by: .seconds(30))
        let second = SourceCache(directory: dir.url, clock: clock)
        let e = await second.entry(Self.key(), as: Payload.self)
        #expect(e?.value == Payload(n: 7))
        #expect(e?.storedAt == Self.t0)
        #expect(await second.blob(for: Self.key(1), maxAge: .seconds(60))?.data == Data([1, 2, 3]))
        #expect(await second.blob(for: Self.key(1), maxAge: .seconds(10)) == nil)
        let calls = Counter()
        let hit = try await second.load(Self.key(), ttl: Self.ttl, licence: Self.open) { calls.increment(); return Payload(n: 8) }
        #expect(hit.freshness == .fresh)
        #expect(calls.value == 0)
    }

    @Test func leastRecentlyUsedEntryIsEvicted() async throws {
        let cache = SourceCache(memoryCapacity: 2, clock: ManualSourceClock(now: Self.t0))
        await cache.store(Payload(n: 1), for: Self.key(1), licence: Self.open)
        await cache.store(Payload(n: 2), for: Self.key(2), licence: Self.open)
        _ = await cache.entry(Self.key(1), as: Payload.self)
        await cache.store(Payload(n: 3), for: Self.key(3), licence: Self.open)
        #expect(await cache.memoryCount == 2)
        #expect(await cache.entry(Self.key(2), as: Payload.self) == nil)
        #expect(await cache.entry(Self.key(1), as: Payload.self)?.value == Payload(n: 1))
        #expect(await cache.entry(Self.key(3), as: Payload.self)?.value == Payload(n: 3))
    }

    @Test func evictedEntryComesBackFromDisk() async throws {
        let dir = TempDir()
        let cache = SourceCache(directory: dir.url, memoryCapacity: 1, clock: ManualSourceClock(now: Self.t0))
        await cache.store(Payload(n: 1), for: Self.key(1), licence: Self.open)
        await cache.store(Payload(n: 2), for: Self.key(2), licence: Self.open)
        #expect(await cache.entry(Self.key(1), as: Payload.self)?.value == Payload(n: 1))
    }

    @Test func purgeAndRemoveAll() async throws {
        let dir = TempDir()
        let clock = ManualSourceClock(now: Self.t0)
        let cache = SourceCache(directory: dir.url, clock: clock)
        await cache.store(Payload(n: 1), for: Self.key(1), licence: Self.open)
        clock.advance(by: .seconds(100))
        await cache.store(Payload(n: 2), for: Self.key(2), licence: Self.open)
        await cache.purge(olderThan: .seconds(50))
        #expect(await cache.entry(Self.key(1), as: Payload.self) == nil)
        #expect(await cache.entry(Self.key(2), as: Payload.self)?.value == Payload(n: 2))
        #expect(dir.files.count == 2)
        await cache.removeAll()
        #expect(await cache.entry(Self.key(2), as: Payload.self) == nil)
        #expect(dir.files.isEmpty)
    }

    // MARK: DataState

    static let descriptor = SourceCatalogue.metNorway

    func sourced(_ n: Int, at date: Date) -> Sourced<[Int]> {
        Sourced(value: [n], provenance: Self.descriptor.provenance(fetchedAt: date))
    }

    @Test func dataStateFreshStaleAndNone() async throws {
        let clock = ManualSourceClock(now: Self.t0)
        let cache = SourceCache(clock: clock)
        let key = Self.key()
        let calls = Counter()

        // Miss and offline: a named gap, no number.
        let none = await cache.dataState(key, descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in throw SourceError.offline }
        guard case .none(let reasons) = none else { Issue.record("expected .none"); return }
        #expect(reasons == [.offline(lastGood: nil)])

        // Miss and success: fresh.
        let t0 = Self.t0
        let first = await cache.dataState(key, descriptor: Self.descriptor) { calls.increment(); return Sourced(value: [1], provenance: Self.descriptor.provenance(fetchedAt: t0)) }
        #expect(first.isFresh)
        #expect(first.value == [1])

        // Within the TTL: fresh, no fetch.
        clock.advance(by: .seconds(100))
        let again = await cache.dataState(key, descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in calls.increment(); throw SourceError.offline }
        #expect(again.isFresh)
        #expect(calls.value == 1)

        // Past the TTL and the fetch fails: the old value, stale, with its age.
        clock.advance(by: .seconds(4000))
        let stale = await cache.dataState(key, descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in throw SourceError.http(status: 503, excerpt: nil) }
        guard case .stale(let s, let age) = stale else { Issue.record("expected .stale, got \(stale)"); return }
        #expect(s.value == [1])
        #expect(age == .seconds(4100))

        // Past the TTL with a working fetch: the old value comes back stale at once (stale-while-revalidate), the one
        // background refetch replaces it, and the next call is fresh without another fetch.
        await cache.waitForBackgroundRefreshes()
        let t1 = clock.now
        let refreshes = Counter()
        let served = await cache.dataState(key, descriptor: Self.descriptor) { refreshes.increment(); return Sourced(value: [2], provenance: Self.descriptor.provenance(fetchedAt: t1)) }
        #expect(served.isStale)
        #expect(served.value == [1])
        await cache.waitForBackgroundRefreshes()
        let renewed = await cache.dataState(key, descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in refreshes.increment(); throw SourceError.offline }
        #expect(renewed.isFresh)
        #expect(renewed.value == [2])
        #expect(refreshes.value == 1)
    }

    @Test func dataStateMapsOtherErrors() async throws {
        let cache = SourceCache(clock: ManualSourceClock(now: Self.t0))
        let rate = await cache.dataState(Self.key(1), descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in throw SourceError.rateLimited(retryAfter: nil) }
        #expect(rate.reasons == [.rateLimited(retryAfter: nil)])
        let outside = await cache.dataState(Self.key(2), descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in throw SourceError.outsideCoverage }
        #expect(outside.reasons == [.outsideCoverage])
        let http = await cache.dataState(Self.key(3), descriptor: Self.descriptor) { () async throws -> Sourced<[Int]> in throw SourceError.http(status: 500, excerpt: nil) }
        #expect(http.reasons == [.sourceError(Self.descriptor.id, "HTTP 500")])
    }
}
