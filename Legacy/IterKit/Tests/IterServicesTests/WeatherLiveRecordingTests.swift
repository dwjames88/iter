import Testing
import Foundation
import IterCore
import IterAstro
import IterData
import IterLight
@testable import IterServices

// Live OpenWeather One Call 3.0 check on two curated spots, with optional fixture recording.
// Gated like the other live tests: ITER_LIVE=1 and a resolvable key. Recording also needs ITER_RECORD_FIXTURES=1.
// Nothing here ever prints or writes the key, the request or its URL.

private let liveEnabled = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"
private let recordEnabled = ProcessInfo.processInfo.environment["ITER_RECORD_FIXTURES"] == "1"
private func liveKey() -> String? { APIKeyResolver(store: KeychainAPIKeyStore()).resolve(.openWeather)?.value }

private let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

/// True if any string anywhere in `value` equals the key or contains its first 8 characters.
private func containsKey(_ value: Any, key: String) -> Bool {
    let prefix = String(key.prefix(8))
    switch value {
    case let s as String: return s == key || (!prefix.isEmpty && s.contains(prefix))
    case let a as [Any]: return a.contains { containsKey($0, key: key) }
    case let d as [String: Any]: return d.contains { containsKey($0.key, key: key) || containsKey($0.value, key: key) }
    default: return false
    }
}

private func keys(_ value: Any?) -> String {
    guard let d = value as? [String: Any] else { return "(absent)" }
    return d.keys.sorted().joined(separator: ", ")
}

@Suite("Weather live recording", .serialized) struct WeatherLiveRecordingTests {
    /// Spots: "mesa-arch" (Utah high desert, America/Denver) and "haystack-rock" (Oregon coast, marine climate,
    /// America/Los_Angeles). The curated catalogue is US-only, so this is the widest climate contrast available.
    static let spotIDs = ["mesa-arch", "haystack-rock"]

    @Test(.enabled(if: liveEnabled && liveKey() != nil, "ITER_LIVE=1 and an OpenWeather key"))
    func openWeatherLiveTwoSpots() async throws {
        let key = try #require(liveKey())
        let engine = LightEngine(ephemeris: Astronomy())

        for id in Self.spotIDs {
            let spot = try #require(CuratedSpots.spot(id: id), "curated spot \(id) missing")
            let zone = spot.timeZone

            // Fetch the raw bytes through the service's own request builder. The request never leaves this scope.
            let data: Data
            do {
                let request = OpenWeatherService.request(for: spot.coordinate, key: key)
                let (body, response) = try await URLSessionTransport().data(for: request)
                guard response.statusCode == 200 else {
                    let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                    let cod = object?["cod"].map { "\($0)" } ?? "none"
                    let message = (object?["message"] as? String).map { ProviderHTTP.redact($0, key: key) } ?? "none"
                    print("[\(id)] HTTP \(response.statusCode) cod=\(cod) message=\(message)")
                    Issue.record("\(id): HTTP \(response.statusCode)")
                    continue
                }
                data = body
            } catch {
                // Transport errors can embed the URL (and so the key): report only the code.
                let code = (error as? URLError)?.code.rawValue
                Issue.record("\(id): transport failed (URLError code \(code.map(String.init) ?? "n/a"))")
                continue
            }

            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], "\(id): response is not a JSON object")

            // Map and score with the app's own code.
            let fetchedAt = Date()
            let forecast = try OpenWeatherMapping.map(data, coordinate: spot.coordinate, fetchedAt: fetchedAt)
            #expect(forecast.hours.count >= 48, "\(id)")
            #expect(forecast.source == .openWeather, "\(id)")

            let today = LocalDay(fetchedAt, in: zone)
            let days = [today, today.adding(days: 1)]
            let dayLights = days.map { engine.dayLight(for: spot, on: $0, forecast: forecast, unavailable: nil, now: fetchedAt) }
            let scored = dayLights.flatMap(\.windows).compactMap(\.assessment.lightScore)
            #expect(!scored.isEmpty, "\(id): no scored window")
            #expect(scored.contains { !$0.contributors.isEmpty || !$0.notes.isEmpty }, "\(id): no reasons")
            #expect(scored.allSatisfy { Confidence.allCases.contains($0.confidence) }, "\(id)")

            // Human summary.
            let first48 = forecast.hours.prefix(48)
            let clouds = first48.map(\.cloudCover)
            let vis = first48.compactMap(\.visibilityMeters)
            let fmt = DateFormatter()
            fmt.timeZone = zone
            fmt.dateFormat = "EEE yyyy-MM-dd HH:mm"
            print("""

            ===== \(id) =====
            timezone: \(object["timezone"] as? String ?? "?") (spot zone \(spot.timeZoneIdentifier))
            hours: \(forecast.hours.count), days: \(forecast.days.count)
            cloud cover (first 48h): min \(clouds.min().map { String(format: "%.2f", $0) } ?? "n/a") max \(clouds.max().map { String(format: "%.2f", $0) } ?? "n/a")
            visibility m (first 48h): min \(vis.min().map { String(format: "%.0f", $0) } ?? "n/a") max \(vis.max().map { String(format: "%.0f", $0) } ?? "n/a"), hours without visibility: \(first48.count - vis.count)
            """)
            for dl in dayLights {
                for w in dl.windows {
                    let start = fmt.string(from: w.span.start)
                    switch w.assessment {
                    case .scored(let s):
                        let reasons = s.contributors.map { "\($0.factor.rawValue)/\($0.effect.rawValue)/\($0.points >= 0 ? "+" : "")\($0.points)" }
                            + s.notes.map { "note:\($0.rawValue)" }
                        print("  \(w.kind.rawValue) @ \(start): score \(s.value) \(s.band) confidence \(s.confidence.rawValue) reasons [\(reasons.joined(separator: "; "))]")
                    case .noForecast(let reason):
                        print("  \(w.kind.rawValue) @ \(start): no forecast (\(reason))")
                    }
                }
            }
            let documentedTop: Set<String> = ["lat", "lon", "timezone", "timezone_offset", "current", "minutely", "hourly", "daily", "alerts"]
            let unexpected = Set(object.keys).subtracting(documentedTop).sorted()
            print("""
              top-level keys: \(keys(object))
              current keys: \(keys(object["current"]))
              hourly[0] keys: \(keys((object["hourly"] as? [Any])?.first))
              daily[0] keys: \(keys((object["daily"] as? [Any])?.first))
              unexpected top-level keys: \(unexpected.isEmpty ? "none" : unexpected.joined(separator: ", "))
            """)

            // Recording.
            if recordEnabled {
                if containsKey(object, key: key) {
                    Issue.record("\(id): response contains the API key (or its first 8 characters); NOT writing the fixture")
                    continue
                }
                let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                let url = fixturesDirectory.appendingPathComponent("openweather-onecall3-live-\(id).json")
                try pretty.write(to: url, options: .atomic)
                print("  recorded: \(url.lastPathComponent) (\(pretty.count) bytes)")
            }
        }
    }
}
