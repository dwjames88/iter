import Foundation
import IterCore

/// Maps an OpenWeather One Call 3.0 response (requested with `units=metric`) to an Iter `Forecast`. Pure: no network, no clock.
///
/// Every field is optional while decoding. Nothing is invented: a missing visibility, probability or gust stays nil;
/// absent `rain`/`snow` means none (the API omits them when dry). An hour without `dt` or `clouds` is dropped.
/// Temperature, humidity and wind are non-optional in `HourlyConditions`; when the provider omits them they read 0.
enum OpenWeatherMapping {
    // MARK: Wire types (all optional)

    struct Response: Decodable {
        var lat: Double?
        var lon: Double?
        var timezone: String?
        var timezone_offset: Double?
        var hourly: [Hour]?
        var daily: [Day]?
    }

    struct Weather: Decodable {
        var id: Int?
        var main: String?
        var description: String?
        var icon: String?
    }

    struct Volume: Decodable {
        var oneHour: Double?
        enum CodingKeys: String, CodingKey { case oneHour = "1h" }
    }

    struct Hour: Decodable {
        var dt: Double?
        var temp: Double?
        var humidity: Double?
        var clouds: Double?
        var visibility: Double?
        var wind_speed: Double?
        var wind_gust: Double?
        var pop: Double?
        var rain: Volume?
        var snow: Volume?
        var weather: [Weather]?
    }

    struct DayTemp: Decodable {
        var day: Double?
        var min: Double?
        var max: Double?
        var night: Double?
        var eve: Double?
        var morn: Double?
    }

    struct Day: Decodable {
        var dt: Double?
        var sunrise: Double?
        var sunset: Double?
        var moon_phase: Double?
        var temp: DayTemp?
        var humidity: Double?
        var wind_speed: Double?
        var wind_gust: Double?
        var clouds: Double?
        var pop: Double?
        var rain: Double?
        var snow: Double?
        var weather: [Weather]?
    }

    // MARK: Mapping

    enum MappingError: Error, Hashable { case noForecastData }

    static func map(_ data: Data, coordinate: Coordinate, fetchedAt: Date) throws -> Forecast {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let clock = LocalClock(zoneName: r.timezone, offset: r.timezone_offset, reference: r.hourly?.first?.dt ?? r.daily?.first?.dt)
        var hours = (r.hourly ?? []).compactMap(hour)
        hours.sort { $0.date < $1.date }
        let days = (r.daily ?? []).compactMap { day($0, clock: clock) }
        hours += summaryHours(after: hours.last?.date, daily: r.daily ?? [], clock: clock)
        guard !hours.isEmpty else { throw MappingError.noForecastData }
        return Forecast(coordinate: coordinate, hours: hours, days: days, fetchedAt: fetchedAt, source: .openWeather)
    }

    static func isNight(_ icon: String?) -> Bool { icon?.hasSuffix("n") ?? false }

    static func hour(_ h: Hour) -> HourlyConditions? {
        guard let dt = h.dt, let clouds = h.clouds else { return nil }
        let w = h.weather?.first
        let r = WeatherConditionMapping.openWeather(id: w?.id ?? 804, isNight: isNight(w?.icon))
        let mm = (h.rain?.oneHour ?? 0) + (h.snow?.oneHour ?? 0)
        return HourlyConditions(
            date: Date(timeIntervalSince1970: dt),
            cloudCover: clamp01(clouds / 100),
            precipitationChance: h.pop.map(clamp01),
            precipitationMm: mm,
            visibilityMeters: h.visibility,
            windSpeedKph: (h.wind_speed ?? 0) * 3.6,
            windGustKph: h.wind_gust.map { $0 * 3.6 },
            temperatureC: h.temp ?? 0,
            humidity: clamp01((h.humidity ?? 0) / 100),
            symbolName: w == nil ? "cloud" : r.symbol,
            condition: w == nil ? "cloudy" : r.condition)
    }

    static func day(_ d: Day, clock: LocalClock) -> DailyConditions? {
        guard let dt = d.dt, let hi = d.temp?.max, let lo = d.temp?.min else { return nil }
        let w = d.weather?.first
        let r = WeatherConditionMapping.openWeather(id: w?.id ?? 804, isNight: false)
        return DailyConditions(
            date: Date(timeIntervalSince1970: clock.midnight(of: dt)),
            highC: hi, lowC: lo, precipitationChance: clamp01(d.pop ?? 0),
            symbolName: w == nil ? "cloud" : r.symbol, condition: w == nil ? "cloudy" : r.condition,
            providerSunrise: d.sunrise.map { Date(timeIntervalSince1970: $0) },
            providerSunset: d.sunset.map { Date(timeIntervalSince1970: $0) },
            providerMoonPhase: d.moon_phase)
    }

