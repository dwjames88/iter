import SwiftUI
import SwiftData
import Testing
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

/// Scout double for snapshots: reports a fixed availability and never answers.
private struct SnapshotScout: Scouting {
    var state: ScoutAvailability = .available
    func availability() -> ScoutAvailability { state }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { [] }
}

private struct FailingGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw URLError(.notConnectedToInternet) }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

@MainActor
@Suite(.serialized) struct LibrarySnapshotTests {
    private static let pin = Coordinate(latitude: 36.5786, longitude: -118.2920)

    private static func addUserSpot(_ model: AppModel) -> PlaceRecord {
        model.store.createUserSpot(name: "Back field at Lone Pine", locality: "Lone Pine, CA", coordinate: pin,
                                   timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise, .night],
                                   notes: "Park at the pullout; the gate is usually open before dawn.", walkInMinutes: 12)
    }

    private static func screen<V: View>(_ view: V) -> some View { NavigationStack { view } }

    // MARK: Saved

    @Test(.enabled(if: Snapshot.enabled)) func saved() async throws {
        let model = Fixtures.model(weather: .sample)
        _ = Self.addUserSpot(model)
        try await Snapshot.render(Fixtures.host(Self.screen(SavedView()), model: model), screen: "saved", state: "list")
        let empty = Fixtures.model(weather: .sample, seedTrip: false, saved: [])
        try await Snapshot.render(Fixtures.host(Self.screen(SavedView()), model: empty), screen: "saved", state: "empty")
        let noWeather = Fixtures.model(weather: .notEnabled)
        _ = Self.addUserSpot(noWeather)
        try await Snapshot.render(Fixtures.host(Self.screen(SavedView()), model: noWeather), screen: "saved", state: "noforecast")
    }

    // MARK: Editor

    @Test(.enabled(if: Snapshot.enabled)) func editor() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(Fixtures.host(SpotEditorSheet(mode: .create(Self.pin)), model: model), screen: "editor", state: "create")
        let record = Self.addUserSpot(model)
        try await Snapshot.render(Fixtures.host(SpotEditorSheet(mode: .edit(record)), model: model), screen: "editor", state: "edit")

        let failing = AppModel(store: model.store, weather: FailingWeather(error: .notEnabled), search: StubSearch(),
                               geocoder: FailingGeocoder(), drives: EstimateDrives(), scout: nil, now: { Fixtures.now })
        try await Snapshot.render(Fixtures.host(SpotEditorSheet(mode: .create(Self.pin)), model: failing), screen: "editor", state: "create-lookup-failed")
    }

    // MARK: Scout

    private static func suggestions() -> [ScoutSuggestion] {
        let mesa = CuratedSpots.spot(id: "mesa-arch")!
        let tunnel = CuratedSpots.spot(id: "tunnel-view")!
        let maps1 = Spot(id: "maps-1", name: "Latourell Falls", locality: "Corbett, OR", coordinate: Coordinate(latitude: 45.5370, longitude: -122.2161),
                         timeZoneIdentifier: "America/Los_Angeles", category: .waterfall, origin: .appleMaps)
        let maps2 = Spot(id: "maps-2", name: "Hoyt Arboretum", locality: "Portland, OR", coordinate: Coordinate(latitude: 45.5100, longitude: -122.7160),
                         timeZoneIdentifier: "America/Los_Angeles", category: .forest, origin: .appleMaps)
        return [
            ScoutSuggestion(id: "maps-2", spot: maps2, provenance: .appleMaps,
                            why: "Tall conifers hold fog well into the morning, and the paths run east so the first sun comes through the trunks.",
                            suggestedWindow: .goldenMorning, driveSeconds: 12 * 60),
            ScoutSuggestion(id: "maps-1", spot: maps1, provenance: .appleMaps,
                            why: "A tall waterfall in a mossy gorge; overcast keeps the water even.", suggestedWindow: .goldenMorning, driveSeconds: 38 * 60),
            ScoutSuggestion(id: "tunnel-view", spot: tunnel, provenance: .curated,
                            why: "Valley fog fills below the viewpoint at first light.", suggestedWindow: .goldenMorning, driveSeconds: 95 * 60),
            ScoutSuggestion(id: "mesa-arch", spot: mesa, provenance: .curated, why: "", suggestedWindow: .goldenMorning, driveSeconds: nil),
        ]
    }

    private static let request = "Foggy forest spots within two hours of Portland for sunrise"

    @Test(.enabled(if: Snapshot.enabled)) func scout() async throws {
        let model = Fixtures.model(weather: .sample)
        func scoutModel(_ app: AppModel, _ availability: ScoutAvailability = .available, state: ScoutState = .idle, request: String = "") -> ScoutModel {
            ScoutModel(app: app, scout: SnapshotScout(state: availability), state: state, request: request)
        }
        try await Snapshot.render(Fixtures.host(Self.screen(ScoutView(model: scoutModel(model))), model: model), screen: "scout", state: "idle")
        let running = scoutModel(model, state: .running(stage: .searching("Portland, Oregon"), started: Fixtures.now.addingTimeInterval(-14)), request: Self.request)
        try await Snapshot.render(Fixtures.host(Self.screen(ScoutView(model: running)), model: model), screen: "scout", state: "running")
        let results = scoutModel(model, state: .results(Self.suggestions()), request: Self.request)
        try await Snapshot.render(Fixtures.host(Fixtures.inDetailColumn(Self.screen(ScoutView(model: results))), model: model), screen: "scout", state: "results", settle: .seconds(1))

        let bare = Fixtures.model(weather: .notEnabled)
        let noForecast = scoutModel(bare, state: .results(Self.suggestions()), request: Self.request)
        try await Snapshot.render(Fixtures.host(Fixtures.inDetailColumn(Self.screen(ScoutView(model: noForecast))), model: bare), screen: "scout", state: "results-noforecast", settle: .seconds(1))

        let unavailable: [(String, ScoutAvailability)] = [("unavailable-not-enabled", .appleIntelligenceNotEnabled),
                                                          ("unavailable-device", .deviceNotEligible),
                                                          ("unavailable-downloading", .modelNotReady)]
        for (state, availability) in unavailable {
            let m = scoutModel(model, availability)
            try await Snapshot.render(Fixtures.host(Self.screen(ScoutView(model: m)), model: model), screen: "scout", state: state, sizes: [Snapshot.regular])
        }
        let none = scoutModel(model, state: .failed(.noResults), request: Self.request)
        try await Snapshot.render(Fixtures.host(Self.screen(ScoutView(model: none)), model: model), screen: "scout", state: "no-results", sizes: [Snapshot.regular])
        let guardrail = scoutModel(model, state: .failed(.guardrail), request: "x")
        try await Snapshot.render(Fixtures.host(Self.screen(ScoutView(model: guardrail)), model: model), screen: "scout", state: "guardrail", sizes: [Snapshot.regular])
    }

    // MARK: Settings

    @Test(.enabled(if: Snapshot.enabled)) func settings() async throws {
        let sample = Fixtures.model(weather: .sample)
        try await Snapshot.render(Fixtures.host(SettingsView(), model: sample), screen: "settings", state: "general")
        let bare = Fixtures.model(weather: .notEnabled)
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: bare), screen: "settings", state: "weather", settle: .seconds(1))
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: sample), screen: "settings", state: "weather-working", sizes: [Snapshot.regular], settle: .seconds(1))
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .intelligence), model: bare), screen: "settings", state: "intelligence", sizes: [Snapshot.regular])
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .about), model: bare), screen: "settings", state: "about", sizes: [Snapshot.regular])
    }

    // MARK: Behaviour (runs without snapshots)

    @Test func smokeHookNeverCrashesOffline() async {
        let model = Fixtures.model()
        await SmokeHook.run(model)
        #expect(model.store.trips().count >= 1)
    }

    @Test func editorSavesAUserSpotThroughTheStore() {
        let model = Fixtures.model(seedTrip: false, saved: [])
        let record = Self.addUserSpot(model)
        #expect(model.store.savedPlaces().contains { $0.id == record.id })
        #expect(record.origin == .user)
    }
}
