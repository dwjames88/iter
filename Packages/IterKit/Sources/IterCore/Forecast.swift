import Foundation

/// Weather for one hour at one place. Fractions are 0–1; nil means the provider did not supply it.
public struct HourlyConditions: Codable, Hashable, Sendable {
    public var date: Date
    public var cloudCover: Double
    /// Cloud by altitude (WeatherKit `cloudCoverByAltitude`, macOS 15+). nil when not provided.
    public var cloudLow: Double?
    public var cloudMid: Double?
    public var cloudHigh: Double?
    public var precipitationChance: Double
    public var visibilityMeters: Double
    public var windSpeedKph: Double
    public var temperatureC: Double
    public var humidity: Double
    /// SF Symbol name supplied by the provider (WeatherKit `symbolName`).
    public var symbolName: String
    /// Provider condition, e.g. WeatherKit `WeatherCondition.rawValue` ("mostlyCloudy", "foggy").
    public var condition: String

    public init(date: Date, cloudCover: Double, cloudLow: Double? = nil, cloudMid: Double? = nil, cloudHigh: Double? = nil,
                precipitationChance: Double, visibilityMeters: Double, windSpeedKph: Double, temperatureC: Double,
                humidity: Double, symbolName: String, condition: String) {
        self.date = date
        self.cloudCover = cloudCover
        self.cloudLow = cloudLow
        self.cloudMid = cloudMid
        self.cloudHigh = cloudHigh
        self.precipitationChance = precipitationChance
        self.visibilityMeters = visibilityMeters
        self.windSpeedKph = windSpeedKph
        self.temperatureC = temperatureC
        self.humidity = humidity
        self.symbolName = symbolName
        self.condition = condition
    }
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

    public init(date: Date, highC: Double, lowC: Double, precipitationChance: Double, symbolName: String, condition: String) {
        self.date = date
        self.highC = highC
        self.lowC = lowC
        self.precipitationChance = precipitationChance
        self.symbolName = symbolName
        self.condition = condition
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

    public init(coordinate: Coordinate, hours: [HourlyConditions], days: [DailyConditions], fetchedAt: Date, source: ForecastSource) {
        self.coordinate = coordinate
        self.hours = hours.sorted { $0.date < $1.date }
        self.days = days
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// The last instant covered by the hourly data.
    public var horizon: Date? { hours.last.map { $0.date.addingTimeInterval(3600) } }

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

/// Apple Weather attribution, required wherever WeatherKit data appears.
public struct WeatherAttributionInfo: Codable, Hashable, Sendable {
    public var serviceName: String
    public var legalPageURL: URL
    public var combinedMarkLightURL: URL
    public var combinedMarkDarkURL: URL

    public init(serviceName: String, legalPageURL: URL, combinedMarkLightURL: URL, combinedMarkDarkURL: URL) {
        self.serviceName = serviceName
        self.legalPageURL = legalPageURL
        self.combinedMarkLightURL = combinedMarkLightURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
    }
}

/// Supplies forecasts. Implementations: WeatherKit (IterServices), sample data (Debug menu only), test fakes.
public protocol WeatherProviding: Sendable {
    var source: ForecastSource { get }
    /// Throws `WeatherError`.
    func forecast(for coordinate: Coordinate) async throws -> Forecast
    func attribution() async -> WeatherAttributionInfo?
}

public enum WeatherError: Error, Hashable, Sendable {
    case notEnabled
    case failed(String)

    public var unavailableReason: ForecastUnavailableReason {
        switch self {
        case .notEnabled: .weatherServiceNotEnabled
        case .failed(let detail): .serviceFailed(detail: detail)
        }
    }
}
