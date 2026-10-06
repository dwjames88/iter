import Foundation
import IterCore

/// Windy Point Forecast v2 models Iter uses, with the region choice.
public enum WindyModel: String, Hashable, Sendable {
    case gfs, iconEu, namConus

    /// The name shown beside the source ("Windy · GFS") and stored on `Forecast.model`.
    public var displayName: String {
        switch self {
        case .gfs: "GFS"
        case .iconEu: "ICON-EU"
        case .namConus: "NAM CONUS"
        }
    }

    /// Approximate coverage boxes (documented as approximations: a miss returns 204 or 400 and the service retries with GFS).
    /// ICON-EU: 29.5...70.5 N, 23.5 W...62.5 E. NAM CONUS: the contiguous United States, 24...50 N, 125...66 W.
    public static func best(for c: Coordinate) -> WindyModel {
        if (29.5...70.5).contains(c.latitude), (-23.5...62.5).contains(c.longitude) { return .iconEu }
        if (24.0...50.0).contains(c.latitude), (-125.0 ... -66.0).contains(c.longitude) { return .namConus }
        return .gfs
    }
}

/// "Best for the spot" (default) or always GFS.
public enum WindyModelMode: String, Codable, CaseIterable, Hashable, Sendable {
    case bestForSpot
    case forceGFS

    func model(for c: Coordinate) -> WindyModel { self == .forceGFS ? .gfs : WindyModel.best(for: c) }
}

/// Which kind of Windy key the user holds. Testing keys return randomly shuffled data and are never used for scores.
public enum WindyKeyType: String, Codable, CaseIterable, Hashable, Sendable {
    case testing
    case professional
}

/// Maps a Windy Point Forecast v2 response to an Iter `Forecast`. Pure.
///
/// Response: `ts` in milliseconds, `units` object, and arrays like `"temp-surface"`, `"lclouds-surface"`. A missing key means
/// the model lacks the parameter; arrays may hold null. Units are converted by the `units` string, never assumed; a
/// parameter with an unrecognised unit is dropped.
///
/// - Steps are interpolated linearly to hours. Hours in a step longer than one hour are `.interpolated` (including the
///   native step itself, so confidence treats the whole dataset as three-hourly); otherwise `.hourly`. Nothing is
///   extrapolated: an hour needs both neighbouring values, else that field is nil there.
/// - Total cloud is derived (Windy has none): `1 - (1-low)(1-mid)(1-high)`, random overlap. An hour with no layer at all is dropped;
///   with some layers null the total uses the layers present (a lower bound) and the missing layers stay nil.
/// - Precipitation: `past3hprecip` is the accumulation over the PRECEDING three hours; each of those hours gets value / 3 mm.
/// - Probability is nil. Wind = hypot(u, v). Humidity from `rh`, else derived from temperature and dew point (Magnus).
///   Temperature, wind and humidity read 0 when the model lacks them (the contract keeps them non-optional).
struct WindyMapping {
    struct Output {
        var forecast: Forecast
        /// True when the response carries at least one cloud layer. A regional model without any should be retried on GFS.
        var hasClouds: Bool
        /// A top-level "warning" string means a testing-tier response.
        var warning: String?
    }

    enum MappingError: Error, Hashable { case malformed, noCloudData }

    static let windowSeconds = 3.0 * 3600