    /// Hours after the last hourly entry, filled from the daily summaries (`.dailySummary`): cloud, probability,
    /// humidity and wind from the day; no visibility; temperature interpolated through the local day
    /// (night at 00:00, morn 06:00, day 12:00, eve 18:00, night 24:00); rain and snow amounts spread evenly over 24 h.
    static func summaryHours(after last: Date?, daily: [Day], clock: LocalClock) -> [HourlyConditions] {
        guard let last else { return [] }
        var out: [HourlyConditions] = []
        let firstNew = last.timeIntervalSince1970 + 3600
        for d in daily.sorted(by: { ($0.dt ?? 0) < ($1.dt ?? 0) }) {
            guard let dt = d.dt, let clouds = d.clouds else { continue }
            let start = clock.midnight(of: dt)
            let end = clock.nextMidnight(after: start)
            var t = max(start, firstNew)
            // Align to the hourly grid of the provider's own hours.
            let phase = last.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600)
            t = (ceil((t - phase) / 3600) * 3600) + phase
            while t < end {
                let localHour = (t - start) / 3600
                let w = d.weather?.first
                let night = nightAt(t, sunrise: d.sunrise, sunset: d.sunset, localHour: localHour)
                let r = WeatherConditionMapping.openWeather(id: w?.id ?? 804, isNight: night)
                let mm = ((d.rain ?? 0) + (d.snow ?? 0)) / 24
                out.append(HourlyConditions(
                    date: Date(timeIntervalSince1970: t),
                    cloudCover: clamp01(clouds / 100),
                    precipitationChance: d.pop.map(clamp01),
                    precipitationMm: mm,
                    visibilityMeters: nil,
                    windSpeedKph: (d.wind_speed ?? 0) * 3.6,
                    windGustKph: d.wind_gust.map { $0 * 3.6 },
                    temperatureC: temperature(d.temp, localHour: localHour),
                    humidity: clamp01((d.humidity ?? 0) / 100),
                    symbolName: w == nil ? "cloud" : r.symbol,
                    condition: w == nil ? "cloudy" : r.condition,
                    resolution: .dailySummary))
                t += 3600
            }
        }
        return out
    }

    private static func nightAt(_ t: Double, sunrise: Double?, sunset: Double?, localHour: Double) -> Bool {
        if let sunrise, let sunset { return t < sunrise || t >= sunset }
        return localHour < 6 || localHour >= 19
    }

    private static func temperature(_ temp: DayTemp?, localHour h: Double) -> Double {
        guard let temp else { return 0 }
        let anchors: [(Double, Double?)] = [(0, temp.night), (6, temp.morn), (12, temp.day), (18, temp.eve), (24, temp.night)]
        let known = anchors.compactMap { a in a.1.map { (a.0, $0) } }
        guard let first = known.first, let lastKnown = known.last else { return ((temp.min ?? 0) + (temp.max ?? 0)) / 2 }
        if h <= first.0 { return first.1 }
        if h >= lastKnown.0 { return lastKnown.1 }
        for i in 1..<known.count where h <= known[i].0 {
            let (x0, y0) = known[i - 1], (x1, y1) = known[i]
            return y0 + (y1 - y0) * (h - x0) / (x1 - x0)
        }
        return lastKnown.1
    }

    /// The place's local days. The named zone wins when it agrees with `timezone_offset` at the first timestamp, so a
    /// day after a clock change still starts at its real local midnight (the response's single offset is only right
    /// up to the change); otherwise the fixed offset is used (0 when neither is given).
    struct LocalClock {
        private let calendar: Calendar?
        private let offset: Double

        init(zoneName: String?, offset: Double?, reference: Double?) {
            let zone = zoneName.flatMap(TimeZone.init(identifier:))
            if let zone, offset == nil || reference == nil
                || Double(zone.secondsFromGMT(for: Date(timeIntervalSince1970: reference ?? 0))) == offset {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                self.calendar = calendar
            } else {
                self.calendar = nil
            }
            self.offset = offset ?? 0
        }

        /// Start of the local day containing `dt`.
        func midnight(of dt: Double) -> Double {
            if let calendar { return calendar.startOfDay(for: Date(timeIntervalSince1970: dt)).timeIntervalSince1970 }
            return floor((dt + offset) / 86400) * 86400 - offset
        }

        /// Start of the local day after the one starting at `start` (23 or 25 hours on a clock change).
        func nextMidnight(after start: Double) -> Double {
            if let calendar { return calendar.startOfDay(for: Date(timeIntervalSince1970: start + 36 * 3600)).timeIntervalSince1970 }
            return start + 86400
        }
    }

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}
