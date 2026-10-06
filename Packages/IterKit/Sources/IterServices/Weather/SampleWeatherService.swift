import Foundation
import IterCore

/// A deterministic synthetic ten-day forecast. It exists only behind the Debug menu's Sample Data mode so the Light Index
/// can be exercised across every band; the app labels it "Sample" wherever it appears.
///
/// The same coordinate and day always produce the same weather. Days cycle through six sky regimes in an order
/// shuffled per coordinate, so any ten-day span contains every regime.
public struct SampleWeatherService: WeatherProviding {
    public var source: ForecastSource { .sample }

    /// The sky for one local day.
    public enum Regime: Int, CaseIterable, Sendable {
        case clear, highCloudEvening, overcast, rain, morningFog, partlyCloudy
    }

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func attribution() async -> WeatherAttributionInfo? { nil }

    public func forecast(for coordinate: Coordinate) async throws -> Forecast {
        let fetchedAt = now()
        return Self.makeForecast(for: coordinate, fetchedAt: fetchedAt)
    }

    /// The regime for the local solar day containing `date` at `coordinate`.
    public static func regime(for coordinate: Coordinate, on date: Date) -> Regime {
        regime(for: coordinate, dayIndex: dayIndex(of: date, longitude: coordinate.longitude))
    }

    // MARK: Generation

    static func makeForecast(for coordinate: Coordinate, fetchedAt: Date) -> Forecast {
        let firstHour = floor((fetchedAt.timeIntervalSince1970 - 3600) / 3600) * 3600
        let hourCount = 10 * 24 + 2
        var hours: [HourlyConditions] = []
        hours.reserveCapacity(hourCount)
        for i in 0..<hourCount {
            hours.append(hour(at: Date(timeIntervalSince1970: firstHour + Double(i) * 3600), coordinate: coordinate))
        }

        var days: [DailyConditions] = []
        var byDay: [Int: [HourlyConditions]] = [:]
        for h in hours { byDay[dayIndex(of: h.date, longitude: coordinate.longitude), default: []].append(h) }
        for index in byDay.keys.sorted() {
            guard let hs = byDay[index], let noon = hs.min(by: { abs(localHour(of: $0.date, longitude: coordinate.longitude) - 13) < abs(localHour(of: $1.date, longitude: coordinate.longitude) - 13) }) else { continue }
            days.append(DailyConditions(
                date: Date(timeIntervalSince1970: Double(index) * 86400 - coordinate.longitude / 15 * 3600),
                highC: hs.map(\.temperatureC).max() ?? 0,
                lowC: hs.map(\.temperatureC).min() ?? 0,
                precipitationChance: hs.compactMap(\.precipitationChance).max() ?? 0,
                symbolName: noon.symbolName.replacingOccurrences(of: ".fill", with: ""),
                condition: noon.condition))
        }
        return Forecast(coordinate: coordinate, hours: hours, days: days, fetchedAt: fetchedAt, source: .sample)
    }

    static func dayIndex(of date: Date, longitude: Double) -> Int {
        Int(floor((date.timeIntervalSince1970 + longitude / 15 * 3600) / 86400))
    }

    static func localHour(of date: Date, longitude: Double) -> Double {
        let seconds = (date.timeIntervalSince1970 + longitude / 15 * 3600).truncatingRemainder(dividingBy: 86400)
        return (seconds < 0 ? seconds + 86400 : seconds) / 3600
    }

