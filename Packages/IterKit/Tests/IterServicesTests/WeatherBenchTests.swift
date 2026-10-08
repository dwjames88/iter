import Testing
import Foundation
import IterCore
@testable import IterServices

/// Parsing cost of the real and documented responses. Opt in with `ITER_BENCH=1`; prints a line per case.
@Suite("Weather parsing benchmark", .enabled(if: ProcessInfo.processInfo.environment["ITER_BENCH"] == "1", "ITER_BENCH=1"))
struct WeatherBenchTests {
    private func time(_ label: String, runs: Int = 200, _ work: () throws -> Void) rethrows {
        try work()   // warm up
        let start = ContinuousClock.now
        for _ in 0..<runs { try work() }
        let each = (ContinuousClock.now - start) / runs
        print("BENCH weather \(label): \(each.components.attoseconds / 1_000_000_000_000) us per parse")
    }

    @Test func openWeatherFixtures() throws {
        for name in openWeatherFixtureNames {
            let data = WeatherFixture.data(name)
            try time(name) { _ = try OpenWeatherMapping.map(data, coordinate: moabSpot, fetchedAt: Date()) }
        }
    }

    @Test func windyFixture() throws {
        let data = WeatherFixture.data("windy-gfs-documented-schema.json")
        try time("windy-gfs") { _ = try WindyMapping.map(data, coordinate: moabSpot, model: .gfs, fetchedAt: Date()) }
    }

    @Test func cacheRoundTrip() async throws {
        let f = try OpenWeatherMapping.map(WeatherFixture.data("openweather-onecall3-live-mesa-arch.json"), coordinate: moabSpot, fetchedAt: Date())
        let data = try JSONEncoder().encode(f)
        print("BENCH weather cache file: \(data.count) bytes")
        try time("disk-cache decode") { _ = try JSONDecoder().decode(Forecast.self, from: data) }
    }
}
