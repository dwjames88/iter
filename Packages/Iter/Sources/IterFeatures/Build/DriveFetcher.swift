import Foundation
import IterModel
import IterPlan
import IterSources

/// The builder's drive lookups: a cache keyed by pair and departure bucket, requests spaced at least `spacing` apart with at
/// most `maxInFlight` running, passing failures retried on the old backoff, and everything cancelled on `stop()`.
///
/// A pair with a departure time inside the traffic horizon is asked for twice: once with no departure (the typical drive,
/// which fixes the plan the leave-by is worked from) and once with the planned leave time rounded down to a half hour (the
/// traffic-aware drive). A known (pair, bucket) is never asked for again.
@MainActor
final class DriveFetcher {
    struct Key: Hashable, Sendable {
        var leg: LegKey
        /// Half hours since 1970 of the departure; nil for the typical drive.
        var bucket: Int?
    }

    struct Want: Equatable, Sendable {
        var key: Key
        var from: Coordinate
        var to: Coordinate
        /// The bucket's start; nil for the typical drive.
        var departing: Date?
    }

    struct Entry {
        var from: Coordinate
        var to: Coordinate
        var route: Route
    }

    enum Fetch: Equatable {
        case queued
        case loading
        case failed(attempt: Int, retryAt: Date)
        case noRoute
    }

    struct Request: Equatable, Sendable {
        var from: Coordinate
        var to: Coordinate
        var departing: Date?
    }

    static let bucketSeconds: TimeInterval = 1800

