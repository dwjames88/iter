import Foundation

/// Iter's condition strings and SF Symbols for providers that do not supply them.
/// Strings follow WeatherKit's `WeatherCondition.rawValue` style: clear, partlyCloudy, mostlyCloudy, cloudy, rain,
/// drizzle, thunderstorms, snow, foggy, haze.
enum WeatherConditionMapping {
    struct Result: Equatable {
        var condition: String
        var symbol: String
    }

    /// Cloud thresholds shared by every provider that gives a total cloud fraction (0-1) without a condition code.
    /// < 0.15 clear, < 0.45 partlyCloudy, < 0.80 mostlyCloudy, otherwise cloudy.
    static func sky(cloud: Double, isNight: Bool) -> Result {
        switch cloud {
        case ..<0.15: Result(condition: "clear", symbol: isNight ? "moon.stars" : "sun.max")
        case ..<0.45: Result(condition: "partlyCloudy", symbol: isNight ? "cloud.moon" : "cloud.sun")
        case ..<0.80: Result(condition: "mostlyCloudy", symbol: isNight ? "cloud.moon" : "cloud.sun")
        default: Result(condition: "cloudy", symbol: "cloud")
        }
    }

    /// OpenWeather condition id (https://openweathermap.org/weather-conditions).
    /// 2xx thunderstorms; 3xx drizzle; 5xx rain; 6xx snow (sleet included); 701/741 foggy; 7xx other haze (smoke, dust,
    /// sand, ash); 771 squalls "cloudy" with the wind symbol; 781 tornado "thunderstorms" with the tornado symbol;
    /// 800 clear; 801 and 802 partlyCloudy; 803 mostlyCloudy; 804 cloudy.
    static func openWeather(id: Int, isNight: Bool) -> Result {
        switch id {
        case 200..<300: Result(condition: "thunderstorms", symbol: "cloud.bolt.rain")
        case 300..<400: Result(condition: "drizzle", symbol: "cloud.drizzle")
        case 500..<600: Result(condition: "rain", symbol: "cloud.rain")
        case 600..<700: Result(condition: "snow", symbol: "cloud.snow")
        case 701, 741: Result(condition: "foggy", symbol: "cloud.fog")
        case 771: Result(condition: "cloudy", symbol: "wind")
        case 781: Result(condition: "thunderstorms", symbol: "tornado")
        case 700..<800: Result(condition: "haze", symbol: isNight ? "moon.haze" : "sun.haze")
        case 800: sky(cloud: 0, isNight: isNight)
        case 801, 802: sky(cloud: 0.3, isNight: isNight)
        case 803: sky(cloud: 0.6, isNight: isNight)
        case 804: sky(cloud: 1, isNight: isNight)
        default: Result(condition: "cloudy", symbol: "cloud")
        }
    }

    /// Windy has no condition code: derive one. Order: precipitation (ptype 5 snow, 7 mixture and 8 ice pellets are snow,
    /// others rain; under 0.5 mm/h is drizzle, rain or snow from 0.5 mm/h) at 0.1 mm/h and over; visibility under
    /// 1,000 m foggy; under 5,000 m haze; otherwise the sky thresholds.
    static func windy(cloud: Double, precipitationMm: Double?, precipitationType: Int?, visibilityMeters: Double?, isNight: Bool) -> Result {
        if let mm = precipitationMm, mm >= 0.1 {
            if let t = precipitationType, [5, 7, 8].contains(t) { return Result(condition: "snow", symbol: "cloud.snow") }
            return mm < 0.5 ? Result(condition: "drizzle", symbol: "cloud.drizzle") : Result(condition: "rain", symbol: "cloud.rain")
        }
        if let v = visibilityMeters {
            if v < 1_000 { return Result(condition: "foggy", symbol: "cloud.fog") }
            if v < 5_000 { return Result(condition: "haze", symbol: isNight ? "moon.haze" : "sun.haze") }
        }
        return sky(cloud: cloud, isNight: isNight)
    }

    /// Approximate sun above or below the horizon (NOAA low-precision formula, good to a few minutes) for choosing day or
    /// night symbols where the provider gives no icon.
    static func isNight(at date: Date, latitude: Double, longitude: Double) -> Bool {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = ((357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360)) * .pi / 180
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180
        let epsilon = (23.439 - 0.0000004 * n) * .pi / 180
        let declination = asin(sin(epsilon) * sin(lambda))
        let rightAscension = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let gmst = (280.46061837 + 360.98564736629 * n).truncatingRemainder(dividingBy: 360) * .pi / 180
        let hourAngle = gmst + longitude * .pi / 180 - rightAscension
        let phi = latitude * .pi / 180
        let altitude = asin(sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle))
        return altitude < -0.833 * .pi / 180
    }
}
