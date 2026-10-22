import SwiftUI
import Testing
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

/// Road-like drives for snapshots: the same speed as the estimate, but not marked as an estimate, with a bent path.
struct RoadLikeDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        let estimate = DriveLeg.estimate(from: a, to: b)
        let mid = Coordinate(latitude: (a.latitude + b.latitude) / 2 + 0.05, longitude: (a.longitude + b.longitude) / 2 - 0.05)
        return DriveLeg(from: a, to: b, seconds: estimate.seconds, meters: estimate.meters, isEstimate: false, path: [a, mid, b])
    }
}

@MainActor
enum TripsFixtures {
    static func model(weather: Fixtures.Weather = .sample, seedTrip: Bool = true, drives: any DriveTimeProviding = RoadLikeDrives()) -> AppModel {
        let container = try! IterSchema.makeContainer(inMemory: true)
        let store = IterStore(container: container)
        store.actionName = StoreActionText.name
        let defaults = UserDefaults(suiteName: "IterTripsFixtures-\(UUID().uuidString)")!
        let clock: @Sendable () -> Date = { Fixtures.now }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        let live: any WeatherProviding
        switch weather {
        case .sample: live = sample
        case .notEnabled: live = FailingWeather(error: .notEnabled)
        case .failed: live = FailingWeather(error: .failed("offline"))
        }
        let model = AppModel(store: store, weather: live, search: StubSearch(), geocoder: StubGeocoder(),
                             drives: drives, scout: nil, sampleWeather: sample, defaults: defaults, now: { Fixtures.now })
        if seedTrip { _ = store.seedSampleTrip(startDay: LocalDay(year: 2026, month: 10, day: 7)) }
        for id in ["mesa-arch", "tunnel-view"] { if let s = CuratedSpots.spot(id: id) { store.setSaved(s, true) } }
        return model
    }

    /// The sample trip with day 2 reversed: its sunset stop comes before its sunrise stop, so the day has a conflict and a
    /// Reorder-by-light suggestion (the same thing `-IterSeedTrip conflict` seeds).
    static func conflictedModel() -> AppModel {
        let model = model()
        let store = model.store
        let trip = store.trips()[0]
        store.reorder(day: 1, in: trip, to: trip.orderedStops(onDay: 1).reversed().map(\.id))
        return model
    }

    /// Day 1 is backwards (sunset before sunrise); on day 2 the drive between two sunsets cannot be made.
    static func backwardsModel() -> AppModel {
        let model = model(seedTrip: false)
        let store = model.store
        let trip = store.createTrip(name: "Arches and Monument Valley", startDay: LocalDay(year: 2026, month: 10, day: 7), dayCount: 2)
        let spot = { (id: String) in CuratedSpots.spot(id: id)! }
        store.addStop(spot("delicate-arch"), to: trip, day: 0, session: .goldenEvening)
        store.addStop(spot("mesa-arch"), to: trip, day: 0, session: .goldenMorning)
        store.addStop(spot("monument-valley"), to: trip, day: 1, session: .goldenEvening)
        store.addStop(spot("horseshoe-bend"), to: trip, day: 1, session: .blueEvening)
        return model
    }
}

@MainActor
@Suite(.serialized) struct TripsSnapshotTests {
    private let settle = Duration.milliseconds(1200)

