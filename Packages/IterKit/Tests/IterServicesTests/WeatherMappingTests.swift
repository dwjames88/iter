import Testing
import Foundation
import IterCore
@testable import IterServices

private let fetched = Date(timeIntervalSince1970: 1_595_246_400)
private let c = Coordinate(latitude: 40.12, longitude: -96.66)

@Suite("OpenWeather mapping") struct OpenWeatherMappingTests {
    func map(_ name: String = "openweather-onecall3-documented.json") throws -> Forecast {
        try OpenWeatherMapping.map(WeatherFixture.data(name), coordinate: c, fetchedAt: fetched)
    }

    @Test func documentedExampleHourZero() throws {
        let f = try map()
        let h = try #require(f.hours.first)
        #expect(h.date == Date(timeIntervalSince1970: 1_595_242_800))
        #expect(h.cloudCover == 0.9)
        #expect(h.precipitationChance == 0.99)
        #expect(h.precipitationMm == 2.46)
        #expect(h.visibilityMeters == 10_000)
        #expect(abs(h.windSpeedKph - 4.6 * 3.6) < 1e-9)
        #expect(abs(h.temperatureC - 20.13) < 0.01)      // 293.28 K in the doc, converted to metric for the fixture
        #expect(h.humidity == 1.0)
        #expect(h.condition == "rain" && h.symbolName == "cloud.rain")
        #expect(h.resolution == .hourly)
        #expect(!h.hasLayers && h.cloudLow == nil)
        #expect(f.source == .openWeather && f.model == nil && f.fallbackFrom.isEmpty && f.fetchedAt == fetched)
    }

    @Test func fortyEightHourlyThenDailySummary() throws {
        let f = try map()
        let hourly = f.hours.filter { $0.resolution == .hourly }
        let summary = f.hours.filter { $0.resolution == .dailySummary }
        #expect(hourly.count == 48)
        #expect(!summary.isEmpty)
        // Summary hours only after the last hourly entry, on the hour grid with no gap or overlap.
        #expect(summary.first!.date == hourly.last!.date.addingTimeInterval(3600))
        for (a, b) in zip(f.hours, f.hours.dropFirst()) { #expect(b.date.timeIntervalSince(a.date) == 3600) }
        #expect(summary.allSatisfy { $0.visibilityMeters == nil && !$0.hasLayers })
        #expect(f.days.count == 8)
        // Day 3 of the fixture is a clear day (clouds 5 %, pop 0).
        let clearDay = summary.first { $0.cloudCover == 0.05 }
        #expect(clearDay?.precipitationChance == 0)
        #expect(clearDay?.condition == "clear" || clearDay?.condition == "partlyCloudy")
    }

    @Test func dailyFields() throws {
        let d = try #require(try map().days.first)
        #expect(abs(d.highC - 28.75) < 0.01 && abs(d.lowC - 20.10) < 0.01)
        #expect(d.precipitationChance == 1)
        #expect(d.providerSunrise == Date(timeIntervalSince1970: 1_595_243_663))
        #expect(d.providerSunset == Date(timeIntervalSince1970: 1_595_296_278))
        #expect(d.providerMoonPhase == 0.6)
        // The local day (America/Chicago, offset -18000) starts 05:00 UTC.
        #expect(d.date == Date(timeIntervalSince1970: 1_595_221_200))
    }

    @Test func missingFieldsAreNilNotInvented() throws {
        let f = try map("openweather-missing-fields-documented-schema.json")
        #expect(f.hours.count == 3)                       // the hour without clouds and the one without dt are dropped
        #expect(f.hours.allSatisfy { $0.visibilityMeters == nil && $0.precipitationChance == nil && $0.windGustKph == nil })
        #expect(f.hours.allSatisfy { $0.precipitationMm == 0 })   // absent rain/snow means none
        #expect(f.days.isEmpty)
        #expect(f.hours.allSatisfy { $0.resolution == .hourly })
    }

    @Test func rainAndSnowAmountsAdd() throws {
        let json = #"{"timezone_offset":0,"hourly":[{"dt":3600,"clouds":100,"rain":{"1h":1.5},"snow":{"1h":0.5},"weather":[{"id":600,"icon":"13d"}]}]}"#
        let f = try OpenWeatherMapping.map(Data(json.utf8), coordinate: c, fetchedAt: fetched)
        #expect(f.hours[0].precipitationMm == 2.0)
        #expect(f.hours[0].condition == "snow")
    }

    @Test func nightIconGivesNightSymbol() throws {
        let json = #"{"hourly":[{"dt":3600,"clouds":0,"weather":[{"id":800,"icon":"01n"}]},{"dt":7200,"clouds":0,"weather":[{"id":800,"icon":"01d"}]}]}"#
        let f = try OpenWeatherMapping.map(Data(json.utf8), coordinate: c, fetchedAt: fetched)
        #expect(f.hours[0].symbolName == "moon.stars" && f.hours[1].symbolName == "sun.max")
    }

    @Test func conditionCodes() {
        func m(_ id: Int, night: Bool = false) -> WeatherConditionMapping.Result { WeatherConditionMapping.openWeather(id: id, isNight: night) }
        #expect(m(211).condition == "thunderstorms")
        #expect(m(301).condition == "drizzle")
        #expect(m(502).condition == "rain")
        #expect(m(601).condition == "snow" && m(616).condition == "snow")
        #expect(m(741).condition == "foggy" && m(701).condition == "foggy")
        #expect(m(721).condition == "haze")
        #expect(m(800).condition == "clear" && m(800, night: true).symbol == "moon.stars")
        #expect(m(801).condition == "partlyCloudy" && m(802).condition == "partlyCloudy")
        #expect(m(803).condition == "mostlyCloudy")
        #expect(m(804).condition == "cloudy")
    }

    @Test func emptyResponseThrows() {
        #expect(throws: (any Error).self) { try OpenWeatherMapping.map(Data("{}".utf8), coordinate: c, fetchedAt: fetched) }
        #expect(throws: (any Error).self) { try OpenWeatherMapping.map(Data("not json".utf8), coordinate: c, fetchedAt: fetched) }
    }
}

@Suite("Windy mapping") struct WindyMappingTests {
    let raw = WeatherFixture.json("windy-gfs-documented-schema.json")
    func series(_ name: String) -> [Double?] { (raw[name] as! [Any]).map { ($0 as? NSNumber)?.doubleValue } }
    var ts: [Double] { (raw["ts"] as! [NSNumber]).map { $0.doubleValue / 1000 } }

