import Foundation
import MapKit
import Synchronization
import IterCore

/// Driving routes from `MKDirections`, cached per (from, to) pair, serialised with a minimum spacing, and retried
/// with backoff when MapKit answers "throttled". Identical in-flight requests share one fetch.
public actor MapKitDriveTimes: DriveTimeProviding {
    /// Fetches one real route. Throws `MapServiceError.throttled` to ask for a backoff, `.noRoute` when there is none.
    typealias Fetch = @Sendable (Coordinate, Coordinate) async throws -> DriveLeg
    typealias Sleep = @Sendable (Duration) async -> Void

    public static let maxPathPoints = 400

    private struct Key: Hashable, Sendable { var from: String; var to: String }

    private let fetch: Fetch
    private let sleep: Sleep
    private let minimumSpacing: Duration
    private let backoffs: [Duration]
    private let capacity = 1000

    // The cache is readable synchronously from any context (`cachedLeg`), hence a Mutex instead of actor state.
    private let cache = Mutex<[Key: DriveLeg]>([:])
    private var inflight: [Key: Task<DriveLeg, any Error>] = [:]

    // Serialisation gate: one request at a time, spaced by `minimumSpacing`.
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastRequestStart: ContinuousClock.Instant?

    public init(minimumSpacing: Duration = .milliseconds(200), backoffs: [Duration] = [.seconds(2), .seconds(5)]) {
        self.init(minimumSpacing: minimumSpacing, backoffs: backoffs,
                  sleep: { try? await Task.sleep(for: $0) },
                  fetch: { try await Self.fetchFromMapKit(from: $0, to: $1) })
    }

    init(minimumSpacing: Duration, backoffs: [Duration], sleep: @escaping Sleep, fetch: @escaping Fetch) {
        self.minimumSpacing = minimumSpacing
        self.backoffs = backoffs
        self.sleep = sleep
        self.fetch = fetch
    }

    /// A previously fetched leg for this pair, without any request. Never returns an estimate.
    public nonisolated func cachedLeg(from a: Coordinate, to b: Coordinate) -> DriveLeg? {
        let key = Key(from: a.cacheKey, to: b.cacheKey)
        return cache.withLock { $0[key] }
    }

    public func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        let key = Key(from: a.cacheKey, to: b.cacheKey)
        if let hit = cachedLeg(from: a, to: b) { return hit }
        if let running = inflight[key] { return try await running.value }

        // Unstructured: shared by all waiters, so one caller cancelling does not cancel the fetch for the others.
        let task = Task { try await self.fetchSerialised(from: a, to: b) }
        inflight[key] = task
        defer { inflight[key] = nil }
        let leg = try await task.value
        store(leg, for: key)
        return leg
    }

    private func store(_ leg: DriveLeg, for key: Key) {
        cache.withLock { cache in
            if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
            cache[key] = leg
        }
    }

    // MARK: Serialisation and backoff

    private func fetchSerialised(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        var attempt = 0
        while true {
            await acquire()
            do {
                let leg = try await fetch(a, b)
                release()
                return leg
            } catch MapServiceError.throttled {
                release()
                guard attempt < backoffs.count else { throw MapServiceError.throttled }
                await sleep(backoffs[attempt])
                attempt += 1
            } catch {
                release()
                throw error
            }
        }
    }

    private func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        // Space requests: wait out the remainder of the minimum gap since the previous one started.
        if let last = lastRequestStart {
            let elapsed = ContinuousClock.now - last
            if elapsed < minimumSpacing { await sleep(minimumSpacing - elapsed) }
        }
        lastRequestStart = .now
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()   // ownership passes to the next waiter; `busy` stays true
        }
    }

    // MARK: MapKit

    private static func fetchFromMapKit(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: a.latitude, longitude: a.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: b.latitude, longitude: b.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw MapServiceError.noRoute }
            let path = MapKitMapping.downsample(MapKitMapping.coordinates(of: route.polyline), maxPoints: maxPathPoints)
            return DriveLeg(from: a, to: b, seconds: route.expectedTravelTime, meters: route.distance, isEstimate: false,
                            path: path.isEmpty ? [a, b] : path)
        } catch let error as MKError {
            switch error.code {
            case .loadingThrottled: throw MapServiceError.throttled
            case .directionsNotFound: throw MapServiceError.noRoute
            default: throw error
            }
        }
    }
}
