import Testing
import Foundation
import SwiftUI
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

// MARK: - Launch

@Suite struct IterIOSLaunchTests {
    @Test func colorSchemeSwitchIsOffByDefault() {
        #expect(AppLaunch.forcedColorScheme == nil)
    }

    @MainActor @Test func openSettingsActionCallsItsHandler() {
        var calls = 0
        let action = OpenIterSettingsAction { calls += 1 }
        action()
        action()
        #expect(calls == 2)
    }

    @MainActor @Test func defaultOpenSettingsActionIsHarmless() {
        OpenIterSettingsAction()()
    }
}

// MARK: - ShellState

@MainActor @Suite struct ShellStateTests {
    @Test func startsOnExploreWithTabs() {
        let s = ShellState()
        #expect(s.phoneTab == .explore)
        #expect(s.usesTabs)
        #expect(s.openTripID == nil && s.openFolderID == nil)
        #expect(!s.showsSettingsSheet)
    }

    @Test func followExplore() {
        let s = ShellState()
        s.phoneTab = .trips
        s.follow(.explore)
        #expect(s.phoneTab == .explore)
    }

    @Test func followTripsClearsOpenTrip() {
        let s = ShellState()
        s.openTripID = UUID()
        s.follow(.trips)
        #expect(s.phoneTab == .trips)
        #expect(s.openTripID == nil)
    }

    @Test func followNilActsLikeTrips() {
        let s = ShellState()
        s.openTripID = UUID()
        s.follow(nil)
        #expect(s.phoneTab == .trips)
        #expect(s.openTripID == nil)
    }

    @Test func followTripOpensIt() {
        let s = ShellState()
        let id = UUID()
        s.follow(.trip(id))
        #expect(s.phoneTab == .trips)
        #expect(s.openTripID == id)
    }

    @Test func followLocationsClearsOpenFolder() {
        let s = ShellState()
        s.openFolderID = UUID()
        s.follow(.locations)
        #expect(s.phoneTab == .locations)
        #expect(s.openFolderID == nil)
    }

    @Test func followFolderOpensIt() {
        let s = ShellState()
        let id = UUID()
        s.follow(.locationFolder(id))
        #expect(s.phoneTab == .locations)
        #expect(s.openFolderID == id)
    }

    @Test func tripSurvivesVisitingOtherTabs() {
        let s = ShellState()
        let id = UUID()
        s.follow(.trip(id))
        s.follow(.explore)
        #expect(s.openTripID == id)
        s.follow(.locations)
        #expect(s.openTripID == id)
    }

    @Test func folderSurvivesVisitingTrips() {
        let s = ShellState()
        let id = UUID()
        s.follow(.locationFolder(id))
        s.follow(.trip(UUID()))
        #expect(s.openFolderID == id)
    }

    @Test func showSettingsSelectsTabWhenUsingTabs() {
        let s = ShellState()
        s.usesTabs = true
        s.showSettings()
        #expect(s.phoneTab == .settings)
        #expect(!s.showsSettingsSheet)
    }

    @Test func showSettingsPresentsSheetWithoutTabs() {
        let s = ShellState()
        s.usesTabs = false
        s.showSettings()
        #expect(s.showsSettingsSheet)
        #expect(s.phoneTab == .explore)
    }
}

// MARK: - Navigation

@MainActor @Suite struct IOSNavigationTests {
    private func route() throws -> SpotRoute {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let trip = store.seedSampleTrip(startDay: LocalDay(year: 2026, month: 6, day: 1))
        return SpotRoute(spot: try #require(trip.plan.stops.first).spot, day: nil)
    }

    @Test func openOnExplorePushesExplorePath() throws {
        let nav = AppNavigation()
        nav.selection = .explore
        let r = try route()
        nav.open(r)
        #expect(nav.explorePath == [r])
        #expect(nav.tripPath.isEmpty && nav.locationsPath.isEmpty)
    }

    @Test func openOnTripPushesTripPath() throws {
        let nav = AppNavigation()
        nav.selection = .trip(UUID())
        let r = try route()
        nav.open(r)
        #expect(nav.tripPath == [r])
        #expect(nav.explorePath.isEmpty)
    }

    @Test func openOnTripsListPushesTripPath() throws {
        let nav = AppNavigation()
        nav.selection = .trips
        nav.open(try route())
        #expect(nav.tripPath.count == 1)
    }

    @Test func openOnLocationsAndFolderPushesLocationsPath() throws {
        let nav = AppNavigation()
        let r = try route()
        nav.selection = .locations
        nav.open(r)
        nav.selection = .locationFolder(UUID())
        nav.open(r)
        #expect(nav.locationsPath == [r, r])
        #expect(nav.tripPath.isEmpty && nav.explorePath.isEmpty)
    }

    @Test func openWithNilSelectionSwitchesToExplore() throws {
        let nav = AppNavigation()
        nav.selection = nil
        nav.open(try route())
        #expect(nav.selection == .explore)
        #expect(nav.explorePath.count == 1)
    }

    @Test func showSetsSelection() {
        let nav = AppNavigation()
        let id = UUID()
        nav.show(.trip(id))
        #expect(nav.selection == .trip(id))
    }

    @Test func showThenFollowOpensTripOnPhone() {
        let nav = AppNavigation()
        let shell = ShellState()
        let id = UUID()
        nav.show(.trip(id))
        shell.follow(nav.selection)
        #expect(shell.phoneTab == .trips && shell.openTripID == id)
    }

    @Test func phoneRouteEqualityAndHashing() throws {
        let id = UUID()
        let r = try route()
        #expect(PhoneRoute.trip(id) == .trip(id))
        #expect(PhoneRoute.trip(id) != .folder(id))
        #expect(PhoneRoute.spot(r) == .spot(r))
        #expect(Set([PhoneRoute.trip(id), .trip(id), .folder(id), .spot(r), .spot(r)]).count == 3)
    }

    @Test func spotRouteDayDistinguishesRoutes() throws {
        let r = try route()
        var other = r
        other.day = LocalDay(year: 2026, month: 6, day: 2)
        #expect(r != other)
    }
}

// MARK: - TripImport

@MainActor @Suite struct TripImportTests {
    private func tempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "iter-test-\(UUID().uuidString).iter")
        try data.write(to: url)
        return url
    }

    @Test func roundTripMakesANewTripWithSameContent() throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let trip = store.seedSampleTrip(startDay: LocalDay(year: 2026, month: 6, day: 1))
        let url = try tempFile(try store.document(for: trip).encoded())
        defer { try? FileManager.default.removeItem(at: url) }

        guard case .success(let id) = TripImport.read(url, into: store) else {
            Issue.record("import failed"); return
        }
        #expect(id != trip.id)
        let imported = try #require(store.trip(id: id))
        #expect(imported.name == trip.name)
        #expect(imported.plan.stops.count == trip.plan.stops.count)
        #expect(store.trips().count == 2)
    }

    @Test func garbageFails() throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let url = try tempFile(Data("not json".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .failure(let message) = TripImport.read(url, into: store) else {
            Issue.record("expected failure"); return
        }
        #expect(message == String(localized: "The file isn't a readable Iter trip.", comment: "Import error"))
        #expect(store.trips().isEmpty)
    }

    @Test func missingFileFails() throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let url = FileManager.default.temporaryDirectory.appending(path: "iter-missing-\(UUID().uuidString).iter")
        if case .success = TripImport.read(url, into: store) { Issue.record("expected failure") }
    }

    @Test func futureVersionSaysNewerVersion() throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let trip = store.seedSampleTrip(startDay: LocalDay(year: 2026, month: 6, day: 1))
        let future = TripDocument(trip: trip.plan, formatVersion: TripDocument.currentFormatVersion + 1)
        let url = try tempFile(try future.encoded())
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .failure(let message) = TripImport.read(url, into: store) else {
            Issue.record("expected failure"); return
        }
        #expect(message == String(localized: "It was made by a newer version of Iter.", comment: "Import error"))
        #expect(store.trips().count == 1)
    }
}

