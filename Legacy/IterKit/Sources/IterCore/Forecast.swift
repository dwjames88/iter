import Foundation

/// Weather for one hour at one place. Fractions are 0–1; nil means the provider did not supply it.
public struct HourlyConditions: Codable, Hashable, Sendable {
    /// How an hour was obtained from the provider.
    public enum Resolution: String, Codable, Hashable, Sendable {
        /// The provider gave this hour directly.
        case hourly
        /// Linearly interpolated between the provider's three-hourly steps (Windy GFS, ICON).
        case interpolated
        /// Filled from the provider's daily summary, beyond its hourly range (OpenWeather after 48 h).
        case dailySummary
    }

    public var date: Date
    public var cloudCover: Double
    /// Cloud by altitude (WeatherKit `cloudCoverByAltitude`; Windy `lclouds`/`mclouds`/`hclouds`). nil when not provided.
    public var cloudLow: Double?
    public var cloudMid: Double?
    public var cloudHigh: Double?
    /// Probability of precipitation, 0–1. nil when the provider gives amounts only (Windy).
    public var precipitationChance: Double?
    /// Precipitation amount for this hour, millimetres. nil when not provided.
    public var precipitationMm: Double?
    /// Horizontal visibility. nil when the provider or model has none.
    public var visibilityMeters: Double?
    public var windSpeedKph: Double
    public var windGustKph: Double?
    public var temperatureC: Double
    public var humidity: Double
    /// Height of the lowest cloud base above ground (Windy `cbase`). nil when not provided.
    public var cloudBaseMeters: Double?
    /// SF Symbol name (WeatherKit's own, or mapped from the provider's condition code).
    public var symbolName: String
    /// Provider condition, e.g. WeatherKit `WeatherCondition.rawValue` ("mostlyCloudy", "foggy").
    public var condition: String
    public var resolution: Resolution

    public init(date: Date, cloudCover: Double, cloudLow: Double? = nil, cloudMid: Double? = nil, cloudHigh: Double? = nil,
                precipitationChance: Double?, precipitationMm: Double? = nil, visibilityMeters: Double?, windSpeedKph: Double,
                windGustKph: Double? = nil, temperatureC: Double, humidity: Double, cloudBaseMeters: Double? = nil,
                symbolName: String, condition: String, resolution: Resolution = .hourly) {
        self.date = date
        self.cloudCover = cloudCover
        self.cloudLow = cloudLow
        self.cloudMid = cloudMid
        self.cloudHigh = cloudHigh
        self.precipitationChance = precipitationChance
        self.precipitationMm = precipitationMm
        self.visibilityMeters = visibilityMeters
        self.windSpeedKph = windSpeedKph
        self.windGustKph = windGustKph
        self.temperatureC = temperatureC
        self.humidity = humidity
        self.cloudBaseMeters = cloudBaseMeters
        self.symbolName = symbolName
        self.condition = condition
        self.resolution = resolution
    }

    public var hasLayers: Bool { cloudLow != nil && cloudMid != nil && cloudHigh != nil }
}

/// A summary for one day at one place.
public struct DailyConditions: Codable, Hashable, Sendable {
    /// Start of the day in the place's zone.
    public var date: Date
    public var highC: Double
    public var lowC: Double
    public var precipitationChance: Double
    public var symbolName: String
    public var condition: String
    /// The provider's own sun and moon times (OpenWeather), kept as a cross-check for Iter's astronomy. Not displayed.
    public var providerSunrise: Date?
    public var providerSunset: Date?
    /// The provider's moon phase, 0 and 1 new, 0.5 full (OpenWeather `moon_phase`). Not displayed.
    public var providerMoonPhase: Double?

    public init(date: Date, highC: Double, lowC: Double, precipitationChance: Double, symbolName: String, condition: String,
                providerSunrise: Date? = nil, providerSunset: Date? = nil, providerMoonPhase: Double? = nil) {
        self.date = date
        self.highC = highC
        self.lowC = lowC
        self.precipitationChance = precipitationChance
        self.symbolName = symbolName
        self.condition = condition
        self.providerSunrise = providerSunrise
        self.providerSunset = providerSunset
        self.providerMoonPhase = providerMoonPhase
    }
}

