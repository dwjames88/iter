import Foundation
import Synchronization
import IterCore

/// A per-spot, per-hour forecast cache for one provider.
///
/// Key = coordinate rounded to 2 decimal places (about 1 km) plus the UTC hour bucket the forecast was fetched in.
/// With `.throughNextClockHour` a forecast fetched in hour H is served during H and H+1 (so 1–2 hours). With
/// `.interval` it is served for that many seconds. With a `directory` entries persist as JSON and survive a relaunch
/// (OpenWeather; ODbL allows it). Without one the cache is memory only (Windy: its terms forbid storing the data).
/// Concurrent requests for one spot share one fetch.
public actor ProviderCache {
    public enum Validity: Hashable, Sendable {
        case throughNextClockHour
        case interval(TimeInterval)
    }

    private struct Entry { var forecast: Forecast; var bucket: Int }

    private let directory: URL?
    private let validity: Validity
    private let now: @Sendable () -> Date
    private var memory: [String: Entry] = [:]
    private var inflight: [String: Task<Forecast, any Error>] = [:]

    public init(directory: URL?, validity: Validity, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.validity = validity
        self.now = now
    }

    /// The hour bucket (hours since 1970, UTC).
    static func bucket(of date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 3600)) }

    /// "38.57,-109.55", 2 dp.
    static func spotKey(_ c: Coordinate) -> String { String(format: "%.2f,%.2f", c.latitude, c.longitude) }

    private func fileName(spot: String, bucket: Int) -> String {
        spot.replacingOccurrences(of: ",", with: "_") + "@\(bucket).json"
    }

    private func isFresh(_ entry: Entry, at date: Date) -> Bool {
        switch validity {
        case .throughNextClockHour:
            return Self.bucket(of: date) - entry.bucket <= 1 && date >= entry.forecast.fetchedAt.addingTimeInterval(-60)
        case .interval(let ttl):
            let age = date.timeIntervalSince(entry.forecast.fetchedAt)
            return age >= -60 && age < ttl
        }
    }

    private var lookback: Int {
        switch validity {
        case .throughNextClockHour: 1
        case .interval(let ttl): Int(ceil(ttl / 3600)) + 1
        }
    }

    /// A fresh cached forecast for the spot, or nil.
    public func cached(for coordinate: Coordinate) -> Forecast? {
        let spot = Self.spotKey(coordinate)
        let current = now()
        let nowBucket = Self.bucket(of: current)
        for back in 0...lookback {
            let b = nowBucket - back
            let key = "\(spot)|\(b)"
            if let e = memory[key], isFresh(e, at: current) { return e.forecast }
            if let loaded = load(spot: spot, bucket: b), isFresh(loaded, at: current) {
                memory[key] = loaded
                return loaded.forecast
            }
        }
        return nil
    }

    /// Serves the cache, else runs `fetch` once (shared by concurrent callers) and stores the result.
    /// Errors are not cached.
    public func forecast(for coordinate: Coordinate, fetch: @escaping @Sendable () async throws -> Forecast) async throws -> Forecast {
        if let hit = cached(for: coordinate) { return hit }
        let spot = Self.spotKey(coordinate)
        if let running = inflight[spot] { return try await running.value }
        // Unstructured on purpose: one caller cancelling must not cancel the fetch the others wait on.
        let task = Task { try await fetch() }
        inflight[spot] = task
        do {
            let forecast = try await task.value
            inflight[spot] = nil
            store(forecast, spot: spot)
            return forecast
        } catch {
            inflight[spot] = nil
            throw error
        }
    }

    public func removeAll() {
        memory.removeAll()
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: Storage

    private func store(_ forecast: Forecast, spot: String) {
        let bucket = Self.bucket(of: forecast.fetchedAt)
        memory["\(spot)|\(bucket)"] = Entry(forecast: forecast, bucket: bucket)
        prune()
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(forecast)
            try data.write(to: directory.appendingPathComponent(fileName(spot: spot, bucket: bucket)), options: .atomic)
        } catch {
            // A cache that cannot persist is still a working cache.
        }
        pruneFiles(directory)
    }

    private func load(spot: String, bucket: Int) -> Entry? {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(fileName(spot: spot, bucket: bucket))),
              let forecast = try? JSONDecoder().decode(Forecast.self, from: data) else { return nil }
        return Entry(forecast: forecast, bucket: bucket)
    }

    private func prune() {
        let oldest = Self.bucket(of: now()) - lookback - 1
        memory = memory.filter { $0.value.bucket >= oldest }
    }

    private func pruneFiles(_ directory: URL) {
        let oldest = Self.bucket(of: now()) - lookback - 1
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" {
            let name = f.deletingPathExtension().lastPathComponent
            if let at = name.lastIndex(of: "@"), let b = Int(name[name.index(after: at)...]), b < oldest {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}

/// Counts provider calls per UTC day and refuses to go past a cap, so the free allowance is never exceeded by accident.
/// Counts persist in the injected UserDefaults (they are counts, not secrets). Check with `reserve` BEFORE the
/// network call; cache hits never reach it.
public final class CallBudget: Sendable {
    public static let defaultCaps: [ForecastSource: Int] = [.openWeather: 800, .windy: 400]

    // UserDefaults is documented thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let caps: Mutex<[ForecastSource: Int]>

    public init(defaults: UserDefaults, caps: [ForecastSource: Int] = CallBudget.defaultCaps, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        self.caps = Mutex(caps)
    }

    public func cap(for source: ForecastSource) -> Int? { caps.withLock { $0[source] } }
    public func setCap(_ cap: Int?, for source: ForecastSource) { caps.withLock { $0[source] = cap } }

    /// Calls made today (UTC) to `source`.
    public func callsToday(for source: ForecastSource) -> Int {
        let today = utcDay()
        let stored = defaults.dictionary(forKey: storageKey(source))
        guard stored?["day"] as? String == today else { return 0 }
        return stored?["count"] as? Int ?? 0
    }

    /// Counts one call, or throws `overDailyLimit` (without counting) when the cap is already reached.
    public func reserve(_ source: ForecastSource) throws {
        try caps.withLock { caps in
            let used = callsToday(for: source)
            if let cap = caps[source], used >= cap { throw WeatherError.overDailyLimit(source) }
            defaults.set(["day": utcDay(), "count": used + 1], forKey: storageKey(source))
        }
    }

    private func storageKey(_ source: ForecastSource) -> String { "iter.weather.calls.\(source.rawValue)" }

    private func utcDay() -> String {
        let t = Int(floor(now().timeIntervalSince1970 / 86400))
        let c = Date(timeIntervalSince1970: Double(t) * 86400)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let p = cal.dateComponents([.year, .month, .day], from: c)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
}