    @Test(.enabled(if: Snapshot.enabled)) func empty() async throws {
        let model = TripsFixtures.model(seedTrip: false)
        try await Snapshot.render(Fixtures.host(NavigationStack { TripsHomeView() }, model: model), screen: "trips", state: "empty", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func list() async throws {
        let model = TripsFixtures.model()
        _ = model.store.createTrip(from: TripTemplates.all[2], startDay: LocalDay(year: 2026, month: 11, day: 14))
        _ = model.store.createTrip(name: "Weekend on the coast", startDay: LocalDay(year: 2026, month: 12, day: 3), dayCount: 3)
        try await Snapshot.render(Fixtures.host(NavigationStack { TripsHomeView() }, model: model), screen: "trips", state: "list", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func builder() async throws {
        let model = TripsFixtures.model()
        let id = model.store.trips()[0].id
        try await Snapshot.render(Fixtures.host(NavigationStack { TripBuilderView(tripID: id, initialDay: 1) }, model: model), screen: "trip", state: "builder", settle: settle)
    }

    /// The Trip Builder panel alone (the inspector's content): the offscreen harness cannot draw `.inspector`, so the panel
    /// is rendered at its own size, 640 x 1400, beside nothing, for the sample trip, the conflicted trip and the offline-weather case.
    @Test(.enabled(if: Snapshot.enabled)) func builderPanel() async throws {
        let model = TripsFixtures.model()
        let size = Snapshot.Size(name: "640x1400", width: 640, height: 1400)
        try await Snapshot.render(Fixtures.host(try await TripBuilderPanelFixture.panel(model, day: 0), model: model),
                                  screen: "trip", state: "builder-panel", sizes: [size], settle: settle, chrome: .bare)
    }

    @Test(.enabled(if: Snapshot.enabled)) func builderPanelConflict() async throws {
        let model = TripsFixtures.conflictedModel()
        let size = Snapshot.Size(name: "640x1400", width: 640, height: 1400)
        try await Snapshot.render(Fixtures.host(try await TripBuilderPanelFixture.panel(model, day: 1), model: model),
                                  screen: "trip", state: "builder-panel-conflict", sizes: [size], settle: settle, chrome: .bare)
    }

    @Test(.enabled(if: Snapshot.enabled)) func builderWeatherOffline() async throws {
        let model = TripsFixtures.model(weather: .notEnabled)
        let id = model.store.trips()[0].id
        try await Snapshot.render(Fixtures.host(NavigationStack { TripBuilderView(tripID: id, initialDay: nil) }, model: model), screen: "trip", state: "builder-weather-offline", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func builderConflict() async throws {
        let model = TripsFixtures.conflictedModel()
        let id = model.store.trips()[0].id
        try await Snapshot.render(Fixtures.host(NavigationStack { TripBuilderView(tripID: id, initialDay: 1) }, model: model), screen: "trip", state: "builder-conflict", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func builderMissing() async throws {
        let model = TripsFixtures.model(seedTrip: false)
        try await Snapshot.render(Fixtures.host(NavigationStack { TripBuilderView(tripID: UUID(), initialDay: nil) }, model: model), screen: "trip", state: "builder-missing", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func newSheet() async throws {
        let model = TripsFixtures.model()
        let sheet = NewTripSheet(initialStart: LocalDay(year: 2026, month: 10, day: 7), initialTemplate: "canyon-country")
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize() // a sheet is its ideal size, centred in the window
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        try await Snapshot.render(Fixtures.host(sheet, model: model), screen: "trip", state: "new-sheet", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func newSheetEmpty() async throws {
        let model = TripsFixtures.model()
        let sheet = NewTripSheet(initialStart: LocalDay(year: 2026, month: 10, day: 7))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize() // a sheet is its ideal size, centred in the window
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        try await Snapshot.render(Fixtures.host(sheet, model: model), screen: "trip", state: "new-sheet-empty", settle: settle)
    }

    @Test(.enabled(if: Snapshot.enabled)) func changeDatesSheet() async throws {
        let model = TripsFixtures.model()
        let id = model.store.trips()[0].id
        let builder = TripBuilderModel(tripID: id, store: model.store, scheduler: model.scheduler, drives: model.drives,
                                       forecasts: model.forecasts, now: { Fixtures.now })
        let sheet = ChangeDatesSheet(builder: builder)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize() // a sheet is its ideal size, centred in the window
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        try await Snapshot.render(Fixtures.host(sheet, model: model), screen: "trip", state: "change-dates-sheet", settle: settle)
    }

    /// The backwards trip's panel (a drive that does not fit, a day out of order, the transfer card), 640 pt wide.
    @Test(.enabled(if: Snapshot.enabled)) func stopRow() async throws {
        let model = TripsFixtures.backwardsModel()
        let size = Snapshot.Size(name: "640x1100", width: 640, height: 1100)
        try await Snapshot.render(Fixtures.host(try await TripBuilderPanelFixture.panel(model, day: 1), model: model),
                                  screen: "trip", state: "stoprow", sizes: [size], settle: settle, chrome: .bare)
    }

    @Test func fixturesBuild() {
        let model = TripsFixtures.conflictedModel()
        #expect(model.store.trips().first?.orderedStops.count == 6)
        // Keep the model alive while its records are read: the container goes with it.
        let backwards = TripsFixtures.backwardsModel()
        #expect(backwards.store.trips().first?.orderedStops.count == 4)
    }
}

/// The builder panel the way the Mac window hosts it, for snapshots.
@MainActor
enum TripBuilderPanelFixture {
    static func panel(_ model: AppModel, day: Int?) async throws -> some View {
        let id = model.store.trips()[0].id
        let builder = TripBuilderModel(tripID: id, store: model.store, scheduler: model.scheduler, drives: model.drives,
                                       forecasts: model.forecasts, now: { Fixtures.now })
        await builder.waitForLegs()
        let state = TripViewState(day: day)
        let plan = builder.plan!
        let actions = TripCornerActions(planName: plan.name, isLoading: false,
                                        shareItem: LazyTripDocument(tripName: plan.name, build: { nil }),
                                        changeDates: {}, exportTrip: {}, duplicate: {}, delete: {})
        return TripPlanList(plan: plan, builder: builder, state: state, tripActions: actions, changeDates: {}, chooseDay: { _ in })
            .frame(width: 640)
    }
}
