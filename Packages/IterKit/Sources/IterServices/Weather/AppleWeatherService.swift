import Foundation
import CoreLocation
import IterCore
import WeatherKit

/// Forecasts from Apple WeatherKit.
///
/// Without the WeatherKit entitlement (a free Personal Team cannot have it) the system throws an
/// XPC connection error; that is turned into `WeatherError.notEnabled` so the UI can say exactly why there is no forecast.
public struct AppleWeatherService: WeatherProviding {
    public var source: ForecastSource { .appleWeather }

    /// How far back from "now" the hourly data starts, so the hour in progress is included.
    public static let lookBack: TimeInterval = 3600
    /// WeatherKit serves ten days of hourly and daily forecast.
    public static let lookAhead: TimeInterval = 10 * 24 * 3600

    private let now: @Sendable () -> Date

    public init() {
        self.now = { Date() }
    }

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    public func forecast(for coordinate: Coordinate) async throws -> IterCore.Forecast {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let fetchedAt = now()
        let start = fetchedAt.addingTimeInterval(-Self.lookBack)
        let end = fetchedAt.addingTimeInterval(Self.lookAhead)
        do {
            let (hourly, daily) = try await WeatherService.shared.weather(
                for: location,
                including: .hourly(startDate: start, endDate: end), .daily(startDate: start, endDate: end))
            return IterCore.Forecast(
                coordinate: coordinate,
                hours: hourly.forecast.map(Self.convert),
                days: daily.forecast.map(Self.convert),
                fetchedAt: fetchedAt,
                source: .appleWeather)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WeatherErrorMapping.map(error)
        }
    }

    public func attribution() async -> WeatherAttributionInfo? {
        do {
            let a = try await WeatherService.shared.attribution
            return WeatherAttributionInfo(serviceName: a.serviceName, legalPageURL: a.legalPageURL,
                                          combinedMarkLightURL: a.combinedMarkLightURL, combinedMarkDarkURL: a.combinedMarkDarkURL)
        } catch {
            return nil
        }
    }

    // MARK: Conversion

    static func convert(_ h: HourWeather) -> HourlyConditions {
        HourlyConditions(
            date: h.date,
            cloudCover: h.cloudCover,
            cloudLow: h.cloudCoverByAltitude.low,
            cloudMid: h.cloudCoverByAltitude.medium,
            cloudHigh: h.cloudCoverByAltitude.high,
            precipitationChance: h.precipitationChance,
            visibilityMeters: h.visibility.converted(to: .meters).value,
            windSpeedKph: h.wind.speed.converted(to: .kilometersPerHour).value,
            temperatureC: h.temperature.converted(to: .celsius).value,
            humidity: h.humidity,
            symbolName: h.symbolName,
            condition: h.condition.rawValue)
    }

    static func convert(_ d: DayWeather) -> DailyConditions {
        DailyConditions(
            date: d.date,
            highC: d.highTemperature.converted(to: .celsius).value,
            lowC: d.lowTemperature.converted(to: .celsius).value,
            precipitationChance: d.precipitationChance,
            symbolName: d.symbolName,
            condition: d.condition.rawValue)
    }
}

/// Turns WeatherKit and system errors into the IterCore `WeatherError`.
enum WeatherErrorMapping {
    /// The XPC service WeatherKit uses to obtain its auth token; unreachable when the process lacks the entitlement.
    static let authServiceName = "com.apple.weatherkit.authservice"

    static func map(_ error: any Error) -> IterCore.WeatherError {
        if let e = error as? IterCore.WeatherError { return e }
        if let e = error as? WeatherKit.WeatherError, e == .permissionDenied { return .notEnabled }
        if isMissingEntitlement(description: String(reflecting: error)) { return .notEnabled }
        let ns = error as NSError
        if isMissingEntitlement(description: ns.localizedDescription + " " + ns.userInfo.description) { return .notEnabled }
        return .failed(String(reflecting: error))
    }

    static func isMissingEntitlement(description: String) -> Bool {
        description.contains(authServiceName)
    }
}
