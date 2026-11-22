import Testing
import Foundation
import Synchronization
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

@Suite("Windy audit") struct WindyAuditTests {
    private func body(_ ts: [Double], _ series: [String: [Any]], units: [String: String] = [:]) -> Data {
        var o: [String: Any] = ["ts": ts, "units": units]
        for (k, v) in series { o[k] = v }
        return WeatherFixture.encode(o)
    }
    private func map(_ data: Data, model: WindyModel = .gfs) throws -> Forecast {
        try WindyMapping.map(data, coordinate: moabSpot, model: model, fetchedAt: fetched).forecast
    }
    private let base = 1_595_246_400_000.0     // 2020-07-20 12:00 UTC

    @Test func stepsOffTheHourStillGiveWholeUTCHours() throws {
        // Steps at 12:30, 15:30, 18:30: hours run 13:00 to 18:00, each at a whole hour, interpolated between the steps.
        let ts = [base + 1_800_000, base + 12_600_000, base + 23_400_000]
        let f = try map(body(ts, ["lclouds-surface": [0, 30, 60], "mclouds-surface": [0, 0, 0], "hclouds-surface": [0, 0, 0]],
                             units: ["lclouds-surface": "%", "mclouds-surface": "%", "hclouds-surface": "%"]))
        #expect(f.hours.map(\.date.timeIntervalSince1970) == (13...18).map { 1_595_203_200.0 + Double($0) * 3600 })
        #expect(abs(f.hours[0].cloudLow! - 0.05) < 1e-9)            // 30 minutes into a 3 h step, a sixth of 30 %
        #expect(f.hours.allSatisfy { $0.resolution == .interpolated })
    }

    @Test func windUnitsComeFromTheUnitsObject() throws {
        let ts = [base, base + 3_600_000]
        let layers: [String: [Any]] = ["lclouds-surface": [10, 10], "mclouds-surface": [10, 10], "hclouds-surface": [10, 10]]
        let pct = ["lclouds-surface": "%", "mclouds-surface": "%", "hclouds-surface": "%"]
        func wind(_ unit: String, u: Double, v: Double) throws -> Double {
            var s = layers
            s["wind_u-surface"] = [u, u]; s["wind_v-surface"] = [v, v]
            return try map(body(ts, s, units: pct.merging(["wind_u-surface": unit, "wind_v-surface": unit]) { $1 })).hours[0].windSpeedKph
        }
        #expect(abs(try wind("m*s-1", u: 3, v: 4) - 18) < 1e-9)
        #expect(abs(try wind("kt", u: 3, v: 4) - 5 * 1.852) < 1e-9)
        #expect(abs(try wind("km/h", u: 3, v: 4) - 5) < 1e-9)
        // No wind series at all, or an unknown unit: reads 0 (the contract keeps wind non-optional), gust stays nil.
        #expect(try map(body(ts, layers, units: pct)).hours[0].windSpeedKph == 0)
        #expect(try wind("parsecs", u: 3, v: 4) == 0)
        #expect(try map(body(ts, layers, units: pct)).hours[0].windGustKph == nil)
    }

    @Test func temperatureUnitsAndMissingSeries() throws {
        let ts = [base, base + 3_600_000]
        var s: [String: [Any]] = ["lclouds-surface": [10, 10], "mclouds-surface": [10, 10], "hclouds-surface": [10, 10], "temp-surface": [293.15, 293.15]]
        let pct = ["lclouds-surface": "%", "mclouds-surface": "%", "hclouds-surface": "%"]
        #expect(abs(try map(body(ts, s, units: pct.merging(["temp-surface": "K"]) { $1 })).hours[0].temperatureC - 20) < 1e-9)
        s["temp-surface"] = [68, 68]
        #expect(abs(try map(body(ts, s, units: pct.merging(["temp-surface": "°F"]) { $1 })).hours[0].temperatureC - 20) < 1e-9)
        s["temp-surface"] = nil
        let none = try map(body(ts, s, units: pct)).hours[0]
        #expect(none.temperatureC == 0 && none.humidity == 0 && none.visibilityMeters == nil && none.precipitationMm == nil)
    }

    @Test func aSeriesOfTheWrongLengthIsIgnoredNotMisaligned() throws {
        let ts = [base, base + 3_600_000, base + 7_200_000]
        let f = try map(body(ts, ["lclouds-surface": [10, 10, 10], "mclouds-surface": [10, 10, 10], "hclouds-surface": [10, 10, 10], "temp-surface": [280, 281]],
                             units: ["lclouds-surface": "%", "mclouds-surface": "%", "hclouds-surface": "%", "temp-surface": "K"]))
        #expect(f.hours.count == 3 && f.hours.allSatisfy { $0.temperatureC == 0 })
    }

