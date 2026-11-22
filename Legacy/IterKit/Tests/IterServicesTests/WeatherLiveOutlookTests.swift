import Testing
import Foundation
import IterCore
import IterAstro
@testable import IterLight
@testable import IterServices

// Opt-in diagnostic: scores the 8-day outlook (golden morning and golden evening) from LIVE OpenWeather data at four
// places and prints, per window, the score, the averaged inputs and the breakdown. Skipped unless ITER_LIVE_WEATHER=1
// and a key is in the login Keychain. The key is never printed, logged or written; failures report only a status code.

private let enabled = ProcessInfo.processInfo.environment["ITER_LIVE_WEATHER"] == "1"
private func liveKey() -> String? { KeychainAPIKeyStore().key(for: .openWeather) }

@Suite("Weather live outlook", .serialized) struct WeatherLiveOutlookTests {
    static let places: [(name: String, lat: Double, lon: Double, zone: String)] = [
        ("Mesa Arch UT", 38.2675, -109.8683, "America/Denver"),
        ("Seattle WA", 47.6062, -122.3321, "America/Los_Angeles"),
        ("Old Man of Storr", 57.5070, -6.1830, "Europe/London"),
        ("Cape Town", -33.9249, 18.4241, "Africa/Johannesburg"),
    ]

    @Test(.enabled(if: enabled && liveKey() != nil, "ITER_LIVE_WEATHER=1 and an OpenWeather key"))
    func outlookScoresAgainstLiveData() async throws {
        let key = try #require(liveKey())
        let engine = LightEngine(ephemeris: Astronomy())

        for p in Self.places {
            let spot = Spot(id: "live-\(p.name)", name: p.name, locality: "", coordinate: Coordinate(latitude: p.lat, longitude: p.lon),
                            timeZoneIdentifier: p.zone, category: .landscape, origin: .curated)
            let data: Data
            do {
                let (body, response) = try await URLSessionTransport().data(for: OpenWeatherService.request(for: spot.coordinate, key: key))
                guard response.statusCode == 200 else {
                    Issue.record("\(p.name): HTTP \(response.statusCode)")
                    continue
                }
                data = body
            } catch {
                // Transport errors can embed the URL (and so the key): report only the code.
                Issue.record("\(p.name): transport failed (URLError code \((error as? URLError)?.code.rawValue ?? 0))")
                continue
            }
            let now = Date()
            let forecast = try OpenWeatherMapping.map(data, coordinate: spot.coordinate, fetchedAt: now)
            let today = LocalDay(now, in: spot.timeZone)
            let fmt = DateFormatter()
            fmt.timeZone = spot.timeZone
            fmt.dateFormat = "EEE MM-dd HH:mm"
            func pct(_ v: Double?) -> String { v.map { String(format: "%.0f", $0 * 100) } ?? "-" }

            print("\n===== \(p.name): \(forecast.hours.count) hours, \(forecast.days.count) days, horizon \(forecast.horizon.map { fmt.string(from: $0) } ?? "?") =====")
            for dl in engine.outlook(for: spot, from: today, days: 8, forecast: forecast, unavailable: nil, now: now) {
                for w in dl.windows where w.kind.isGolden {
                    guard case .scored(let s) = w.assessment else { print("  \(w.kind.rawValue) \(fmt.string(from: w.span.start)): no forecast"); continue }
                    let c = LightEngine.conditions(in: forecast, over: w.span)
                    let res = c.map { $0.resolutions.map(\.rawValue).sorted().joined(separator: "+") } ?? "?"
                    let factors = s.contributors.map { "\($0.factor.rawValue)\($0.points >= 0 ? "+" : "")\($0.points)" }.joined(separator: " ")
                    print("  \(w.kind == .goldenMorning ? "AM" : "PM") \(fmt.string(from: w.span.start)) score \(s.value) [\(res)] cloud \(pct(c?.totalCloud)) low/mid/high \(pct(c?.low))/\(pct(c?.mid))/\(pct(c?.high)) pop \(pct(c?.precipitationChance)) mm/h \(c?.precipitationMm.map { String(format: "%.2f", $0) } ?? "-") vis \(c?.visibilityMeters.map { String(format: "%.1fkm", $0 / 1000) } ?? "-") | \(factors) | notes \(s.notes.map(\.rawValue).joined(separator: ","))")
                    #expect((5...100).contains(s.value))
                }
            }
        }
    }
}
