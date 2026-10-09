import SwiftUI
import SwiftData
import Testing
import IterCore
import IterData
import IterServices
import IterDesign
import IterFeatures
@testable import Iter

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

    // MARK: Locations

    /// A model with two location folders of saved curated spots and one unfiled spot.
    private static func libraryModel() -> (AppModel, coast: FolderRecord) {
        let model = Fixtures.model(weather: .sample, saved: ["haystack-rock", "bixby-bridge", "point-reyes-lighthouse", "mesa-arch", "tunnel-view"])
        let coast = model.store.createFolder(name: "Coast", kind: .locations)
        let desert = model.store.createFolder(name: "Desert", kind: .locations)
        let saved = model.store.savedPlaces()
        model.store.movePlaces(saved.filter { ["haystack-rock", "bixby-bridge", "point-reyes-lighthouse"].contains($0.curatedID ?? "") }, to: coast, index: nil)
        model.store.movePlaces(saved.filter { $0.curatedID == "mesa-arch" }, to: desert, index: nil)
        return (model, coast)
    }

    @Test(.enabled(if: Snapshot.enabled)) func locations() async throws {
        let (model, coast) = Self.libraryModel()
        _ = Self.addUserSpot(model)
        try await Snapshot.render(Fixtures.host(Self.screen(LocationsView(folderID: nil)), model: model), screen: "locations", state: "all")
        try await Snapshot.render(Fixtures.host(Self.screen(LocationsView(folderID: coast.id)), model: model), screen: "locations", state: "folder")
        let empty = Fixtures.model(weather: .sample, seedTrip: false, saved: [])
        try await Snapshot.render(Fixtures.host(Self.screen(LocationsView(folderID: nil)), model: empty), screen: "locations", state: "empty")
        let emptyFolder = empty.store.createFolder(name: "Someday", kind: .locations)
        try await Snapshot.render(Fixtures.host(Self.screen(LocationsView(folderID: emptyFolder.id)), model: empty), screen: "locations", state: "empty-folder")
        let noWeather = Fixtures.model(weather: .notEnabled)
        _ = Self.addUserSpot(noWeather)
        try await Snapshot.render(Fixtures.host(Self.screen(LocationsView(folderID: nil)), model: noWeather), screen: "locations", state: "noforecast")
    }

    /// The whole Locations screen with Mesa Arch selected (its pin scaled and shadowed, drawn last).
    @Test(.enabled(if: Snapshot.enabled)) func locationsMapSelected() async throws {
        let (model, _) = Self.libraryModel()
        let mesa = model.store.savedPlaces().first { $0.spot.name == "Mesa Arch" }
        let screen = Self.screen(LocationsView(folderID: nil, selected: mesa.map { [$0.id] } ?? []))
        try await Snapshot.render(Fixtures.host(screen, model: model), screen: "locations", state: "map-selected", settle: .seconds(2))
    }

    // MARK: Sidebar

    @Test(.enabled(if: Snapshot.enabled)) func sidebar() async throws {
        let (model, _) = Self.libraryModel()
        let trips = model.store.trips()
        if let first = trips.first { model.store.setPinned(first, true) }
        let utah = model.store.createFolder(name: "Utah 2027", kind: .trips)
        model.store.createFolder(name: "Scouting", kind: .trips)
        let canyon = model.store.createTrip(name: "Canyon Country", startDay: LocalDay(year: 2027, month: 4, day: 3), dayCount: 4)
        model.store.moveTrips([canyon], to: utah, index: nil)
        model.store.createTrip(name: "Weekend Away", startDay: LocalDay(year: 2026, month: 11, day: 14), dayCount: 2)
        let sidebar = SidebarView().frame(width: IterSize.sidebarIdeal, height: 560)
        try await Snapshot.render(Fixtures.host(sidebar, model: model), screen: "sidebar", state: "library", sizes: [Snapshot.regular])
    }

    @Test func libraryFixtureFilesPlaces() {
        let (model, coast) = Self.libraryModel()
        #expect(model.store.savedPlaces(in: coast).count == 3)
        #expect(model.store.savedPlaces().count == 5)
    }

    @Test func offlineStatusWordsMatchTheSpec() {
        #expect(OfflineStatusText.label(.none) == nil)
        #expect(OfflineStatusText.label(.downloading(done: 3, total: 9)) == "Downloading for offline use, 3 of 9")
        #expect(OfflineStatusText.label(.ready(savedAt: Fixtures.now)) == "Ready offline")
        #expect(OfflineStatusText.label(.stale(savedAt: Fixtures.now, reason: .tripChanged)) == "Trip changed since download")
        #expect(OfflineStatusText.label(.stale(savedAt: Fixtures.now, reason: .forecastOld)) == "Forecast is more than 12 hours old")
        #expect(OfflineStatusText.label(.stale(savedAt: Fixtures.now, reason: .incomplete)) == "Some items didn't download")
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

    // MARK: Settings

    @Test(.enabled(if: Snapshot.enabled)) func settings() async throws {
        let sample = Fixtures.model(weather: .sample)
        try await Snapshot.render(Fixtures.host(SettingsView(), model: sample), screen: "settings", state: "general")
        let bare = Fixtures.model(weather: .notEnabled)
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: bare), screen: "settings", state: "weather", settle: .seconds(1))
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: sample), screen: "settings", state: "weather-working", sizes: [Snapshot.regular], settle: .seconds(1))
        let needsKey = await Fixtures.weatherSettingsModel(primary: .openWeather, fallback: .appleWeather)
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: needsKey), screen: "settings", state: "weather-needs-key", settle: .seconds(1))
        let working = await Fixtures.weatherSettingsModel(primary: .openWeather, fallback: .appleWeather, keys: [.openWeather], working: [.openWeather])
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: working), screen: "settings", state: "weather-openweather-working", settle: .seconds(1))
        let testing = await Fixtures.weatherSettingsModel(primary: .windy, fallback: .openWeather, keys: [.windy])
        try await Snapshot.render(Fixtures.host(SettingsView(initialTab: .weather), model: testing), screen: "settings", state: "weather-testing-key", settle: .seconds(1))
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

// MARK: - Weather settings behaviour (runs without snapshots)

@MainActor
@Suite struct WeatherSettingsStatusTests {
    @Test func statusWordsMatchTheSpec() {
        let time = Fixtures.now.formatted(date: .omitted, time: .shortened)
        #expect(WeatherSettingsText.status(.working(lastUpdate: Fixtures.now), source: .openWeather).text == "Working · last update \(time)")
        #expect(WeatherSettingsText.status(.needsKey, source: .windy).text == "Needs an API key")
        #expect(WeatherSettingsText.status(.dailyCap(calls: 800, cap: 800), source: .openWeather).text == "Daily cap reached (800 of 800)")
        #expect(WeatherSettingsText.status(.failed(detail: "x"), source: .openWeather).text == "Couldn't reach OpenWeather")
    }

    @Test func fixtureModelsCarryTheStatuses() async {
        let needsKey = await Fixtures.weatherSettingsModel(primary: .openWeather, fallback: .appleWeather)
        #expect(needsKey.weather.status(for: .openWeather) == .needsKey)
        let testing = await Fixtures.weatherSettingsModel(primary: .windy, keys: [.windy])
        #expect(testing.weather.status(for: .windy) == .testingKey)
        let working = await Fixtures.weatherSettingsModel(primary: .openWeather, keys: [.openWeather], working: [.openWeather])
        #expect(working.weather.status(for: .openWeather) == .working(lastUpdate: Fixtures.now))
    }
}