    func map(_ name: String = "windy-gfs-documented-schema.json", model: WindyModel = .gfs) throws -> WindyMapping.Output {
        try WindyMapping.map(WeatherFixture.data(name), coordinate: moabSpot, model: model, fetchedAt: fetched)
    }

    @Test func nativeStepConvertsUnitsAndLayers() throws {
        let out = try map()
        #expect(out.hasClouds && out.warning == nil)
        let f = out.forecast
        #expect(f.source == .windy && f.model == "GFS")
        let h = try #require(f.hours.first)
        #expect(h.date.timeIntervalSince1970 == ts[0])
        #expect(abs(h.temperatureC - (series("temp-surface")[0]! - 273.15)) < 1e-9)
        let u = series("wind_u-surface")[0]!, v = series("wind_v-surface")[0]!
        #expect(abs(h.windSpeedKph - hypot(u, v) * 3.6) < 1e-9)
        #expect(abs(h.windGustKph! - series("gust-surface")[0]! * 3.6) < 1e-9)
        let l = series("lclouds-surface")[0]! / 100, m = series("mclouds-surface")[0]! / 100, hi = series("hclouds-surface")[0]! / 100
        #expect(h.cloudLow == l && h.cloudMid == m && h.cloudHigh == hi && h.hasLayers)
        // Total cloud is derived, random overlap.
        #expect(abs(h.cloudCover - (1 - (1 - l) * (1 - m) * (1 - hi))) < 1e-12)
        #expect(abs(h.humidity - series("rh-surface")[0]! / 100) < 1e-12)
        #expect(h.visibilityMeters == series("visibility-surface")[0])
        #expect(h.precipitationChance == nil)
    }

    @Test func threeHourlyStepsAreInterpolatedAndFlagged() throws {
        let f = try map().forecast
        let t = ts
        #expect(f.hours.count == Int((t.last! - t.first!) / 3600) + 1)
        #expect(f.hours.allSatisfy { $0.resolution == .interpolated })
        let low = series("lclouds-surface")
        let h1 = f.hours[1]   // one third of the way from step 0 to step 1
        #expect(abs(h1.cloudLow! - (low[0]! + (low[1]! - low[0]!) / 3) / 100) < 1e-12)
        let h3 = f.hours[3]   // exactly step 1
        #expect(abs(h3.cloudLow! - low[1]! / 100) < 1e-12)
    }

    @Test func hourlyModelIsNotFlaggedInterpolated() throws {
        var o = raw
        let base = 1_595_246_400_000.0
        o["ts"] = (0..<4).map { base + Double($0) * 3_600_000 }
        for k in o.keys where k.hasSuffix("-surface") { o[k] = Array((o[k] as! [Any]).prefix(4)) }
        let f = try WindyMapping.map(WeatherFixture.encode(o), coordinate: moabSpot, model: .iconEu, fetchedAt: fetched).forecast
        #expect(f.hours.count == 4 && f.hours.allSatisfy { $0.resolution == .hourly })
        #expect(f.model == "ICON-EU")
    }

