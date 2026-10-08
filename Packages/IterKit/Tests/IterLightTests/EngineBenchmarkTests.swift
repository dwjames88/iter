import Foundation
import Testing
import IterCore
import IterAstro
@testable import IterLight

/// Cost of the two calls every Explore row and every trip stop makes. Off by default; run with
/// `ITER_BENCH=1 swift test --filter EngineBenchmark` (add `-c release` for the optimised numbers).
/// Prints microseconds per call; asserts nothing about speed, so it cannot flake.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ITER_BENCH"] == "1"))
struct EngineBenchmark {
    static let zones = ["America/Denver", "America/Los_Angeles", "Europe/London", "Australia/Sydney", "Asia/Tokyo",
                        "Pacific/Auckland", "Europe/Oslo", "America/Phoenix"]

    static func spots(_ n: Int) -> [Spot] {
        var rng = SeededRNG(seed: 7)
        return (0..<n).map { i in
            let lat = Double(rng.next() % 12_000) / 100 - 60          // -60...60
            let lon = Double(rng.next() % 36_000) / 100 - 180
            return Spot(id: "b\(i)", name: "b\(i)", locality: "", coordinate: Coordinate(latitude: lat, longitude: lon),
                        timeZoneIdentifier: zones[i % zones.count], category: .landscape, origin: .user)
        }
    }

    static func forecast(for spot: Spot, from start: Date) -> Forecast {
        let hours = (0..<(8 * 24)).map { i in
            HourlyConditions(date: start.addingTimeInterval(Double(i) * 3600), cloudCover: 0.35, cloudLow: 0.05, cloudMid: 0.3, cloudHigh: 0.3,
                             precipitationChance: 0.1, visibilityMeters: 20_000, windSpeedKph: 5, temperatureC: 12, humidity: 0.5,
                             symbolName: "sun.max", condition: "clear")
        }
        return Forecast(coordinate: spot.coordinate, hours: hours, days: [], fetchedAt: start, source: .appleWeather)
    }

    static func microseconds(_ label: String, calls: Int, _ body: () -> Void) {
        body()   // warm up
        let clock = ContinuousClock()
        let elapsed = clock.measure(body)
        let us = Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12
        print(String(format: "BENCH %@: %.1f us/call (%d calls)", label, us / Double(calls), calls))
    }

    @Test func costPerCall() {
        let engine = LightEngine(ephemeris: Astronomy())
        let now = Date(timeIntervalSince1970: 1_791_000_000)   // 2026-10-03
        let spots = Self.spots(64)
        let forecasts = spots.map { Self.forecast(for: $0, from: now.addingTimeInterval(-3600)) }
        let rounds = 4
        let calls = spots.count * rounds
        Self.microseconds("nextEvent, no forecast", calls: calls) {
            for _ in 0..<rounds { for s in spots { _ = engine.nextEvent(for: s, forecast: nil, unavailable: .notLoaded, now: now) } }
        }
        Self.microseconds("nextEvent, 8-day forecast", calls: calls) {
            for _ in 0..<rounds { for (s, f) in zip(spots, forecasts) { _ = engine.nextEvent(for: s, forecast: f, unavailable: nil, now: now) } }
        }
        Self.microseconds("dayLight, 8-day forecast", calls: calls) {
            let day = LocalDay(now, in: utc)
            for _ in 0..<rounds { for (s, f) in zip(spots, forecasts) { _ = engine.dayLight(for: s, on: day, forecast: f, unavailable: nil, now: now) } }
        }
        Self.microseconds("outlook 8 days (per day)", calls: calls * 8) {
            let day = LocalDay(now, in: utc)
            for _ in 0..<rounds { for (s, f) in zip(spots, forecasts) { _ = engine.outlook(for: s, from: day, days: 8, forecast: f, unavailable: nil, now: now) } }
        }
        Self.microseconds("LocalDay(date,in:) + adding(days:)", calls: calls * 100) {
            var d = LocalDay(now, in: utc)
            for _ in 0..<(calls * 100) { d = d.adding(days: 1) }
            _ = d
        }
    }
}
