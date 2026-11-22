import Testing
import Foundation
import IterCore
import IterLight
@testable import IterServices

// The plan's light rules, checked against forecasts that came through each provider's REAL mapping:
//  1. An overcast golden hour never scores Good or better.
//  2. A night window can never lift a sunset or sunrise headline.
//  3. No forecast means no score, including every provider's error states.

private let utc = TimeZone(identifier: "UTC")!
private let day = LocalDay(year: 2026, month: 10, day: 12)
private let dayBefore = day.adding(days: -1)
/// Noon the day before: every window of `day` is in the future.
private let now = day.adding(days: -1).start(in: utc).addingTimeInterval(12 * 3600)
private let spot = Spot(id: "rules", name: "Rules", locality: "", coordinate: Coordinate(latitude: 38.5733, longitude: -109.5498),
                        timeZoneIdentifier: "UTC", category: .landscape, origin: .user)

private struct FixedEphemeris: Ephemeris {
    var moonAltitude = -30.0
    var illumination = 0.0

    static func at(_ day: LocalDay, _ hour: Double) -> Date { day.start(in: utc).addingTimeInterval(hour * 3600) }

    /// Sunrise 06:12, golden evening from 17:30, sunset 18:20, night 20:10 to 23:10 (every day).
    func sunEvents(on d: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents {
        let at = { Self.at(d, $0) }
        return SunEvents(day: d, kind: .normal, solarNoon: at(12.0),
                         astronomicalDawn: at(4.5), nauticalDawn: at(5.17), civilDawn: at(5.67),
                         sunrise: at(6.2), goldenMorningEnd: at(7.0), goldenEveningStart: at(17.5),
                         sunset: at(18.333), civilDusk: at(18.833), nauticalDusk: at(19.5), astronomicalDusk: at(20.167))
    }
    func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { SkyPosition(altitude: 10, azimuth: 90) }
    func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { SkyPosition(altitude: moonAltitude, azimuth: 180) }
    func moonPhase(at date: Date) -> MoonPhase { MoonPhase(illumination: illumination, cycle: illumination / 2) }
    func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents { MoonEvents(day: day, rise: nil, set: nil) }
}

/// Cloud cover 0-1 by UTC hour of day.
private typealias Sky = @Sendable (Int) -> Double

private enum Provider: String, CaseIterable, CustomStringConvertible {
    case apple, openWeather, windy
    var description: String { rawValue }
}

private let start = dayBefore.start(in: utc)

/// A forecast for `day` and the day either side from `provider`, with total cloud following `sky` and nothing else bad
/// (no rain, 20 km visibility), built through the provider's mapping.
private func forecast(_ provider: Provider, sky: @escaping Sky) throws -> Forecast {
    switch provider {
    case .apple:
        // WeatherKit gives layers; set them all to the same value so the total equals the sky.
        let hours = (0..<72).map { i -> HourlyConditions in
            let c = sky(i % 24)
            return HourlyConditions(date: start.addingTimeInterval(Double(i) * 3600), cloudCover: c, cloudLow: c, cloudMid: c, cloudHigh: c,
                                    precipitationChance: 0, precipitationMm: 0, visibilityMeters: 20_000, windSpeedKph: 5,
                                    temperatureC: 12, humidity: 0.5, symbolName: "sun.max", condition: "clear")
        }
        return Forecast(coordinate: spot.coordinate, hours: hours, days: [], fetchedAt: now, source: .appleWeather)

    case .openWeather:
        var json = WeatherFixture.json("openweather-onecall3-documented.json")
        var hourly = json["hourly"] as! [[String: Any]]
        for i in hourly.indices {
            let c = sky(i % 24)
            hourly[i]["dt"] = Int(start.timeIntervalSince1970) + 3600 * i
            hourly[i]["clouds"] = Int((c * 100).rounded())
            hourly[i]["pop"] = 0
            hourly[i]["rain"] = nil
            hourly[i]["visibility"] = 10_000
            hourly[i]["weather"] = [["id": c > 0.8 ? 804 : c < 0.15 ? 800 : 803, "icon": "04d"]]
        }
        json["hourly"] = hourly
        json["daily"] = nil
        json["current"] = nil
        return try OpenWeatherMapping.map(WeatherFixture.encode(json), coordinate: spot.coordinate, fetchedAt: now)

    case .windy:
        var json = WeatherFixture.json("windy-gfs-documented-schema.json")
        let steps = 24    // three days at three hours
        let tsMs = (0..<steps).map { Double((Int(start.timeIntervalSince1970) + 3 * 3600 * $0) * 1000) }
        json["ts"] = tsMs
        for key in json.keys where key.hasSuffix("-surface") { json[key] = Array((json[key] as! [Any]).prefix(steps)) }
        let pct = (0..<steps).map { sky(($0 * 3) % 24) * 100 }
        for k in ["lclouds-surface", "mclouds-surface", "hclouds-surface"] { json[k] = pct }
        json["past3hprecip-surface"] = [Double](repeating: 0, count: steps)
        json["visibility-surface"] = [Double](repeating: 20_000, count: steps)
        // A Professional-key forecast: the service would only return this after the testing-key check passed.
        return try WindyMapping.map(WeatherFixture.encode(json), coordinate: spot.coordinate, model: .gfs, fetchedAt: now).forecast
    }
}

private func windows(_ f: Forecast?, unavailable: ForecastUnavailableReason? = nil, moonAltitude: Double = -30, illumination: Double = 0) -> DayLight {
    LightEngine(ephemeris: FixedEphemeris(moonAltitude: moonAltitude, illumination: illumination))
        .dayLight(for: spot, on: day, forecast: f, unavailable: unavailable, now: now)
}

@Suite("Provider light rules") struct ProviderLightRulesTests {
    @Test("the fixtures reach the engine as real forecasts", arguments: Provider.allCases)
    private func forecastsCoverTheWindows(_ p: Provider) throws {
        let f = try forecast(p) { _ in 0.2 }
        let light = windows(f)
        #expect(light.windows.count == 5)
        #expect(light.windows.allSatisfy { $0.score != nil })
        let expected: ForecastSource = p == .apple ? .appleWeather : p == .openWeather ? .openWeather : .windy
        #expect(light.windows.allSatisfy { $0.assessment.lightScore?.source == expected })
    }

