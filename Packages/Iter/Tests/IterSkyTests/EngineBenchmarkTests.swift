import Foundation
import Testing
import IterModel
import IterAstro
@testable import IterSky

/// Cost of the two calls every Explore row and every trip stop makes. Off by default; run with
/// `ITER_BENCH=1 swift test --filter EngineBenchmark` (add `-c release` for the optimised numbers).
/// Prints microseconds per call; asserts nothing about speed, so it cannot flake.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ITER_BENCH"] == "1"))
struct EngineBenchmark {
    static let zones = ["America/Denver", "America/Los_Angeles", "Europe/London", "Australia/Sydney", "Asia/Tokyo",
                        "Pacific/Auckland", "Europe/Oslo", "America/Phoenix"]

    static func places(_ n: Int) -> [Place] {
        var rng = SeededRNG(seed: 7)
        return (0..<n).map { i in
            let lat = Double(rng.next() % 12_000) / 100 - 60          // -60...60
            let lon = Double(rng.next() % 36_000) / 100 - 180
            return makePlace("b\(i)", lat: lat, lon: lon, zone: zones[i % zones.count])
        }
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
        let places = Self.places(64)
        let inputs = places.map { eightDayInputs(for: $0, from: now.addingTimeInterval(-3600)) }
        let rounds = 4
        let calls = places.count * rounds
        Self.microseconds("nextEvent, no forecast", calls: calls) {
            for _ in 0..<rounds { for s in places { _ = engine.nextEvent(for: s, inputs: nil, unavailable: [], now: now) } }
        }
        Self.microseconds("nextEvent, 8-day forecast", calls: calls) {
            for _ in 0..<rounds { for (s, f) in zip(places, inputs) { _ = engine.nextEvent(for: s, inputs: f, now: now) } }
        }
        Self.microseconds("dayLight, 8-day forecast", calls: calls) {
            let day = LocalDay(now, in: utc)
            for _ in 0..<rounds { for (s, f) in zip(places, inputs) { _ = engine.dayLight(for: s, on: day, inputs: f, now: now) } }
        }
        Self.microseconds("outlook 8 days (per day)", calls: calls * 8) {
            let day = LocalDay(now, in: utc)
            for _ in 0..<rounds { for (s, f) in zip(places, inputs) { _ = engine.outlook(for: s, from: day, days: 8, inputs: f, now: now) } }
        }
        Self.microseconds("LocalDay(date,in:) + adding(days:)", calls: calls * 100) {
            var d = LocalDay(now, in: utc)
            for _ in 0..<(calls * 100) { d = d.adding(days: 1) }
            _ = d
        }
    }
}
