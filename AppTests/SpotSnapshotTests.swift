import SwiftUI
import Testing
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

@MainActor
@Suite(.serialized) struct SpotSnapshotTests {
    private var mesaArch: Spot { CuratedSpots.spot(id: "mesa-arch")! }

    private func render(_ page: SpotPage, model: AppModel, state: String) async throws {
        try await Snapshot.render(Fixtures.host(NavigationStack { page }, model: model), screen: "spot", state: state,
                                sizes: Snapshot.sizes + [Snapshot.Size(name: "1280x2600", width: 1280, height: 2600)], settle: .seconds(1))
    }

    @Test(.enabled(if: Snapshot.enabled)) func sample() async throws {
        let model = Fixtures.model(weather: .sample)
        try await render(SpotPage(app: model, spot: mesaArch, initialDay: nil), model: model, state: "sample")
    }

    @Test(.enabled(if: Snapshot.enabled)) func windowExpanded() async throws {
        let model = Fixtures.model(weather: .sample)
        let page = SpotModel(app: model, spot: mesaArch, explainer: NeverExplainer())
        await page.start()
        page.toggleDayExpanded(page.today)
        page.toggleExpanded(page.selectedWindow ?? .goldenEvening)
        try await render(SpotPage(model: page), model: model, state: "window-expanded")
    }

    /// The outlook with tomorrow open: its windows as rows, one with its reasons.
    @Test(.enabled(if: Snapshot.enabled)) func outlookDayOpen() async throws {
        let model = Fixtures.model(weather: .sample)
        let page = SpotModel(app: model, spot: mesaArch, explainer: NeverExplainer())
        await page.start()
        page.toggleDayExpanded(page.today.adding(days: 1))
        page.toggleExpanded(page.selectedWindow ?? .goldenEvening)
        try await render(SpotPage(model: page), model: model, state: "outlook-open")
    }

    /// The outlook with today open, with the layout grid and lane guides on.
    @Test(.enabled(if: Snapshot.enabled)) func layoutGrid() async throws {
        let model = Fixtures.model(weather: .sample)
        let page = SpotModel(app: model, spot: mesaArch, explainer: NeverExplainer())
        await page.start()
        page.toggleDayExpanded(page.today)
        let view = NavigationStack { SpotPage(model: page) }.environment(\.showsLayoutGrid, true)
        try await Snapshot.render(Fixtures.host(view, model: model), screen: "spot", state: "layout-grid",
                                  sizes: [Snapshot.Size(name: "1280x1400", width: 1280, height: 1400)], settle: .seconds(1))
    }

    @Test(.enabled(if: Snapshot.enabled)) func weatherOffline() async throws {
        let model = Fixtures.model(weather: .notEnabled)
        try await render(SpotPage(app: model, spot: mesaArch, initialDay: nil), model: model, state: "weather-offline")
    }

    @Test(.enabled(if: Snapshot.enabled)) func failed() async throws {
        let model = Fixtures.model(weather: .failed)
        try await render(SpotPage(app: model, spot: mesaArch, initialDay: nil), model: model, state: "failed")
    }

    @Test(.enabled(if: Snapshot.enabled)) func polar() async throws {
        let model = Fixtures.model(weather: .sample)
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let december = LocalDay(year: 2026, month: 12, day: 10).at(hour: 11, in: oslo)
        model.now = { december }
        model.forecasts.replaceProvider(CachedWeatherService(wrapping: SampleWeatherService(now: { december })))
        let tromso = Spot(id: UUID().uuidString, name: "Tromsø harbour", locality: "Tromsø, Norway",
                          coordinate: Coordinate(latitude: 69.65, longitude: 18.96), timeZoneIdentifier: "Europe/Oslo",
                          category: .coast, bestLight: [.night], origin: .appleMaps)
        try await render(SpotPage(app: model, spot: tromso, initialDay: nil), model: model, state: "polar")
    }