/// An hourly forecast for one place.
public struct Forecast: Codable, Hashable, Sendable {
    public var coordinate: Coordinate
    public var hours: [HourlyConditions]
    public var days: [DailyConditions]
    /// When the data was fetched (shown as "Updated 2:00 PM").
    public var fetchedAt: Date
    public var source: ForecastSource
    /// The numerical model behind the data when the provider names one ("GFS", "ICON-EU"); nil otherwise.
    public var model: String?
    /// Providers tried first that failed, in order, when this forecast came from the user's fallback order.
    /// Empty when the first choice answered. Shown beside the source so a fallback is never silent.
    public var fallbackFrom: [ForecastSource]

    public init(coordinate: Coordinate, hours: [HourlyConditions], days: [DailyConditions], fetchedAt: Date, source: ForecastSource,
                model: String? = nil, fallbackFrom: [ForecastSource] = []) {
        self.coordinate = coordinate
        self.hours = hours.sorted { $0.date < $1.date }
        self.days = days
        self.fetchedAt = fetchedAt
        self.source = source
        self.model = model
        self.fallbackFrom = fallbackFrom
    }

    /// The last instant covered by the hourly data.
    public var horizon: Date? { hours.last.map { $0.date.addingTimeInterval(3600) } }

    /// How many consecutive local days, starting at `day`, begin before `horizon` (0 when there are no hours).
    public func coveredDays(from day: LocalDay, in zone: TimeZone) -> Int {
        guard let horizon else { return 0 }
        var count = 0
        while day.adding(days: count).start(in: zone) < horizon { count += 1 }
        return count
    }

    /// The hour containing `date`, or nil if `date` is outside the forecast.
    public func hour(at date: Date) -> HourlyConditions? {
        guard let first = hours.first, date >= first.date, let horizon, date < horizon else { return nil }
        return hours.last { $0.date <= date }
    }

    /// Hours overlapping `span` (at least one if the span is inside the forecast).
    public func hours(overlapping span: TimeSpan) -> [HourlyConditions] {
        let inside = hours.filter { $0.date < span.end && $0.date.addingTimeInterval(3600) > span.start }
        return inside
    }
}

/// The attribution a provider's licence requires wherever its data appears.
/// Apple Weather: the combined mark and the legal page (from WeatherKit). OpenWeather (ODbL): a visible
/// "Weather data © OpenWeather" with a link. Windy (API terms §Attribution): "Contains data from the Windy database",
/// the model's data source, and the Windy logo clickable to windy.com.
public struct WeatherAttributionInfo: Codable, Hashable, Sendable {
    public var serviceName: String
    public var legalPageURL: URL
    /// Apple's combined mark (nil for providers that require a text line instead).
    public var combinedMarkLightURL: URL?
    public var combinedMarkDarkURL: URL?
    /// The text the licence asks for, e.g. "Weather data © OpenWeather". nil for Apple Weather (the mark carries it).
    public var requiredText: String?

    public init(serviceName: String, legalPageURL: URL, combinedMarkLightURL: URL? = nil, combinedMarkDarkURL: URL? = nil,
                requiredText: String? = nil) {
        self.serviceName = serviceName
        self.legalPageURL = legalPageURL
        self.combinedMarkLightURL = combinedMarkLightURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
        self.requiredText = requiredText
    }
}

/// Supplies forecasts. Implementations: WeatherKit, OpenWeather, Windy and the fallback router (IterServices),
/// sample data (Debug menu only), test fakes.
public protocol WeatherProviding: Sendable {
    var source: ForecastSource { get }
    /// Throws `WeatherError`.
    func forecast(for coordinate: Coordinate) async throws -> Forecast
    func attribution() async -> WeatherAttributionInfo?
}

public enum WeatherError: Error, Hashable, Sendable {
    /// WeatherKit is not provisioned for this build.
    case notEnabled
    /// Apple Weather failed (kept for WeatherKit; other providers use `provider`).
    case failed(String)
    case missingKey(ForecastSource)
    case keyRejected(ForecastSource)
    case overDailyLimit(ForecastSource)
    case testingKey(ForecastSource)
    case provider(ForecastSource, String)
    /// The device could not reach the provider.
    case offline(ForecastSource)

    public var unavailableReason: ForecastUnavailableReason {
        switch self {
        case .notEnabled: .weatherServiceNotEnabled
        case .failed(let detail): .serviceFailed(detail: detail)
        case .missingKey(let s): .missingAPIKey(s)
        case .keyRejected(let s): .keyRejected(s)
        case .overDailyLimit(let s): .dailyLimitReached(s)
        case .testingKey(let s): .testingKey(s)
        case .provider(let s, let detail): .providerFailed(s, detail: detail)
        case .offline(let s): .offline(s)
        }
    }
}
