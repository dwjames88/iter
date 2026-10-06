import SwiftUI
import Testing
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

@MainActor
@Suite(.serialized) struct ExploreSnapshotTests {
    private func screen(_ model: AppModel, configure: (@MainActor (ExploreModel) -> Void)? = nil) -> some View {
        Fixtures.host(Fixtures.inDetailColumn(NavigationStack { ExploreView(configure: configure).spotDestination() }), model: model)
    }

    /// Name order keeps the row's position stable while forecasts arrive; the list is scrolled to it once.
    private func openRow(_ explore: ExploreModel, id: String = "mesa-arch") {
        explore.sort = .name
        explore.select(id, from: .list)
        explore.toggleExpansion()
        explore.requestScroll(to: id)
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

    /// A Near You row opened: its content sits on its own surface, only the summary line is selected.
    @Test(.enabled(if: Snapshot.enabled)) func nearExpanded() async throws {
        try await Snapshot.render(screen(located(Self.sanFrancisco)) { explore in
            explore.select("tunnel-view", from: .list)
            explore.toggleExpansion()
            explore.requestScroll(to: "tunnel-view")
        }, screen: "explore", state: "near-expanded", settle: .seconds(3))
    }

    /// Location denied: the whole list plus the Settings prompt.
    @Test(.enabled(if: Snapshot.enabled)) func locationDenied() async throws {
        let model = Fixtures.model(weather: .sample, location: UserLocationModel(provider: DeniedProvider(), defaults: UserDefaults(suiteName: "IterExploreSnap-\(UUID().uuidString)")!))
        try await Snapshot.render(screen(model), screen: "explore", state: "location-denied", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func defaultState() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model), screen: "explore", state: "default", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func selected() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "selected", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func noForecast() async throws {
        let model = Fixtures.model(weather: .notEnabled)
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "noforecast", settle: .seconds(2))
    }

    /// FIXTURE ONLY: Windy GFS-shaped data from `FixtureProvider`, so the list footer and place card show a non-Apple source.
    @Test(.enabled(if: Snapshot.enabled)) func windySource() async throws {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false)
        model.forecasts.replaceProvider(FixtureProvider(shape: .windy))
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "windy-source", settle: .seconds(2))
    }

    /// FIXTURE ONLY: OpenWeather-shaped data that stands in for Apple Weather, so the fallback wording shows.
    @Test(.enabled(if: Snapshot.enabled)) func openWeatherFallback() async throws {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false)
        model.forecasts.replaceProvider(FixtureProvider(shape: .openWeather))
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "openweather-fallback", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func filteredEmpty() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.filters.sources = [.yours] }, screen: "explore", state: "filtered-empty", settle: .seconds(1))
    }

    @Test(.enabled(if: Snapshot.enabled)) func addSpotMode() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.beginAddingSpot() }, screen: "explore", state: "addspot-mode", settle: .seconds(2))
    }

    /// The list with every row lit for blue hour: the long window names ("Evening blue hour") must not move chips or times.
    @Test(.enabled(if: Snapshot.enabled)) func listBlueHour() async throws {
        let model = Fixtures.model(weather: .sample)
        model.preferredIntent = .blueHour
        try await Snapshot.render(screen(model), screen: "explore", state: "list-bluehour", settle: .seconds(2))
    }

    /// A row opened to its actions and the day's weather, with sample weather.
    @Test(.enabled(if: Snapshot.enabled)) func expandedRow() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { explore in
            openRow(explore)
        },
                                  screen: "explore", state: "expanded", settle: .seconds(3))
    }

    /// A row opened with no forecast: rings and the reason, inside the row.
    @Test(.enabled(if: Snapshot.enabled)) func expandedRowNoForecast() async throws {
        let model = Fixtures.model(weather: .notEnabled)
        try await Snapshot.render(screen(model) { explore in
            openRow(explore)
        },
                                  screen: "explore", state: "expanded-noforecast", settle: .seconds(3))
    }

    @Test func screenBuilds() {
        let model = Fixtures.model()
        let explore = ExploreModel(app: model)
        #expect(explore.rows.count == CuratedSpots.all.count)
    }
}