    @Test(.enabled(if: Snapshot.enabled)) func userSpot() async throws {
        let model = Fixtures.model(weather: .sample)
        let record = model.store.createUserSpot(name: "Cottonwood bend", locality: "Near Moab, UT",
                                                coordinate: Coordinate(latitude: 38.62, longitude: -109.57),
                                                timeZoneIdentifier: "America/Denver", category: .desert, bestLight: [.sunset],
                                                notes: "Pull-off 200 m past the cattle guard. Soft light on the cliffs after the sun drops.",
                                                walkInMinutes: 12)
        try await render(SpotPage(app: model, spot: record.spot, initialDay: nil), model: model, state: "user")
    }

    /// FIXTURE ONLY: OpenWeather-shaped data (total cloud only, with the first choice marked as failed) built from the sample
    /// generator. It exercises the source line, the fallback wording, the notes and the Windy section, not real OpenWeather output.
    @Test(.enabled(if: Snapshot.enabled)) func openWeatherFallback() async throws {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false)
        model.forecasts.replaceProvider(FixtureProvider(shape: .openWeather))
        let page = SpotModel(app: model, spot: mesaArch, explainer: NeverExplainer())
        await page.start()
        page.toggleDayExpanded(page.today)
        page.toggleExpanded(page.selectedWindow ?? .goldenEvening)
        try await render(SpotPage(model: page), model: model, state: "openweather-fallback")
    }

    /// FIXTURE ONLY: Windy GFS-shaped data (cloud by height, rain amount without a chance, no visibility, three-hourly steps).
    @Test(.enabled(if: Snapshot.enabled)) func windyGFS() async throws {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false)
        model.forecasts.replaceProvider(FixtureProvider(shape: .windy))
        let page = SpotModel(app: model, spot: mesaArch, explainer: NeverExplainer())
        await page.start()
        page.toggleDayExpanded(page.today)
        page.toggleExpanded(page.selectedWindow ?? .goldenEvening)
        try await render(SpotPage(model: page), model: model, state: "windy-gfs")
    }

    @Test @MainActor func fixtureForecastsCarryTheirSource() async throws {
        let open = try await FixtureProvider(shape: .openWeather).forecast(for: mesaArch.coordinate)
        #expect(open.source == .openWeather && open.fallbackFrom == [.appleWeather] && open.hours.allSatisfy { !$0.hasLayers })
        let windy = try await FixtureProvider(shape: .windy).forecast(for: mesaArch.coordinate)
        #expect(windy.source == .windy && windy.model == "GFS" && windy.hours.allSatisfy { $0.precipitationChance == nil })
    }

    @Test func shareLinkCarriesCoordinates() {
        let url = SpotHeaderView.shareURL(for: mesaArch)
        #expect(url.absoluteString.contains("ll="))
        #expect(url.host() == "maps.apple.com")
    }
}

/// An explainer that is available but never answers; the snapshot only needs the button to exist.
private struct NeverExplainer: LightExplaining {
    func isAvailable() -> Bool { true }
    func explain(spotName: String, window: LightWindow, intentName: String) async throws -> String { throw CancellationError() }
}

/// FIXTURE ONLY. Reshapes the sample generator's forecast to look like a provider's, for snapshots.
struct FixtureProvider: WeatherProviding {
    enum Shape { case openWeather, windy }
    let shape: Shape

    var source: ForecastSource { shape == .openWeather ? .openWeather : .windy }
    func attribution() async -> WeatherAttributionInfo? { nil }

    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        var forecast = try await SampleWeatherService(now: { Fixtures.now }).forecast(for: coordinate)
        forecast.source = source
        switch shape {
        case .openWeather:
            forecast.fallbackFrom = [.appleWeather]
            forecast.hours = forecast.hours.map { h in
                var h = h
                h.cloudLow = nil; h.cloudMid = nil; h.cloudHigh = nil
                return h
            }
        case .windy:
            forecast.model = "GFS"
            forecast.hours = forecast.hours.map { h in
                var h = h
                h.precipitationMm = (h.precipitationChance ?? 0) * 1.5
                h.precipitationChance = nil
                h.visibilityMeters = nil
                h.resolution = .interpolated
                return h
            }
        }
        return forecast
    }
}