    @Test("an overcast golden hour never scores Good or better", arguments: Provider.allCases)
    private func overcastGoldenHour(_ p: Provider) throws {
        let f = try forecast(p) { _ in 1.0 }
        let light = windows(f)
        for kind in [LightWindowKind.goldenEvening, .goldenMorning] {
            let score = try #require(light.window(kind)?.assessment.lightScore)
            #expect(score.band < .good, "\(p) \(kind): \(score.value)")
        }
        #expect(try #require(light.headline(for: .sunset)?.assessment.lightScore).band < .good)
        #expect(try #require(light.headline(for: .sunrise)?.assessment.lightScore).band < .good)
    }

    @Test("cloud that clears only after sunset still does not make a Good sunset", arguments: Provider.allCases)
    private func overcastUntilDusk(_ p: Provider) throws {
        let f = try forecast(p) { $0 < 20 ? 1.0 : 0.0 }
        let light = windows(f, moonAltitude: 40, illumination: 1)
        let golden = try #require(light.window(.goldenEvening)?.assessment.lightScore)
        #expect(golden.band < .good)
    }

    @Test("a bright clear night cannot lift the sunset or sunrise headline", arguments: Provider.allCases)
    private func nightCannotLiftDaytimeHeadlines(_ p: Provider) throws {
        // Overcast all day, then a clear night with a high full moon.
        let f = try forecast(p) { ($0 >= 20 || $0 < 4) ? 0.0 : 1.0 }
        let light = windows(f, moonAltitude: 50, illumination: 1)
        let night = try #require(light.window(.night))
        let golden = try #require(light.window(.goldenEvening))
        let sunrise = try #require(light.window(.goldenMorning))
        #expect(night.score != nil && golden.score != nil)
        for (intent, window) in [(LightIntent.sunset, golden), (.sunrise, sunrise)] {
            let headline = try #require(light.headline(for: intent))
            #expect(headline.kind == window.kind && headline.kind != .night)
            #expect(headline.score == window.score)
            #expect(try #require(headline.assessment.lightScore).band < .good)
        }
        #expect(light.headline(for: .night)?.kind == .night)
    }