    static func bucket(of date: Date) -> Int { Int((date.timeIntervalSince1970 / bucketSeconds).rounded(.down)) }
    static func start(ofBucket bucket: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(bucket) * bucketSeconds) }

    private let routing: any RoutingProvider
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private let backoff: DriveRetryBackoff
    private let spacing: Duration
    let maxInFlight: Int

    private(set) var cache: [Key: Entry] = [:]
    private(set) var fetches: [Key: Fetch] = [:]
    private var wanted: [Key: Want] = [:]
    private var coordinates: [Key: Request] = [:]
    private var queue: [Key] = []
    private var running: [Key: Task<Void, Never>] = [:]
    private var timers: [Key: Task<Void, Never>] = [:]
    private var attempts: [Key: Int] = [:]
    private var gateOpen = true
    private var gateTask: Task<Void, Never>?
    private var stopped = false

    /// How many lookups were started, and each one (tests, the perf counters).
    private(set) var requestCount = 0
    private(set) var requests: [Request] = []
    private(set) var peakInFlight = 0
    var onChange: (() -> Void)?

    init(routing: any RoutingProvider, backoff: DriveRetryBackoff = .standard, spacing: Duration = .milliseconds(200),
         maxInFlight: Int = 2, now: @escaping @Sendable () -> Date, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.routing = routing
        self.backoff = backoff
        self.spacing = spacing
        self.maxInFlight = max(1, maxInFlight)
        self.now = now
        self.sleep = sleep
    }

    var inFlightCount: Int { running.count }

    /// Any of these lookups is queued or running.
    func isLoading(_ list: [Want]) -> Bool {
        list.contains { fetches[$0.key] == .queued || fetches[$0.key] == .loading }
    }

    // MARK: Reading

    func leg(for key: Key, from: Coordinate, to: Coordinate) -> Leg? {
        guard let entry = cache[key], entry.from == from, entry.to == to else { return nil }
        let route = entry.route
        return Leg(from: from, to: to, seconds: route.seconds, meters: route.meters, isEstimate: route.isEstimate, path: route.path)
    }

    /// The lookup state of a key the plan wants, for the row.
    func state(of key: Key, from: Coordinate, to: Coordinate) -> DriveLegState {
        if leg(for: key, from: from, to: to) != nil { return .ready }
        switch fetches[key] {
        case .noRoute: return .noRoute
        case .failed(_, let retryAt): return .failed(retryAt: retryAt)
        case .queued, .loading, nil: return .loading
        }
    }

    // MARK: Asking

    /// Replaces what the plan wants. Queued lookups nobody wants any more are dropped; running ones finish into the cache.
    func want(_ list: [Want]) {
        stopped = false
        wanted = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        queue.removeAll { wanted[$0] == nil }
        for want in list {
            let key = want.key
            let request = Request(from: want.from, to: want.to, departing: want.departing)
            if let known = coordinates[key], known.from != want.from || known.to != want.to {
                // One of the two places moved: nothing known about this pair holds.
                cache[key] = nil
                fetches[key] = nil
                running[key]?.cancel()
                running[key] = nil
                timers[key]?.cancel()
                timers[key] = nil
                attempts[key] = nil
                queue.removeAll { $0 == key }
            }
            coordinates[key] = request
            if leg(for: key, from: want.from, to: want.to) != nil { continue }
            if fetches[key] != nil { continue }
            fetches[key] = .queued
            queue.append(key)
        }
        pump()
    }

    /// Cancels every running lookup, retry timer and the spacing gate. The cache stays.
    func stop() {
        stopped = true
        for task in running.values { task.cancel() }
        for task in timers.values { task.cancel() }
        gateTask?.cancel()
        for (key, fetch) in fetches where fetch == .loading || fetch == .queued { fetches[key] = nil }
        running = [:]
        timers = [:]
        queue = []
        gateTask = nil
        gateOpen = true
        wanted = [:]
    }

    /// Puts a lookup's answer in the cache without asking (previews and tests).
    func seed(_ key: Key, from: Coordinate, to: Coordinate, route: Route) {
        cache[key] = Entry(from: from, to: to, route: route)
        coordinates[key] = Request(from: from, to: to, departing: nil)
        fetches[key] = nil
    }

    /// Marks a lookup as in a given state without asking (previews and tests).
    func seed(_ key: Key, from: Coordinate, to: Coordinate, fetch: Fetch) {
        coordinates[key] = Request(from: from, to: to, departing: nil)
        fetches[key] = fetch
    }

    // MARK: Running

    private func pump() {
        guard !stopped else { return }
        while running.count < maxInFlight, gateOpen, let key = queue.first {
            queue.removeFirst()
            guard let want = wanted[key], fetches[key] == .queued else { continue }
            start(want)
        }
    }

    private func start(_ want: Want) {
        let key = want.key
        requestCount += 1
        requests.append(Request(from: want.from, to: want.to, departing: want.departing))
        fetches[key] = .loading
        let routing = self.routing
        running[key] = Task { [weak self] in
            do {
                let route = try await routing.route(from: want.from, to: want.to, departing: want.departing)
                self?.finish(want, .success(route))
            } catch {
                self?.finish(want, .failure(error))
            }
        }
        peakInFlight = max(peakInFlight, running.count)
        if spacing > .zero {
            gateOpen = false
            let sleep = self.sleep
            let spacing = self.spacing
            gateTask = Task { [weak self] in
                do { try await sleep(spacing) } catch { return }
                guard !Task.isCancelled else { return }
                self?.openGate()
            }
        }
    }

    private func openGate() {
        gateOpen = true
        gateTask = nil
        pump()
    }

    private func finish(_ want: Want, _ result: Result<Route, any Error>) {
        let key = want.key
        // A lookup that was cancelled (the plan changed, the builder closed) or replaced is not this one's to record.
        guard fetches[key] == .loading, !stopped else { return }
        running[key] = nil
        switch result {
        case .success(let route):
            cache[key] = Entry(from: want.from, to: want.to, route: route)
            fetches[key] = nil
            attempts[key] = nil
        case .failure(let error):
            if Self.isCancellation(error) {
                fetches[key] = nil
            } else if Self.isFinal(error) {
                fetches[key] = .noRoute
            } else {
                let attempt = attempts[key] ?? 0
                attempts[key] = attempt + 1
                let delay = backoff.delay(forAttempt: attempt)
                fetches[key] = .failed(attempt: attempt, retryAt: now().addingTimeInterval(delay))
                scheduleRetry(key, after: delay)
            }
        }
        onChange?()
        pump()
    }

    private func scheduleRetry(_ key: Key, after delay: TimeInterval) {
        let sleep = self.sleep
        timers[key]?.cancel()
        timers[key] = Task { [weak self] in
            do { try await sleep(.seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.retry(key)
        }
    }

    private func retry(_ key: Key) {
        timers[key] = nil
        guard case .failed = fetches[key], wanted[key] != nil else { return }
        fetches[key] = .queued
        queue.append(key)
        onChange?()
        pump()
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if case SourceError.cancelled = error { return true }
        return false
    }

    /// No road route exists for this pair, so asking again would not help.
    static func isFinal(_ error: any Error) -> Bool {
        guard let source = error as? SourceError else { return false }
        switch source {
        case .http(let status, _): return status == 404
        case .invalidRequest, .outsideCoverage: return true
        default: return false
        }
    }
}