    @Test func unorderedOrDuplicateStepsAreMalformed() {
        for ts in [[base, base], [base + 3_600_000, base]] {
            #expect(throws: WindyMapping.MappingError.malformed) {
                try WindyMapping.map(body(ts, ["lclouds-surface": [1, 1]]), coordinate: moabSpot, model: .gfs, fetchedAt: fetched)
            }
        }
    }

    @Test func aTestingKeyCallsOnceThenRefusesAndCachesNothing() async {
        let rig = Rig(transport: FakeTransport { _ in (200, WeatherFixture.data("windy-gfs-documented-schema.json")) })
        let s = rig.windy(keyType: .testing)
        for _ in 0..<2 {
            await #expect(throws: WeatherError.testingKey(.windy)) { try await s.forecast(for: moabSpot) }
        }
        #expect(rig.transport.callCount == 2)      // refused after the call, so nothing was cached to serve the second
        let ok = try? await rig.windy(keyType: .professional).forecast(for: moabSpot)
        #expect(ok?.source == .windy)
    }
}

@Suite("API keys audit") struct APIKeyAuditTests {
    /// A store whose Keychain is locked or denied: reads find nothing, writes throw.
    private struct DeniedStore: APIKeyStore {
        func key(for source: ForecastSource) -> String? { nil }
        func setKey(_ key: String, for source: ForecastSource) throws { throw KeychainError(status: errSecInteractionNotAllowed) }
        func removeKey(for source: ForecastSource) throws { throw KeychainError(status: errSecAuthFailed) }
    }

    @Test func pastedWhitespaceAndNewlinesAreTrimmedFromEverySource() {
        let store = InMemoryAPIKeyStore([.openWeather: "  stored\n"])
        func resolver(env: String? = nil, arg: String? = nil) -> APIKeyResolver {
            APIKeyResolver(store: store, environment: { env.map { ["ITER_OPENWEATHER_KEY": $0] } ?? [:] }, launchArgument: { _ in arg })
        }
        #expect(resolver(env: "\tenv \r\n").resolve(.openWeather)?.value == "env")
        #expect(resolver(arg: " arg\n").resolve(.openWeather)?.value == "arg")
        #expect(resolver().resolve(.openWeather)?.value == "stored")
    }

    @Test func aBlankHigherSourceFallsThroughToTheNext() {
        let store = InMemoryAPIKeyStore([.windy: "kc"])
        let r = APIKeyResolver(store: store, environment: { ["ITER_WINDY_KEY": " \n"] }, launchArgument: { _ in "" })
        let key = r.resolve(.windy)
        #expect(key?.value == "kc" && key?.origin == .keychain)
        #expect(r.resolve(.appleWeather) == nil && r.resolve(.sample) == nil)
    }

    @Test func aDeniedKeychainReadsAsNoKeyAndTheServiceAsksForOne() async {
        let r = APIKeyResolver(store: DeniedStore(), environment: { [:] }, launchArgument: { _ in nil })
        #expect(r.resolve(.openWeather) == nil)
        let rig = Rig()
        do { _ = try await rig.openWeather(keys: r).forecast(for: moabSpot) } catch { #expect(error as? WeatherError == .missingKey(.openWeather)) }
        #expect(rig.transport.callCount == 0)
    }

    @Test func keychainFailuresCarryAStatusAndNeverAKey() {
        let e = KeychainError(status: errSecInteractionNotAllowed)
        #expect(!"\(e)".contains(secretKey) && e.status == errSecInteractionNotAllowed)
        let resolved = ResolvedAPIKey(value: secretKey, origin: .environment)
        #expect(!"\(resolved)".contains(secretKey) && !String(reflecting: resolved).contains(secretKey))
    }
}

@Suite("Router audit") struct RouterAuditTests {
    @Test func aCancelledProviderStopsTheRouterWithoutTryingTheFallback() async {
        struct Cancelling: WeatherProviding {
            let source = ForecastSource.openWeather
            func forecast(for coordinate: Coordinate) async throws -> Forecast { throw CancellationError() }
            func attribution() async -> WeatherAttributionInfo? { nil }
        }
        let fallback = StubProvider(.windy, .success(fetched))
        let router = WeatherRouter(providers: [Cancelling(), fallback])
        await #expect(throws: CancellationError.self) { try await router.forecast(for: moabSpot) }
        #expect(fallback.callCount == 0)
    }

    @Test func theObserverHearsEveryAttemptInOrder() async throws {
        let log = Mutex<[String]>([])
        let router = WeatherRouter(providers: [StubProvider(.openWeather, .failure(.offline(.openWeather))), StubProvider(.windy, .success(fetched))]) { source, result in
            log.withLock { $0.append("\(source.rawValue):\((try? result.get()) != nil)") }
        }
        let f = try await router.forecast(for: moabSpot)
        #expect(log.withLock { $0 } == ["openWeather:false", "windy:true"] && f.fallbackFrom == [.openWeather])
    }
}
