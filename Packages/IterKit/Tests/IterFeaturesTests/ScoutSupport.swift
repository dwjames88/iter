import Foundation
import IterCore
import IterData
import IterServices
@testable import IterFeatures

/// 6 Oct 2026, 10:00 in Denver.
let scoutTestNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

struct ScoutFailingWeather: WeatherProviding {
    let error: WeatherError
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw error }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

struct ScoutNoSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

struct ScoutNoGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

struct ScoutFlatDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

/// A scout the test drives by hand: it reports the stages it is told to and finishes when told to.
final class FakeScout: Scouting, @unchecked Sendable { // test double; state guarded by the lock
    private let lock = NSLock()
    private var _availability: ScoutAvailability
    private var outcome: Result<[ScoutSuggestion], any Error>
    private var gate: CheckedContinuation<Void, Never>?
    private var gated = false
    private(set) var cancelledCount = 0
    private(set) var started = 0
    var stages: [ScoutProgress] = []

    init(availability: ScoutAvailability = .available, outcome: Result<[ScoutSuggestion], any Error> = .success([])) {
        _availability = availability
        self.outcome = outcome
    }

    func holdUntilReleased() { lock.withLock { gated = true } }
    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let g = gate; gate = nil; gated = false; return g
        }
        waiting?.resume()
    }

    func availability() -> ScoutAvailability { lock.withLock { _availability } }

    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] {
        lock.withLock { started += 1 }
        for stage in stages { progress(stage) }
        if lock.withLock({ gated }) {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let resumeNow = lock.withLock { () -> Bool in
                        if gated { gate = c; return false }
                        return true
                    }
                    if resumeNow { c.resume() }
                }
            } onCancel: {
                self.lock.withLock { self.cancelledCount += 1 }
                self.release()
            }
        }
        try Task.checkCancellation()
        return try lock.withLock { outcome }.get()
    }
}

func scoutSuggestion(_ id: String, window: LightWindowKind? = .goldenEvening) -> ScoutSuggestion {
    let spot = CuratedSpots.spot(id: id)!
    return ScoutSuggestion(id: id, spot: spot, provenance: .curated, why: "Open view west.", suggestedWindow: window, driveSeconds: 5400)
}

@MainActor
func scoutAppModel(weather: any WeatherProviding, scout: (any Scouting)?) -> AppModel {
    let container = try! IterSchema.makeContainer(inMemory: true)
    let store = IterStore(container: container)
    let defaults = UserDefaults(suiteName: "ScoutTests-\(UUID().uuidString)")!
    let clock: @Sendable () -> Date = { scoutTestNow }
    return AppModel(store: store, weather: weather, search: ScoutNoSearch(), geocoder: ScoutNoGeocoder(),
                    drives: ScoutFlatDrives(), scout: scout,
                    sampleWeather: CachedWeatherService(wrapping: SampleWeatherService(now: clock)),
                    defaults: defaults, now: { scoutTestNow })
}
