import SwiftUI
import Testing
import IterCore
import IterData
import IterServices
import IterDesign
import IterFeatures
@testable import Iter

@MainActor
@Suite(.serialized) struct ExploreSnapshotTests {
    private func screen(_ model: AppModel, configure: (@MainActor (ExploreModel) -> Void)? = nil) -> some View {
        Fixtures.host(Fixtures.inDetailColumn(NavigationStack { ExploreView(configure: configure).spotDestination() }), model: model)
    }

    /// Name order keeps the row's position stable while forecasts arrive; the list is scrolled to it once. Opens the
    /// place panel unless `panel` is false (then the list shows the selected row).
    private func selectRow(_ explore: ExploreModel, id: String = "mesa-arch", panel: Bool = true) {
        explore.sort = .name
        explore.select(id, from: .list)
        if panel { explore.openPanel() }
        explore.requestScroll(to: id)
    }

    /// With generated images in the strip (no network in snapshots).
    private func panelScreen(_ model: AppModel, panel: Bool = true, configure: (@MainActor (ExploreModel) -> Void)? = nil) -> some View {
        screen(model) { explore in
            selectRow(explore, panel: panel)
            configure?(explore)
        }
        .environment(\.spotImagery, FakeImagery(sources: [.lookAround, .satellite]))
    }