    @Test func precipitationIsSpreadOverThePrecedingThreeHours() throws {
        let f = try map().forecast
        let p = series("past3hprecip-surface")
        #expect(p[0] == nil)
        let step = (0..<p.count).first { p[$0] != nil && p[$0]! > 0 && $0 >= 2 }!
        // The accumulation ending at step `step` belongs to the hours starting 3, 2 and 1 hours before it.
        let end = ts[step]
        for back in 1...3 {
            let h = try #require(f.hours.first { $0.date.timeIntervalSince1970 == end - Double(back) * 3600 })
            #expect(abs(h.precipitationMm! - p[step]! / 3) < 1e-12)
        }
        // The hour starting AT that step belongs to the next accumulation.
        let after = try #require(f.hours.first { $0.date.timeIntervalSince1970 == end })
        if step + 1 < p.count, let next = p[step + 1] { #expect(abs(after.precipitationMm! - next / 3) < 1e-12) }
        // Windy has no probability.
        #expect(f.hours.allSatisfy { $0.precipitationChance == nil })
    }

    @Test func hoursBeyondTheLastAccumulationAreNil() throws {
        let f = try map().forecast
        #expect(f.hours.last!.date.timeIntervalSince1970 == ts.last!)
        #expect(f.hours.last!.precipitationMm == nil)          // no later step holds its accumulation
        let before = f.hours[f.hours.count - 2]
        #expect(before.precipitationMm == series("past3hprecip-surface").last!.map { $0 / 3 })
    }

    @Test func nullCloudBaseStaysNil() throws {
        let f = try map().forecast
        let cb = series("cbase-surface")
        let nullStep = try #require(cb.firstIndex { $0 == nil })
        let h = try #require(f.hours.first { $0.date.timeIntervalSince1970 == ts[nullStep] })
        #expect(h.cloudBaseMeters == nil)
    }

    @Test func nullLayersAreNilNotInvented() throws {
        let f = try map("windy-null-layers-documented-schema.json").forecast
        let t = ts
        // Step 2: low is null: low nil, total from the layers present, no layers flag.
        let h2 = try #require(f.hours.first { $0.date.timeIntervalSince1970 == t[2] })
        #expect(h2.cloudLow == nil && h2.cloudMid != nil && h2.cloudHigh != nil && !h2.hasLayers)
        let m = h2.cloudMid!, hi = h2.cloudHigh!
        #expect(abs(h2.cloudCover - (1 - (1 - m) * (1 - hi))) < 1e-12)
        // Step 3: every layer is null: the hour does not exist.
        #expect(!f.hours.contains { $0.date.timeIntervalSince1970 == t[3] })
        // All visibility null: nil. No rh key: humidity from temperature and dew point (more than 0, at most 1).
        #expect(f.hours.allSatisfy { $0.visibilityMeters == nil })
        #expect(f.hours.allSatisfy { $0.humidity > 0 && $0.humidity <= 1 })
    }

    @Test func noCloudKeysMeansNoClouds() throws {
        var o = raw
        for k in ["lclouds-surface", "mclouds-surface", "hclouds-surface"] { o[k] = nil }
        let out = try WindyMapping.map(WeatherFixture.encode(o), coordinate: moabSpot, model: .iconEu, fetchedAt: fetched)
        #expect(!out.hasClouds && out.forecast.hours.isEmpty)
    }

    @Test func unknownUnitDropsTheField() throws {
        var o = raw
        var u = o["units"] as! [String: Any]
        u["visibility-surface"] = "furlongs"
        o["units"] = u
        let f = try WindyMapping.map(WeatherFixture.encode(o), coordinate: moabSpot, model: .gfs, fetchedAt: fetched).forecast
        #expect(f.hours.allSatisfy { $0.visibilityMeters == nil })
    }

    @Test func warningIsReported() throws {
        let out = try map("windy-testing-warning-documented-schema.json")
        #expect(out.warning != nil)
    }

    @Test func malformedThrows() {
        #expect(throws: (any Error).self) { try WindyMapping.map(Data("[]".utf8), coordinate: moabSpot, model: .gfs, fetchedAt: fetched) }
    }

    @Test func conditionThresholds() {
        func w(_ cloud: Double, mm: Double? = nil, type: Int? = nil, vis: Double? = nil, night: Bool = false) -> WeatherConditionMapping.Result {
            WeatherConditionMapping.windy(cloud: cloud, precipitationMm: mm, precipitationType: type, visibilityMeters: vis, isNight: night)
        }
        #expect(w(0.14).condition == "clear" && w(0.15).condition == "partlyCloudy")
        #expect(w(0.44).condition == "partlyCloudy" && w(0.45).condition == "mostlyCloudy")
        #expect(w(0.79).condition == "mostlyCloudy" && w(0.80).condition == "cloudy")
        #expect(w(0.5, mm: 0.09).condition == "mostlyCloudy")
        #expect(w(0.5, mm: 0.1).condition == "drizzle" && w(0.5, mm: 0.5).condition == "rain")
        #expect(w(1, mm: 1, type: 5).condition == "snow")
        #expect(w(0, vis: 999).condition == "foggy" && w(0, vis: 4_999).condition == "haze" && w(0, vis: 5_000).condition == "clear")
        #expect(w(0, night: true).symbol == "moon.stars")
    }

    @Test func conversions() {
        #expect(WindyMapping.toCelsius(273.15, "K") == 0)
        #expect(WindyMapping.toKph(10, "m*s-1") == 36)
        #expect(WindyMapping.toKph(10, "kt")! > 18)
        #expect(WindyMapping.toFraction(50, "%") == 0.5)
        #expect(WindyMapping.toMeters(2, "km") == 2000)
        #expect(WindyMapping.toKph(1, "parsecs") == nil)
    }
}
