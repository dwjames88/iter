import Foundation
import IterCore

/// The one seam between the weather providers and the network, so tests never touch the wire.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The live transport.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Shared helpers for turning transport results and failures into `WeatherError` without ever leaking an API key.
enum ProviderHTTP {
    /// Maps a non-success status. 401/403 = key rejected, 429 = over the provider's limit, anything else = `provider`.
    /// Returns normally for 2xx.
    static func check(status: Int, body: Data, source: ForecastSource, key: String) throws {
        guard !(200..<300).contains(status) else { return }
        switch status {
        case 401, 403: throw WeatherError.keyRejected(source)
        case 429: throw WeatherError.overDailyLimit(source)
        default:
            var detail = "HTTP \(status)"
            if let message = errorMessage(in: body) { detail += ": " + message }
            throw WeatherError.provider(source, redact(detail, key: key))
        }
    }

    /// The provider's own `message` field (OpenWeather `{cod, message}`, Windy `{message}`), if the body has one.
    static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let message = object["message"] as? String { return String(message.prefix(200)) }
        return nil
    }

    /// Turns any thrown error into a `WeatherError` whose detail contains neither the key nor the request URL.
    static func map(_ error: any Error, source: ForecastSource, key: String) -> WeatherError {
        if let e = error as? WeatherError { return e }
        if let url = error as? URLError {
            return .provider(source, redact("Network error: \(url.code.rawValue) \(url.localizedDescription)", key: key))
        }
        if error is DecodingError {
            return .provider(source, "The response could not be read")
        }
        return .provider(source, redact("\(type(of: error))", key: key))
    }

    static func redact(_ text: String, key: String) -> String {
        guard !key.isEmpty else { return text }
        return text.replacingOccurrences(of: key, with: "•••")
    }
}
