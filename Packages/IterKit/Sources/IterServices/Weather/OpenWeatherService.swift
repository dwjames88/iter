import Foundation
import IterCore

/// OpenWeather One Call 3.0 (https://openweathermap.org/api/one-call-3): 48 hours of hourly data, then daily summaries.
/// Needs the user's key ("One Call by Call" subscription). Cached per spot and hour, persisted by the cache's directory;
/// counted against `CallBudget` before every network call.
public struct OpenWeatherService: WeatherProviding {
    public var source: ForecastSource { .openWeather }
    public static let endpoint = URL(string: "https://api.openweathermap.org/data/3.0/onecall")!

    private let keys: APIKeyResolver
    private let transport: any HTTPTransport
    private let cache: ProviderCache
    private let budget: CallBudget
    private let now: @Sendable () -> Date

    public init(keys: APIKeyResolver, transport: any HTTPTransport, cache: ProviderCache, budget: CallBudget,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.keys = keys
        self.transport = transport
        self.cache = cache
        self.budget = budget
        self.now = now
    }

    public func forecast(for coordinate: Coordinate) async throws -> Forecast {
        guard let key = keys.resolve(.openWeather)?.value else { throw WeatherError.missingKey(.openWeather) }
        let transport = transport, budget = budget, now = now
        return try await cache.forecast(for: coordinate) {
            try budget.reserve(.openWeather)
            let request = Self.request(for: coordinate, key: key)
            do {
                let (data, response) = try await transport.data(for: request)
                try ProviderHTTP.check(status: response.statusCode, body: data, source: .openWeather, key: key)
                return try OpenWeatherMapping.map(data, coordinate: coordinate, fetchedAt: now())
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ProviderHTTP.map(error, source: .openWeather, key: key)
            }
        }
    }

    static func request(for c: Coordinate, key: String) -> URLRequest {
        var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", c.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.4f", c.longitude)),
            URLQueryItem(name: "exclude", value: "current,minutely,alerts"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: key),
        ]
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = 20
        return request
    }

    /// "Weather data © OpenWeather", linking openweathermap.org (ODbL: visible attribution wherever the data appears).
    public func attribution() async -> WeatherAttributionInfo? {
        WeatherAttributionInfo(serviceName: "OpenWeather", legalPageURL: URL(string: "https://openweathermap.org")!,
                               requiredText: "Weather data © OpenWeather")
    }
}