    static func regime(for coordinate: Coordinate, dayIndex: Int) -> Regime {
        var rng = Hasher64(seed: coordinateSeed(coordinate))
        var order = Regime.allCases
        // Fisher-Yates with the coordinate's seed.
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            order.swapAt(i, j)
        }
        let slot = ((dayIndex % order.count) + order.count) % order.count
        return order[slot]
    }

    static func coordinateSeed(_ c: Coordinate) -> UInt64 {
        // Rounded to ~1 km so nearby spots in one area share a pattern.
        let lat = Int64((c.latitude * 100).rounded()), lon = Int64((c.longitude * 100).rounded())
        return UInt64(bitPattern: lat) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: lon) &* 0xC2B2_AE3D_27D4_EB4F
    }

    /// 0...1, stable for (coordinate, key).
    static func unit(_ seed: UInt64, _ key: Int, _ salt: UInt64 = 0) -> Double {
        var h = Hasher64(seed: seed ^ (UInt64(bitPattern: Int64(key)) &* 0xD6E8_FEB8_6659_FD93) ^ salt)
        return Double(h.next() >> 11) / Double(1 << 53)
    }

    static func hour(at date: Date, coordinate c: Coordinate) -> HourlyConditions {
        let seed = coordinateSeed(c)
        let day = dayIndex(of: date, longitude: c.longitude)
        let lh = localHour(of: date, longitude: c.longitude)
        let regime = regime(for: c, dayIndex: day)
        let hourKey = Int(floor(date.timeIntervalSince1970 / 3600))
        let jitter = unit(seed, hourKey, 1) - 0.5          // -0.5...0.5
        let dayJitter = unit(seed, day, 2)                 // 0...1

        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

        var low = 0.03, mid = 0.03, high = 0.03
        var precip = 0.03, visibility = 24_000.0
        var condition = "clear"
        var thermal = 8.0    // diurnal swing, degrees
        var humidityBase = 0.35

        switch regime {
        case .clear:
            low = 0.02 + 0.04 * jitter.magnitude; mid = 0.02; high = 0.04 + 0.08 * dayJitter
            condition = "clear"
            thermal = 10
        case .highCloudEvening:
            // Thin high cloud builds through the afternoon: the classic colour evening.
            let build = lh < 11 ? 0.25 : lh < 15 ? 0.45 : lh < 22 ? 0.75 + 0.15 * dayJitter : 0.5
            low = 0.04 + 0.04 * jitter.magnitude; mid = 0.12 + 0.1 * dayJitter; high = clamp(build + 0.1 * jitter)
            condition = "partlyCloudy"
            thermal = 8
            humidityBase = 0.4
        case .overcast:
            low = clamp(0.8 + 0.15 * jitter); mid = clamp(0.85 + 0.1 * jitter); high = clamp(0.9 + 0.1 * jitter)
            precip = 0.12 + 0.1 * dayJitter
            visibility = 14_000
            condition = "cloudy"
            thermal = 3
            humidityBase = 0.7
        case .rain:
            let peak = max(0, 1 - abs(lh - 14) / 9)
            low = clamp(0.85 + 0.1 * jitter); mid = 0.9; high = 0.95
            precip = clamp(0.35 + 0.5 * peak + 0.1 * dayJitter)
            visibility = 6_000 - 2_000 * peak
            condition = "rain"
            thermal = 3
            humidityBase = 0.88
        case .morningFog:
            let fogged = lh < 9.5
            let clearing = lh >= 9.5 && lh < 11.5
            if fogged {
                low = 1.0; mid = 0.1; high = 0.05
                visibility = 300 + 500 * dayJitter + 200 * jitter.magnitude
                condition = "foggy"
                humidityBase = 0.98
            } else if clearing {
                low = 0.6; mid = 0.1; high = 0.05
                visibility = 3_000
                condition = "mostlyCloudy"
                humidityBase = 0.8
            } else {
                low = 0.05; mid = 0.05; high = 0.05
                condition = "clear"
            }
            thermal = 9
        case .partlyCloudy:
            low = clamp(0.25 + 0.25 * jitter + 0.2 * dayJitter); mid = clamp(0.3 + 0.2 * jitter); high = clamp(0.2 + 0.2 * dayJitter)
            precip = 0.08
            condition = "partlyCloudy"
            thermal = 7
            humidityBase = 0.5
        }

        let cover = clamp(1 - (1 - low) * (1 - mid) * (1 - high))
        // Temperature: latitude-driven mean, a per-day offset, and a diurnal cycle peaking around 15:00.
        let mean = 26 - 0.45 * abs(c.latitude) + (unit(seed, day, 3) - 0.5) * 8
        let temperature = mean + thermal * cos((lh - 15) / 24 * 2 * .pi) / 2 - (regime == .morningFog && lh < 9.5 ? 1.5 : 0)
        let humidity = clamp(humidityBase + 0.25 * (1 - (cos((lh - 15) / 24 * 2 * .pi) + 1) / 2) * (1 - humidityBase) + 0.03 * jitter)
        let wind = max(0, 6 + 14 * unit(seed, day, 4) + (regime == .rain ? 8 : 0) + 6 * jitter + (lh > 11 && lh < 18 ? 4 : 0))
        let isDay = lh >= 6 && lh < 20

        let symbol: String
        switch condition {
        case "clear": symbol = isDay ? "sun.max" : "moon.stars"
        case "partlyCloudy": symbol = isDay ? "cloud.sun" : "cloud.moon"
        case "mostlyCloudy": symbol = isDay ? "cloud.sun" : "cloud.moon"
        case "cloudy": symbol = "cloud"
        case "rain": symbol = "cloud.rain"
        case "foggy": symbol = "cloud.fog"
        default: symbol = "cloud"
        }

        return HourlyConditions(
            date: date, cloudCover: cover, cloudLow: low, cloudMid: mid, cloudHigh: high,
            precipitationChance: clamp(precip), visibilityMeters: visibility, windSpeedKph: wind,
            temperatureC: temperature, humidity: humidity, symbolName: symbol, condition: condition)
    }
}

/// SplitMix64: tiny, fast, and identical on every platform and run (unlike `Hasher`, which is seeded per process).
struct Hasher64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