    static func map(_ data: Data, coordinate: Coordinate, model: WindyModel, fetchedAt: Date) throws -> Output {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tsRaw = root["ts"] as? [Any] else { throw MappingError.malformed }
        let warning = root["warning"] as? String
        let units = root["units"] as? [String: Any] ?? [:]
        let ts = tsRaw.compactMap { ($0 as? NSNumber)?.doubleValue }.map { $0 / 1000 }
        guard ts.count == tsRaw.count, ts.count >= 1, zip(ts, ts.dropFirst()).allSatisfy({ $0 < $1 }) else { throw MappingError.malformed }

        func series(_ name: String, convert: (Double, String) -> Double?) -> [Double?]? {
            guard let raw = root[name] as? [Any], raw.count == ts.count else { return nil }
            let unit = (units[name] as? String) ?? ""
            return raw.map { v in (v as? NSNumber).flatMap { convert($0.doubleValue, unit) } }
        }
        func level(_ base: String) -> String { base + "-surface" }

        let temp = series(level("temp"), convert: toCelsius)
        let dew = series(level("dewpoint"), convert: toCelsius)
        let windU = series(level("wind_u"), convert: toKph)
        let windV = series(level("wind_v"), convert: toKph)
        let gust = series(level("gust"), convert: toKph)
        let low = series(level("lclouds"), convert: toFraction)
        let mid = series(level("mclouds"), convert: toFraction)
        let high = series(level("hclouds"), convert: toFraction)
        let rh = series(level("rh"), convert: toFraction)
        let cbase = series(level("cbase"), convert: toMeters)
        let visibility = series(level("visibility"), convert: toMeters)
        let precip = series(level("past3hprecip"), convert: toMillimeters)
        let ptype = series(level("ptype")) { v, _ in v }

        let hasClouds = low != nil || mid != nil || high != nil
        guard hasClouds else { return Output(forecast: Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: fetchedAt, source: .windy, model: model.displayName), hasClouds: false, warning: warning) }