    @Test("a clear golden hour is not penalised by an overcast night", arguments: Provider.allCases)
    private func nightDoesNotDragDaytimeDown(_ p: Provider) throws {
        let clear = try forecast(p) { _ in 0.0 }
        let mixed = try forecast(p) { ($0 >= 20 || $0 < 4) ? 1.0 : 0.0 }
        #expect(windows(clear).window(.goldenEvening)?.score == windows(mixed).window(.goldenEvening)?.score)
    }

    @Test("no forecast gives no score")
    func noForecast() {
        let light = windows(nil, unavailable: .notLoaded)
        #expect(light.windows.count == 5 && light.windows.allSatisfy { $0.score == nil })
        #expect(light.headline(for: .sunset)?.score == nil)
        #expect(windows(nil, unavailable: nil).windows.allSatisfy { $0.assessment == .noForecast(.notLoaded) })
    }

    @Test("every provider error state gives no score and its own reason")
    func errorStatesGiveNoScore() async throws {
        var cases: [(String, WeatherError)] = []
        func error(_ transport: FakeTransport, caps: [ForecastSource: Int] = CallBudget.defaultCaps,
                   _ make: (Rig) -> any WeatherProviding, keys: Bool = true) async -> WeatherError {
            let rig = Rig(transport: transport, caps: caps)
            do { _ = try await make(rig).forecast(for: spot.coordinate); return .failed("no error") } catch { return (error as? WeatherError) ?? .failed("\(error)") }
        }
        let ok = FakeTransport { _ in (200, WeatherFixture.data("windy-gfs-documented-schema.json")) }
        cases.append(("OpenWeather missing key", await {
            let rig = Rig()
            do { _ = try await rig.openWeather(keys: resolver([:])).forecast(for: spot.coordinate) } catch { return error as! WeatherError }
            return .failed("none")
        }()))
        cases.append(("OpenWeather key rejected", await error(FakeTransport { _ in (401, Data()) }) { $0.openWeather() }))
        cases.append(("OpenWeather over limit", await error(FakeTransport(), caps: [.openWeather: 0]) { $0.openWeather() }))
        cases.append(("OpenWeather 429", await error(FakeTransport { _ in (429, Data()) }) { $0.openWeather() }))
        cases.append(("OpenWeather server error", await error(FakeTransport { _ in (503, Data()) }) { $0.openWeather() }))
        cases.append(("Windy missing key", await {
            let rig = Rig()
            do { _ = try await rig.windy(keys: resolver([:])).forecast(for: spot.coordinate) } catch { return error as! WeatherError }
            return .failed("none")
        }()))
        cases.append(("Windy testing key", await error(ok) { $0.windy(keyType: .testing) }))
        cases.append(("Windy key rejected", await error(FakeTransport { _ in (403, Data()) }) { $0.windy() }))
        cases.append(("Windy over limit", await error(ok, caps: [.windy: 0]) { $0.windy() }))
        cases.append(("Apple not enabled", .notEnabled))

        for (label, e) in cases {
            if case .failed("no error") = e { Issue.record("\(label): no error was thrown") }
            let reason = e.unavailableReason
            let light = windows(nil, unavailable: reason)
            #expect(light.windows.count == 5, "\(label)")
            #expect(light.windows.allSatisfy { $0.score == nil && $0.assessment == .noForecast(reason) }, "\(label)")
            #expect(light.headline(for: .sunset)?.score == nil, "\(label)")
        }
        // Each state keeps its own reason (the UI phrases them differently).
        let reasons = Set(cases.map { "\($0.1.unavailableReason)" })
        #expect(reasons.count >= 6)
        #expect(cases.contains { $0.1 == .missingKey(.windy) } && cases.contains { $0.1 == .testingKey(.windy) })
        #expect(cases.contains { $0.1 == .overDailyLimit(.openWeather) } && cases.contains { $0.1 == .keyRejected(.openWeather) })
    }
}
