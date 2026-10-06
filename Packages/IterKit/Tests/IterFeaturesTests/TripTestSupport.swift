import Foundation
import IterCore
import IterAstro
import IterLight
import IterData
@testable import IterFeatures

/// Records every drive asked for; can be told to fail.
actor FakeDrives: DriveTimeProviding {
    private(set) var calls: [LegRequest] = []
    private let fail: Bool
    private let minutes: Double

    struct LegRequest: Hashable, Sendable {
        var from: Coordinate
        var to: Coordinate
    }

    init(fail: Bool = false, minutes: Double = 60) {
        self.fail = fail
        self.minutes = minutes
    }

    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        calls.append(LegRequest(from: a, to: b))
        if fail { throw MapFailure.noRoute }
        return DriveLeg(from: a, to: b, seconds: minutes * 60, meters: 80_000, isEstimate: false, path: [a, b])
    }

    enum MapFailure: Error { case noRoute }
}

struct NoWeather: WeatherProviding {
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw WeatherError.notEnabled }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

@MainActor
struct TripHarness {
    let store: IterStore
    let scheduler: TripScheduler
    let forecasts: ForecastCenter
    static let start = LocalDay(year: 2026, month: 10, day: 7)
    static let denver = TimeZone(identifier: "America/Denver")!

    init() {
        let container = try! IterSchema.makeContainer(inMemory: true)
        store = IterStore(container: container)
        scheduler = TripScheduler(engine: LightEngine(ephemeris: Astronomy()))
        forecasts = ForecastCenter(provider: NoWeather())
    }

    func spot(_ id: String) -> Spot { CuratedSpots.spot(id: id)! }

    func model(for trip: TripRecord, drives: FakeDrives = FakeDrives(), dismissals: SuggestionDismissals = SuggestionDismissals(),
                defaults: UserDefaults = UserDefaults(suiteName: "TripHarness-\(UUID().uuidString)")!) -> TripBuilderModel {
        TripBuilderModel(tripID: trip.id, store: store, scheduler: scheduler, drives: drives, forecasts: forecasts,
                         dismissals: dismissals, defaults: defaults, now: { LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: Self.denver) })
    }

    /// Two days: day 0 Mesa Arch (sunrise) then Delicate Arch (sunset); day 1 Horseshoe Bend (sunset).
    func makeTrip() -> TripRecord {
        let trip = store.createTrip(name: "Test", startDay: Self.start, dayCount: 2)
        store.addStop(spot("mesa-arch"), to: trip, day: 0, session: .goldenMorning)
        store.addStop(spot("delicate-arch"), to: trip, day: 0, session: .goldenEvening)
        store.addStop(spot("horseshoe-bend"), to: trip, day: 1, session: .goldenEvening)
        return trip
    }
}
