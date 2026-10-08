import Testing
import Foundation
import IterCore
import IterAstro
@testable import IterLight
@testable import IterServices

/// Why the sample outlook shows 5s: overcast and rain regimes have 80-95% low cloud, which alone costs 50+ points at
/// golden hour, so the sum falls below the floor. These tests pin that the low scores come from the inputs and that
/// the breakdown names them (low cloud first), and that nothing is a default for missing data.
@Suite struct SampleOutlookScoresTests {
    private func outlook() async throws -> [(regime: SampleWeatherService.Regime, window: LightWindow, c: WindowConditions)] {
        let coordinate = Coordinate(latitude: 38.5733, longitude: -109.5498)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = try await SampleWeatherService(now: { now }).forecast(for: coordinate)
        let spot = Spot(id: "s", name: "s", locality: "", coordinate: coordinate, timeZoneIdentifier: "America/Denver",
                        category: .landscape, origin: .curated)
        let engine = LightEngine(ephemeris: Astronomy())
        var out: [(SampleWeatherService.Regime, LightWindow, WindowConditions)] = []
        for dl in engine.outlook(for: spot, from: LocalDay(now, in: spot.timeZone), days: 8, forecast: forecast, unavailable: nil, now: now) {
            for w in dl.windows where w.kind.isGolden && w.assessment.lightScore != nil {
                let c = try #require(LightEngine.conditions(in: forecast, over: w.span))
                out.append((SampleWeatherService.regime(for: coordinate, on: w.span.midpoint), w, c))
            }
        }
        return out
    }

    @Test func lowScoresComeFromLowCloudAndRain() async throws {
        let rows = try await outlook()
        #expect(!rows.isEmpty)
        for (regime, w, c) in rows {
            let s = try #require(w.assessment.lightScore)
            print("sample \(regime) \(w.kind.rawValue) score \(s.value) low/mid/high \(Int(c.low! * 100))/\(Int(c.mid! * 100))/\(Int(c.high! * 100)) pop \(Int((c.precipitationChance ?? 0) * 100)) vis \(Int((c.visibilityMeters ?? 0) / 1000))km factors \(s.contributors.map { "\($0.factor.rawValue)\($0.points)" })")
            if s.value <= 10 {
                #expect(c.low! >= 0.75, "a floor score needs heavy low cloud")
                let first = try #require(s.contributors.first)
                #expect(first.factor == .lowCloud && first.effect == .hurts)
            }
            if regime == .clear || regime == .partlyCloudy { #expect(s.value > 50) }
        }
    }
}
