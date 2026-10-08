import Testing
import Foundation
import IterCore
@testable import IterServices

private let fetched = Date(timeIntervalSince1970: 1_595_246_400)
private let spot = Coordinate(latitude: 39.5, longitude: -105.0)

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Double {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .gmt
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!.timeIntervalSince1970
}

private func dayJSON(dt: Double, clouds: Int = 50) -> String {
    #"{"dt":\#(Int(dt)),"temp":{"min":1,"max":9,"morn":2,"day":8,"eve":5,"night":1},"clouds":\#(clouds),"wind_speed":2,"humidity":40,"pop":0.2,"weather":[{"id":803,"icon":"04d"}]}"#
}

private func map(_ json: String) throws -> Forecast {
    try OpenWeatherMapping.map(Data(json.utf8), coordinate: spot, fetchedAt: fetched)
}

@Suite("OpenWeather days and gaps") struct OpenWeatherDayTests {
    /// America/Denver falls back on 2026-11-01 (MDT -6 to MST -7). The response carries only today's offset (-21600),
    /// so a fixed-offset midnight for the days after the change landed an hour into the previous local day.
    @Test func daysAfterAFallBackStartAtTheirRealLocalMidnight() throws {
        let hour0 = utc(2026, 10, 30, 12)
        let days = [utc(2026, 10, 30, 18), utc(2026, 10, 31, 18), utc(2026, 11, 1, 19), utc(2026, 11, 2, 19)]   // local noon each day
        let json = #"{"timezone":"America/Denver","timezone_offset":-21600,"hourly":[{"dt":\#(Int(hour0)),"clouds":10}],"daily":[\#(days.map { dayJSON(dt: $0) }.joined(separator: ","))]}"#
        let f = try map(json)
        #expect(f.days.map(\.date.timeIntervalSince1970) == [utc(2026, 10, 30, 6), utc(2026, 10, 31, 6), utc(2026, 11, 1, 6), utc(2026, 11, 2, 7)])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Denver")!
        #expect(f.days.allSatisfy { cal.component(.hour, from: $0.date) == 0 })
        // The summary hours run on without a gap or overlap through the 25-hour day.
        for (a, b) in zip(f.hours, f.hours.dropFirst()) { #expect(b.date.timeIntervalSince(a.date) == 3600) }
        #expect(f.hours.last?.date == Date(timeIntervalSince1970: utc(2026, 11, 3, 7) - 3600))
    }

    @Test func aZoneThatDisagreesWithTheOffsetIsIgnored() throws {
        let json = #"{"timezone":"America/Denver","timezone_offset":3600,"hourly":[{"dt":\#(Int(utc(2026, 7, 1))),"clouds":10}],"daily":[\#(dayJSON(dt: utc(2026, 7, 1, 12) - 3600))]}"#
        let f = try map(json)
        #expect(f.days.first?.date == Date(timeIntervalSince1970: utc(2026, 7, 1) - 3600))
    }

    @Test("a spot whose local day differs from UTC's", arguments: [("Pacific/Auckland", 43200.0), ("Pacific/Honolulu", -36000.0), ("Asia/Kolkata", 19800.0), ("Asia/Kathmandu", 20700.0)])
    func localDayIsTheSpotsNotUTCs(_ zoneName: String, _ offset: Double) throws {
        // Noon local on 2026-07-10 is 2026-07-10 12:00 minus the offset in UTC; the day must start at local midnight.
        let noon = utc(2026, 7, 10, 12) - offset
        let json = #"{"timezone_offset":\#(Int(offset)),"hourly":[{"dt":\#(Int(noon - 3 * 3600)),"clouds":10}],"daily":[\#(dayJSON(dt: noon))]}"#
        let f = try map(json)
        #expect(f.days.first?.date == Date(timeIntervalSince1970: utc(2026, 7, 10) - offset))
        let named = try map(json.replacingOccurrences(of: #"{"timezone_offset""#, with: #"{"timezone":"\#(zoneName)","timezone_offset""#))
        #expect(named.days.first?.date == f.days.first?.date)
        #expect(named.hours.map(\.date) == f.hours.map(\.date))
    }

    @Test func hourlyTimestampsStayOnTheirUTCHours() throws {
        for name in openWeatherFixtureNames {
            let f = try OpenWeatherMapping.map(WeatherFixture.data(name), coordinate: spot, fetchedAt: fetched)
            #expect(f.hours.allSatisfy { $0.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0 }, "\(name)")
            #expect(zip(f.hours, f.hours.dropFirst()).allSatisfy { $1.date.timeIntervalSince($0.date) == 3600 }, "\(name)")
            // The horizon is the end of the last daily day, so the engine sees every forecast day.
            let lastDay = try #require(f.days.last)
            #expect(f.horizon.map { $0 >= lastDay.date.addingTimeInterval(23 * 3600) } == true, "\(name)")
        }
    }

    @Test func noDailyBlockKeepsTheHourlyHoursAndNoDays() throws {
        let f = try map(#"{"hourly":[{"dt":3600,"clouds":20,"temp":4},{"dt":7200,"clouds":30}]}"#)
        #expect(f.hours.count == 2 && f.days.isEmpty && f.hours.allSatisfy { $0.resolution == .hourly })
    }

    @Test func noHourlyBlockHasNothingToAnchorTheDailyHours() {
        #expect(throws: OpenWeatherMapping.MappingError.noForecastData) {
            try map(#"{"timezone_offset":0,"daily":[\#(dayJSON(dt: 43200))]}"#)
        }
    }

    @Test func unitsAndMissingValuesInOneHour() throws {
        let f = try map(#"{"hourly":[{"dt":3600,"clouds":140,"wind_speed":10,"wind_gust":15,"humidity":55,"pop":1.4,"rain":{},"visibility":10000,"temp":-3.5}]}"#)
        let h = try #require(f.hours.first)
        #expect(h.cloudCover == 1)                         // percent clamped to a fraction
        #expect(abs(h.windSpeedKph - 36) < 1e-9 && abs((h.windGustKph ?? 0) - 54) < 1e-9)   // m/s to km/h
        #expect(h.precipitationChance == 1 && h.precipitationMm == 0)
        #expect(h.visibilityMeters == 10_000 && h.humidity == 0.55 && h.temperatureC == -3.5)
        let bare = try #require(try map(#"{"hourly":[{"dt":3600,"clouds":0}]}"#).hours.first)
        #expect(bare.precipitationChance == nil && bare.visibilityMeters == nil && bare.windGustKph == nil)
    }
}

@Suite("OpenWeather service errors") struct OpenWeatherErrorTests {
    @Test func errorBodiesMapToTheRightReason() async {
        let cases: [(Int, String, WeatherError)] = [
            (401, #"{"cod":401,"message":"Invalid API key. Please see https://openweathermap.org/faq#error401"}"#, .keyRejected(.openWeather)),
            (429, #"{"cod":429,"message":"Your account is temporary blocked"}"#, .overDailyLimit(.openWeather)),
            (200, "{}", .provider(.openWeather, "The response had no forecast data")),
            (200, "<html>nope</html>", .provider(.openWeather, "The response could not be read")),
            (200, #"{"hourly":"x"}"#, .provider(.openWeather, "The response could not be read")),
        ]
        for (status, body, expected) in cases {
            let rig = Rig(transport: FakeTransport { _ in (status, Data(body.utf8)) })
            do {
                _ = try await rig.openWeather().forecast(for: moabSpot)
                Issue.record("expected a throw for \(status)")
            } catch { #expect(error as? WeatherError == expected, "\(status) \(body)") }
            #expect(rig.transport.callCount == 1)
        }
    }

    @Test func theFixtureErrorBodyIs401() async {
        let rig = Rig(transport: FakeTransport { _ in (401, WeatherFixture.data("openweather-error-401.json")) })
        do { _ = try await rig.openWeather().forecast(for: moabSpot) } catch { #expect(error as? WeatherError == .keyRejected(.openWeather)) }
    }
}
