import Foundation
import IterCore

/// Windy Point Forecast v2 (https://api.windy.com/point-forecast/docs): a model forecast at a point, 3-hourly for GFS,
/// interpolated to hours. Needs the user's key. Memory-only cache (Windy's terms forbid storing the data), counted against `CallBudget`.
///
/// A testing key returns randomly shuffled data. With `keyType == .testing`, or when the response carries a top-level
/// "warning", the call is still made (so the integration can be checked) but the service throws `.testingKey(.windy)`:
/// Iter never scores from shuffled data, and nothing is cached.
///
/// Model: "Best for the spot" picks ICON-EU in Europe, NAM CONUS in the contiguous US, else GFS; a regional model that
/// answers 204/400 or has no cloud layers is retried once with GFS. `Forecast.model` names the model that answered.
public struct WindyService: WeatherProviding {
    public var source: ForecastSource { .windy }
    public static let endpoint = URL(string: "https://api.windy.com/api/point-forecast/v2")!
    /// Parameters requested. `ptype` is for the condition symbol only.
    static let parameters = ["temp", "dewpoint", "precip", "wind", "windGust", "lclouds", "mclouds", "hclouds", "rh", "cbase", "visibility", "ptype"]

    private let keys: APIKeyResolver
    private let transport: any HTTPTransport
    private let cache: ProviderCache
    private let budget: CallBudget
    private let keyType: WindyKeyType
    private let modelMode: WindyModelMode
    private let now: @Sendable () -> Date

    public init(keys: APIKeyResolver, transport: any HTTPTransport, cache: ProviderCache, budget: CallBudget,
                keyType: WindyKeyType = .testing, modelMode: WindyModelMode = .bestForSpot,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.keys = keys
        self.transport = transport
        self.cache = cache
        self.budget = budget
        self.keyType = keyType
        self.modelMode = modelMode
        self.now = now
    }

    private enum Attempt { case ok(WindyMapping.Output), tryGFS }

    public func forecast(for coordinate: Coordinate) async throws -> Forecast {
        guard let key = keys.resolve(.windy)?.value else { throw WeatherError.missingKey(.windy) }
        let transport = transport, budget = budget, now = now, keyType = keyType
        let first = modelMode.model(for: coordinate)
        return try await cache.forecast(for: coordinate) {
            do {
                var output: WindyMapping.Output
                switch try await Self.attempt(first, coordinate, key, transport, budget, now) {
                case .ok(let o): output = o
                case .tryGFS:
                    guard first != .gfs else { throw WeatherError.provider(.windy, "The model returned no usable data") }
                    switch try await Self.attempt(.gfs, coordinate, key, transport, budget, now) {
                    case .ok(let o): output = o
                    case .tryGFS: throw WeatherError.provider(.windy, "The model returned no usable data")
                    }
                }
                if keyType == .testing || output.warning != nil { throw WeatherError.testingKey(.windy) }
                return output.forecast
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ProviderHTTP.map(error, source: .windy, key: key)
            }
        }
    }

    private static func attempt(_ model: WindyModel, _ c: Coordinate, _ key: String, _ transport: any HTTPTransport,
                                _ budget: CallBudget, _ now: @Sendable () -> Date) async throws -> Attempt {
        try budget.reserve(.windy)
        let (data, response) = try await transport.data(for: request(model: model, coordinate: c, key: key))
        // A regional model that cannot serve this point answers 204 or 400: retry with GFS. For GFS itself a 400 is a real
        // request or key problem, so it falls through to `check`, which keeps Windy's own message (redacted).
        if response.statusCode == 204 || (response.statusCode == 400 && model != .gfs) { return .tryGFS }
        try ProviderHTTP.check(status: response.statusCode, body: data, source: .windy, key: key)
        let output: WindyMapping.Output
        do {
            output = try WindyMapping.map(data, coordinate: c, model: model, fetchedAt: now())
        } catch {
            throw WeatherError.provider(.windy, "The response could not be read")
        }
        return output.hasClouds ? .ok(output) : .tryGFS
    }

    static func request(model: WindyModel, coordinate c: Coordinate, key: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "lat": (c.latitude * 10_000).rounded() / 10_000,
            "lon": (c.longitude * 10_000).rounded() / 10_000,
            "model": model.rawValue,
            "parameters": parameters,
            "levels": ["surface"],
            "key": key,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// "Contains data from the Windy database", linking windy.com.
    /// NOTE: Windy's API terms ALSO require the Windy logo, unscaled and clickable to windy.com, wherever the data appears.
    /// The logo is a brand asset this package does not ship; the app layer must add it beside this text.
    public func attribution() async -> WeatherAttributionInfo? {
        WeatherAttributionInfo(serviceName: "Windy", legalPageURL: URL(string: "https://www.windy.com")!,
                               requiredText: "Contains data from the Windy database")
    }
}