// MARK: - Defaults and weather

@MainActor @Suite struct IOSWeatherDefaultsTests {
    @Test func firstRunPrimaryIsOpenWeather() {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        guard domain["iter.weather.primary"] == nil else { return }  // a stored choice wins; don't assert then
        #expect(UserDefaults.standard.string(forKey: "iter.weather.primary") == "openWeather")
    }

    @Test func weatherSettingsReadRegisteredDefault() {
        let suite = "iter.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: ["iter.weather.primary": "openWeather"])
        let setup = WeatherSetup(keyStore: InMemoryAPIKeyStore(), cacheDirectory: nil, defaults: defaults)
        #expect(setup.settings.primary == .openWeather)
    }

    @Test func storedChoiceBeatsRegisteredDefault() {
        let suite = "iter.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: ["iter.weather.primary": "openWeather"])
        defaults.set("windy", forKey: "iter.weather.primary")
        let setup = WeatherSetup(keyStore: InMemoryAPIKeyStore(), cacheDirectory: nil, defaults: defaults)
        #expect(setup.settings.primary == .windy)
    }
}

// MARK: - Keychain

@Suite struct IOSKeychainTests {
    private func store() -> KeychainAPIKeyStore {
        KeychainAPIKeyStore(service: "com.dwjames.iter.tests.\(UUID().uuidString)")
    }

    @Test func setAndReadBack() throws {
        let s = store()
        defer { try? s.removeKey(for: .openWeather) }
        #expect(s.key(for: .openWeather) == nil)
        try s.setKey("abc123", for: .openWeather)
        #expect(s.key(for: .openWeather) == "abc123")
    }

    @Test func replaceOverwrites() throws {
        let s = store()
        defer { try? s.removeKey(for: .openWeather) }
        try s.setKey("one", for: .openWeather)
        try s.setKey("two", for: .openWeather)
        #expect(s.key(for: .openWeather) == "two")
    }

    @Test func removeDeletesAndIsIdempotent() throws {
        let s = store()
        defer { try? s.removeKey(for: .windy) }
        try s.setKey("k", for: .windy)
        try s.removeKey(for: .windy)
        #expect(s.key(for: .windy) == nil)
        try s.removeKey(for: .windy)
    }

    @Test func providersAreIndependent() throws {
        let s = store()
        defer { try? s.removeKey(for: .openWeather); try? s.removeKey(for: .windy) }
        try s.setKey("ow", for: .openWeather)
        try s.setKey("wy", for: .windy)
        try s.removeKey(for: .openWeather)
        #expect(s.key(for: .windy) == "wy")
    }
}

// MARK: - Platform shims

@MainActor @Suite struct IOSPlatformShimTests {
    @Test func nsFontAliasResolves() {
        #expect(NSFont.preferredFont(forTextStyle: .body).pointSize > 0)
    }

    @Test func eventScoreWidthsArePositive() {
        for variant: EventScore.Variant in [.compact, .regular, .large, .pin] {
            #expect(EventScore.laneWidth(variant) > 0)
            #expect(EventScore.unitWidth(variant, timeStyle: .start) > EventScore.laneWidth(variant))
        }
    }

    @Test func largerVariantsAreWider() {
        #expect(EventScore.unitWidth(.large, timeStyle: .start) > EventScore.unitWidth(.compact, timeStyle: .start))
    }
}
