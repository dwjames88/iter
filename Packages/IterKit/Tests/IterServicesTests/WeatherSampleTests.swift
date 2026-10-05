import Testing
import Foundation
import IterCore
@testable import IterServices

private let places: [Coordinate] = [
    Coordinate(latitude: 38.5733, longitude: -109.5498),
    Coordinate(latitude: 37.7159, longitude: -119.6360),
    Coordinate(latitude: 64.1466, longitude: -21.9426),
    Coordinate(latitude: -33.8688, longitude: 151.2093),
]
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct WeatherSampleTests {
    @Test func isDeterministic() async throws {
        let a = try await SampleWeatherService(now: { now }).forecast(for: places[0])
        let b = try await SampleWeatherService(now: { now }).forecast(for: places[0])
        #expect(a == b)
        #expect(a.source == .sample)
        #expect(await SampleWeatherService().attribution() == nil)
    }

    @Test func differsByCoordinate() async throws {
        let a = try await SampleWeatherService(now: { now }).forecast(for: places[0])
        let b = try await SampleWeatherService(now: { now }).forecast(for: places[2])
        #expect(a.hours.map(\.cloudCover) != b.hours.map(\.cloudCover))
    }

    @Test func coversTenDaysHourly() async throws {
        let f = try await SampleWeatherService(now: { now }).forecast(for: places[0])
        #expect(f.hours.count >= 240)
        #expect(f.hours.first!.date <= now)
        #expect(f.horizon! >= now.addingTimeInterval(10 * 86400))
        #expect(f.days.count >= 10)
        for (a, b) in zip(f.hours, f.hours.dropFirst()) { #expect(b.date.timeIntervalSince(a.date) == 3600) }
    }

    @Test func valuesArePlausible() async throws {
        for p in places {
            let f = try await SampleWeatherService(now: { now }).forecast(for: p)
            for h in f.hours {
                #expect((0...1).contains(h.cloudCover))
                #expect((0...1).contains(h.precipitationChance))
                #expect((0...1).contains(h.humidity))
                #expect((0...1).contains(h.cloudLow ?? 0) && (0...1).contains(h.cloudMid ?? 0) && (0...1).contains(h.cloudHigh ?? 0))
                #expect(h.visibilityMeters > 0 && h.windSpeedKph >= 0)
                #expect(h.temperatureC > -40 && h.temperatureC < 55)
                #expect(!h.symbolName.isEmpty && !h.condition.isEmpty)
            }
            for d in f.days { #expect(d.highC >= d.lowC) }
        }
    }

    @Test func everySkyRegimeAppears() async throws {
        for p in places {
            let f = try await SampleWeatherService(now: { now }).forecast(for: p)
            var clear = false, colour = false, overcast = false, rain = false, fog = false
            for h in f.hours {
                if h.cloudCover < 0.15 && h.precipitationChance < 0.1 { clear = true }
                if (h.cloudHigh ?? 0) > 0.6 && (h.cloudLow ?? 1) < 0.15 { colour = true }
                if h.cloudCover > 0.9 && h.precipitationChance < 0.3 { overcast = true }
                if h.precipitationChance > 0.6 { rain = true }
                if h.visibilityMeters < 1500 { fog = true }
            }
            #expect(clear && colour && overcast && rain && fog, "missing a regime at \(p)")
        }
    }

    @Test func tenConsecutiveDaysContainAllSixRegimes() {
        for p in places {
            let regimes = (0..<10).map { SampleWeatherService.regime(for: p, on: now.addingTimeInterval(Double($0) * 86400)) }
            #expect(Set(regimes).count == SampleWeatherService.Regime.allCases.count)
        }
    }

    @Test func daytimeIsWarmerThanNight() async throws {
        let f = try await SampleWeatherService(now: { now }).forecast(for: places[0])
        let byDay = Dictionary(grouping: f.hours) { SampleWeatherService.dayIndex(of: $0.date, longitude: places[0].longitude) }
        let swings = byDay.values.filter { $0.count == 24 }.map { hs in hs.map(\.temperatureC).max()! - hs.map(\.temperatureC).min()! }
        #expect(swings.count >= 8)
        #expect(swings.allSatisfy { $0 > 1 })
    }
}