        // Hourly grid from the first whole hour at or after ts[0] to the last at or before ts[last].
        let firstHour = ceil(ts[0] / 3600) * 3600
        var hours: [HourlyConditions] = []
        var t = firstHour
        var i0 = 0
        while t <= ts[ts.count - 1] {
            while i0 + 1 < ts.count && ts[i0 + 1] <= t { i0 += 1 }
            let i1 = min(i0 + 1, ts.count - 1)
            // The step this hour sits in (the next one on a native step; the previous one at the very end).
            let span: Double = i1 != i0 ? ts[i1] - ts[i0] : (i0 > 0 ? ts[i0] - ts[i0 - 1] : 3600)
            let f = (ts[i0] == t || i1 == i0) ? 0 : (t - ts[i0]) / (ts[i1] - ts[i0])
            /// Linear between the two surrounding steps; nil if either is null (no extrapolation).
            func exact(_ s: [Double?]?) -> Double? {
                guard let s else { return nil }
                if f == 0 { return s[i0] }
                guard let a = s[i0], let b = s[i1] else { return nil }
                return a + (b - a) * f
            }

            /// Categorical (precipitation type): the nearer step, never a blend.
            func nearest(_ s: [Double?]?) -> Double? {
                guard let s else { return nil }
                return f < 0.5 ? s[i0] : s[i1]
            }

            let l = clamp01opt(exact(low)), m = clamp01opt(exact(mid)), h = clamp01opt(exact(high))
            let layers = [l, m, h].compactMap { $0 }
            if layers.isEmpty { t += 3600; continue }
            let cover = 1 - layers.reduce(1) { $0 * (1 - $1) }

            let u = exact(windU), v = exact(windV)
            let wind = (u != nil && v != nil) ? hypot(u!, v!) : 0
            let temperature = exact(temp)
            var humidity = clamp01opt(exact(rh))
            if humidity == nil, let tc = temperature, let dc = exact(dew) { humidity = magnus(temperature: tc, dewPoint: dc) }

            let mm = precipitation(endingHourAt: t + 3600, ts: ts, values: precip)
            let vis = exact(visibility)
            let type = nearest(ptype).map { Int($0.rounded()) }
            let date = Date(timeIntervalSince1970: t)
            let night = WeatherConditionMapping.isNight(at: date.addingTimeInterval(1800), latitude: coordinate.latitude, longitude: coordinate.longitude)
            let r = WeatherConditionMapping.windy(cloud: cover, precipitationMm: mm, precipitationType: type, visibilityMeters: vis, isNight: night)
            hours.append(HourlyConditions(
                date: date, cloudCover: cover, cloudLow: l, cloudMid: m, cloudHigh: h,
                precipitationChance: nil, precipitationMm: mm, visibilityMeters: vis,
                windSpeedKph: wind, windGustKph: exact(gust), temperatureC: temperature ?? 0, humidity: humidity ?? 0,
                cloudBaseMeters: exact(cbase), symbolName: r.symbol, condition: r.condition,
                resolution: span > 3600 ? .interpolated : .hourly))
            t += 3600
        }
        let days = dailySummaries(hours, coordinate: coordinate)
        return Output(forecast: Forecast(coordinate: coordinate, hours: hours, days: days, fetchedAt: fetchedAt, source: .windy, model: model.displayName),
                      hasClouds: true, warning: warning)
    }

    /// The mm in the hour ending at `end`: the first step at or after `end` holds the accumulation over the three hours
    /// before it; the hour must lie inside that window.
    static func precipitation(endingHourAt end: Double, ts: [Double], values: [Double?]?) -> Double? {
        guard let values, let j = ts.firstIndex(where: { $0 >= end }) else { return nil }
        guard end > ts[j] - windowSeconds, let v = values[j] else { return nil }
        return max(0, v) / 3
    }

    /// Daily summaries from the hours (local day approximated by the spot's solar day): high, low, the heaviest hour as
    /// the symbol, probability 0 because Windy gives none. They carry no precipitation chance beyond that.
    static func dailySummaries(_ hours: [HourlyConditions], coordinate: Coordinate) -> [DailyConditions] {
        let shift = coordinate.longitude / 15 * 3600
        var byDay: [Int: [HourlyConditions]] = [:]
        for h in hours { byDay[Int(floor((h.date.timeIntervalSince1970 + shift) / 86400)), default: []].append(h) }
        return byDay.keys.sorted().compactMap { day in
            guard let hs = byDay[day], hs.count >= 12 else { return nil }
            let noon = hs.min { abs(($0.date.timeIntervalSince1970 + shift).truncatingRemainder(dividingBy: 86400) - 46800) < abs(($1.date.timeIntervalSince1970 + shift).truncatingRemainder(dividingBy: 86400) - 46800) } ?? hs[0]
            return DailyConditions(date: Date(timeIntervalSince1970: Double(day) * 86400 - shift),
                                   highC: hs.map(\.temperatureC).max() ?? 0, lowC: hs.map(\.temperatureC).min() ?? 0,
                                   precipitationChance: 0, symbolName: noon.symbolName, condition: noon.condition)
        }
    }

    // MARK: Units

    static func toCelsius(_ v: Double, _ unit: String) -> Double? {
        switch unit {
        case "K": v - 273.15
        case "°C", "C", "degC": v
        case "°F", "F", "degF": (v - 32) * 5 / 9
        default: nil
        }
    }

    static func toKph(_ v: Double, _ unit: String) -> Double? {
        switch unit {
        case "m*s-1", "m/s", "m s-1": v * 3.6
        case "km/h", "kph", "km*h-1": v
        case "kt", "kn", "knots": v * 1.852
        case "mph": v * 1.609344
        default: nil
        }
    }

    /// Percent to a 0-1 fraction; a unit of "" or "1" is taken as already a fraction.
    static func toFraction(_ v: Double, _ unit: String) -> Double? {
        switch unit {
        case "%": v / 100
        case "1", "fraction": v
        default: nil
        }
    }

    static func toMeters(_ v: Double, _ unit: String) -> Double? {
        switch unit {
        case "m": v
        case "km": v * 1000
        case "ft": v * 0.3048
        default: nil
        }
    }

    static func toMillimeters(_ v: Double, _ unit: String) -> Double? {
        switch unit {
        case "mm", "kg*m-2": v
        case "m": v * 1000
        case "in": v * 25.4
        default: nil
        }
    }

    private static func clamp01opt(_ v: Double?) -> Double? { v.map { min(1, max(0, $0)) } }

    /// Relative humidity (0-1) from temperature and dew point, °C (Magnus, a = 17.62, b = 243.12).
    static func magnus(temperature t: Double, dewPoint d: Double) -> Double {
        min(1, max(0, exp(17.62 * d / (243.12 + d)) / exp(17.62 * t / (243.12 + t))))
    }
}
