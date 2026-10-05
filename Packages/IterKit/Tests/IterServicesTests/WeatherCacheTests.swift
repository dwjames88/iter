import Testing
import Foundation
import Synchronization
import IterCore
@testable import IterServices

private let moab = Coordinate(latitude: 38.5733, longitude: -109.5498)
private let yosemite = Coordinate(latitude: 37.7159, longitude: -119.6360)

private final class Clock: Sendable {
    private let t = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { t.withLock { $0 } }
    func advance(_ s: TimeInterval) { t.withLock { $0 = $0.addingTimeInterval(s) } }
}

private final class FakeProvider: WeatherProviding {
    let source: ForecastSource = .appleWeather
    private let calls = Mutex<[String]>([])
    private let behaviour: Mutex<@Sendable () throws -> Void>
    private let delay: Duration

    init(delay: Duration = .zero, failing: @escaping @Sendable () throws -> Void = {}) {
        self.delay = delay
        self.behaviour = Mutex(failing)
    }
    var callCount: Int { calls.withLock { $0.count } }
    func setBehaviour(_ b: @escaping @Sendable () throws -> Void) { behaviour.withLock { $0 = b } }

    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        calls.withLock { $0.append(coordinate.cacheKey) }
        if delay > .zero { try await Task.sleep(for: delay) }
        try behaviour.withLock { $0 }()
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: Date(), source: .appleWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

@Suite struct WeatherCacheTests {
    @Test func hitMissAndTTL() async throws {
        let clock = Clock(), base = FakeProvider()
        let cached = CachedWeatherService(wrapping: base, now: { clock.now })
        _ = try await cached.forecast(for: moab)
        _ = try await cached.forecast(for: moab)
        #expect(base.callCount == 1)
        _ = try await cached.forecast(for: yosemite)
        #expect(base.callCount == 2)
        clock.advance(29 * 60)
        _ = try await cached.forecast(for: moab)
        #expect(base.callCount == 2)
        clock.advance(2 * 60)
        _ = try await cached.forecast(for: moab)
        #expect(base.callCount == 3)
    }

    @Test func nearbyCoordinatesShareAKey() async throws {
        let base = FakeProvider()
        let cached = CachedWeatherService(wrapping: base)
        _ = try await cached.forecast(for: moab)
        _ = try await cached.forecast(for: Coordinate(latitude: moab.latitude + 0.0001, longitude: moab.longitude))
        #expect(base.callCount == 1)
    }

    @Test func concurrentRequestsCoalesce() async throws {
        let base = FakeProvider(delay: .milliseconds(100))
        let cached = CachedWeatherService(wrapping: base)
        try await withThrowingTaskGroup(of: Forecast.self) { group in
            for _ in 0..<20 { group.addTask { try await cached.forecast(for: moab) } }
            for try await _ in group {}
        }
        #expect(base.callCount == 1)
    }

    @Test func notEnabledIsRememberedForTenMinutes() async throws {
        let clock = Clock()
        let base = FakeProvider(failing: { throw WeatherError.notEnabled })
        let cached = CachedWeatherService(wrapping: base, now: { clock.now })
        for i in 0..<45 {
            let c = Coordinate(latitude: 30 + Double(i) * 0.1, longitude: -100)
            await #expect(throws: WeatherError.notEnabled) { try await cached.forecast(for: c) }
        }
        #expect(base.callCount == 1)
        clock.advance(11 * 60)
        await #expect(throws: WeatherError.notEnabled) { try await cached.forecast(for: moab) }
        #expect(base.callCount == 2)
    }

    @Test func otherFailuresAreNotCached() async throws {
        let base = FakeProvider(failing: { throw WeatherError.failed("offline") })
        let cached = CachedWeatherService(wrapping: base)
        await #expect(throws: WeatherError.failed("offline")) { try await cached.forecast(for: moab) }
        base.setBehaviour {}
        _ = try await cached.forecast(for: moab)
        #expect(base.callCount == 2)
    }

    @Test func invalidateClearsEverything() async throws {
        let base = FakeProvider()
        let cached = CachedWeatherService(wrapping: base)
        _ = try await cached.forecast(for: moab)
        await cached.invalidate()
        _ = try await cached.forecast(for: moab)
        #expect(base.callCount == 2)
    }

    @Test func sourceIsForwarded() {
        let cached = CachedWeatherService(wrapping: SampleWeatherService())
        #expect(cached.source == .sample)
    }

    @Test func errorMapping() {
        #expect(WeatherErrorMapping.map(WeatherError.notEnabled) == .notEnabled)
        let xpc = NSError(domain: NSCocoaErrorDomain, code: 4099, userInfo: [NSLocalizedDescriptionKey:
            "The connection to service named com.apple.weatherkit.authservice was invalidated"])
        #expect(WeatherErrorMapping.map(xpc) == .notEnabled)
        if case .failed = WeatherErrorMapping.map(URLError(.notConnectedToInternet)) {} else { Issue.record("expected .failed") }
    }
}