    /// The list column's saved width (`ResizableSplit(storageKey: "explore")` reads this default) for one render.
    private func withListColumn<T>(width: Double?, _ body: () async throws -> T) async rethrows -> T {
        let key = "ResizableSplit.explore"
        let old = UserDefaults.standard.object(forKey: key)
        if let width { UserDefaults.standard.set(width, forKey: key) }
        defer { if let old { UserDefaults.standard.set(old, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        return try await body()
    }

    private static let sanFrancisco = Coordinate(latitude: 37.77, longitude: -122.42)
    private static let moab = Coordinate(latitude: 38.57, longitude: -109.55)

    private func located(_ at: Coordinate) -> AppModel {
        let defaults = UserDefaults(suiteName: "IterExploreSnap-\(UUID().uuidString)")!
        let location = UserLocationModel(provider: FixedLocationProvider(at), isSimulated: true, defaults: defaults)
        return Fixtures.model(weather: .sample, location: location)
    }

    @MainActor private final class DeniedProvider: UserLocationProviding {
        var authorization: LocationAuthorization { .denied }
        var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
        func requestAuthorization() {}
        func requestFix() async -> Coordinate? { nil }
    }

    /// Near You, Popular and (collapsed) More Places for someone in San Francisco.
    @Test(.enabled(if: Snapshot.enabled)) func nearSanFrancisco() async throws {
        try await Snapshot.render(screen(located(Self.sanFrancisco)), screen: "explore", state: "near-sf", settle: .seconds(2))
    }

    /// The same for Moab, where the desert spots are close.
    @Test(.enabled(if: Snapshot.enabled)) func nearMoab() async throws {
        try await Snapshot.render(screen(located(Self.moab)), screen: "explore", state: "near-moab", settle: .seconds(2))
    }

    /// Scrolled to the Popular and More Places headers (More Places collapsed, with its count).
    @Test(.enabled(if: Snapshot.enabled)) func nearSectionsBelow() async throws {
        try await Snapshot.render(screen(located(Self.sanFrancisco)) { explore in
            if let id = explore.sections.first(where: { $0.kind == .popular })?.rows.last?.id { explore.requestScroll(to: id) }
        }, screen: "explore", state: "near-more", settle: .seconds(2))
    }

    /// A Near You row opened: its panel replaces the list.
    @Test(.enabled(if: Snapshot.enabled)) func nearSelected() async throws {
        try await Snapshot.render(screen(located(Self.sanFrancisco)) { explore in
            explore.select("tunnel-view", from: .list)
            explore.openPanel()
            explore.requestScroll(to: "tunnel-view")
        }, screen: "explore", state: "near-selected", settle: .seconds(3))
    }

    /// Location denied: the whole list plus the Settings prompt.
    @Test(.enabled(if: Snapshot.enabled)) func locationDenied() async throws {
        let model = Fixtures.model(weather: .sample, location: UserLocationModel(provider: DeniedProvider(), defaults: UserDefaults(suiteName: "IterExploreSnap-\(UUID().uuidString)")!))
        try await Snapshot.render(screen(model), screen: "explore", state: "location-denied", settle: .seconds(2))
    }

    /// Debug ▸ Show Layout Grid on: the 8 pt grid and the row lanes over the list.
    @Test(.enabled(if: Snapshot.enabled)) func gridOn() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { selectRow($0) }.environment(\.showsLayoutGrid, true),
                                  screen: "explore", state: "grid", settle: .seconds(3))
    }

    @Test(.enabled(if: Snapshot.enabled)) func defaultState() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model), screen: "explore", state: "default", settle: .seconds(2))
    }

    /// A row selected, panel closed (Back): the list with its row highlighted.
    @Test(.enabled(if: Snapshot.enabled)) func selected() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "selected", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func noForecast() async throws {
        let model = Fixtures.model(weather: .notEnabled)
        try await Snapshot.render(screen(model) { selectRow($0) }, screen: "explore", state: "noforecast", settle: .seconds(2))
    }

    /// FIXTURE ONLY: Windy GFS-shaped data from `FixtureProvider`, so the list footer and place panel show a non-Apple source.
    @Test(.enabled(if: Snapshot.enabled)) func windySource() async throws {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false)
        model.forecasts.replaceProvider(FixtureProvider(shape: .windy))
        try await Snapshot.render(screen(model) { selectRow($0) }, screen: "explore", state: "windy-source", settle: .seconds(2))
    }

    /// FIXTURE ONLY: OpenWeather-shaped data that stands in for Apple Weather, so the fallback wording shows.
    @Test(.enabled(if: Snapshot.enabled)) func openWeatherFallback() async throws {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false)
        model.forecasts.replaceProvider(FixtureProvider(shape: .openWeather))
        try await Snapshot.render(screen(model) { selectRow($0) }, screen: "explore", state: "openweather-fallback", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func filteredEmpty() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.filters.sources = [.yours] }, screen: "explore", state: "filtered-empty", settle: .seconds(1))
    }

    @Test(.enabled(if: Snapshot.enabled)) func addSpotMode() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.beginAddingSpot() }, screen: "explore", state: "addspot-mode", settle: .seconds(2))
    }

    // MARK: The place panel (the list column's second state), 1280x820

    /// The list state, a row selected (its pin highlighted on the map).
    @Test(.enabled(if: Snapshot.enabled)) func panelListState() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(panelScreen(model, panel: false), screen: "explore", state: "panel-list",
                                  sizes: [Snapshot.regular], settle: .seconds(3))
    }

    /// The panel at the list column's ideal width.
    @Test(.enabled(if: Snapshot.enabled)) func panelOpen() async throws {
        let model = Fixtures.model(weather: .sample)
        try await withListColumn(width: nil) {
            try await Snapshot.render(panelScreen(model), screen: "explore", state: "panel", sizes: [Snapshot.regular], settle: .seconds(3))
        }
    }

    /// The panel with the list column at its 340 pt minimum: the saved split width is set to 340 for the render.
    @Test(.enabled(if: Snapshot.enabled)) func panelAtMinimumWidth() async throws {
        let model = Fixtures.model(weather: .sample)
        try await withListColumn(width: Double(IterSize.listColumnMin)) {
            try await Snapshot.render(panelScreen(model), screen: "explore", state: "panel-340", sizes: [Snapshot.regular], settle: .seconds(3))
        }
    }

    /// The panel scrolled to its lower half (`-IterPanelScrolled YES`).
    @Test(.enabled(if: Snapshot.enabled)) func panelScrolled() async throws {
        let model = Fixtures.model(weather: .sample)
        UserDefaults.standard.set(true, forKey: "IterPanelScrolled")
        defer { UserDefaults.standard.removeObject(forKey: "IterPanelScrolled") }
        try await withListColumn(width: nil) {
            try await Snapshot.render(panelScreen(model), screen: "explore", state: "panel-scrolled", sizes: [Snapshot.regular], settle: .seconds(4))
        }
    }

    /// The panel with tomorrow open in the outlook (`-IterOutlookOpen YES`), scrolled to it.
    @Test(.enabled(if: Snapshot.enabled)) func panelOutlookOpen() async throws {
        let model = Fixtures.model(weather: .sample)
        UserDefaults.standard.set(true, forKey: "IterPanelScrolled")
        UserDefaults.standard.set(true, forKey: "IterOutlookOpen")
        defer {
            UserDefaults.standard.removeObject(forKey: "IterPanelScrolled")
            UserDefaults.standard.removeObject(forKey: "IterOutlookOpen")
        }
        try await withListColumn(width: nil) {
            try await Snapshot.render(panelScreen(model), screen: "explore", state: "panel-outlook-open", sizes: [Snapshot.regular], settle: .seconds(4))
        }
    }

    /// Weather offline: the banner under the header, rows without scores, and the selected row's panel.
    @Test(.enabled(if: Snapshot.enabled)) func weatherOffline() async throws {
        let model = Fixtures.model(weather: .failed)
        try await Snapshot.render(screen(model) { selectRow($0) }, screen: "explore", state: "weather-offline", settle: .seconds(3))
    }

    @Test func screenBuilds() {
        let model = Fixtures.model()
        let explore = ExploreModel(app: model)
        #expect(explore.rows.count == CuratedSpots.all.count)
    }
}
