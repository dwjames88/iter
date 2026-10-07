import SwiftUI
import Testing
import IterCore
import IterServices
import IterFeatures
@testable import Iter

/// A scout that only reports an availability.
private struct AvailabilityScout: Scouting {
    let state: ScoutAvailability
    func availability() -> ScoutAvailability { state }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { [] }
}

@MainActor
private final class StatusLocation: UserLocationProviding {
    var authorization: LocationAuthorization
    var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
    init(_ status: LocationAuthorization) { authorization = status }
    func requestAuthorization() {}
    func requestFix() async -> Coordinate? { nil }
}

@MainActor
@Suite(.serialized) struct OnboardingSnapshotTests {
    private static let size = Snapshot.Size(name: "560x480", width: 560, height: 480)
    private static let key = "0123456789abcdef0123456789abcdef"

    private func model(at step: OnboardingStep, location: LocationAuthorization = .notDetermined,
                       scout: ScoutAvailability? = .available) -> AppModel {
        let model = Fixtures.model(weather: .notEnabled, seedTrip: false, saved: [],
                                   location: UserLocationModel(provider: StatusLocation(location)),
                                   scout: scout.map { AvailabilityScout(state: $0) })
        model.onboarding.present(at: step)
        return model
    }

    private func render(_ name: String, _ model: AppModel, keyCheck: OpenWeatherKeyCheck = OpenWeatherKeyCheck()) async throws {
        try await Snapshot.render(Fixtures.host(OnboardingView(keyCheck: keyCheck), model: model),
                                  screen: "onboarding", state: name, sizes: [Self.size], chrome: .bare)
    }

    private func check(draft: String, probe: @escaping OpenWeatherKeyCheck.Probe) -> OpenWeatherKeyCheck {
        let check = OpenWeatherKeyCheck(debounce: .zero, probe: probe)
        check.update(draft: draft)
        return check
    }

    @Test(.enabled(if: Snapshot.enabled)) func welcome() async throws {
        try await render("welcome", model(at: .welcome))
    }

    @Test(.enabled(if: Snapshot.enabled)) func location() async throws {
        try await render("location", model(at: .location))
        try await render("location-on", model(at: .location, location: .authorized))
        try await render("location-off", model(at: .location, location: .denied))
    }

    @Test(.enabled(if: Snapshot.enabled)) func weatherStates() async throws {
        let m = model(at: .weather)
        try await render("weather-empty", m)

        let pending = check(draft: Self.key) { _ in try await Task.sleep(for: .seconds(60)) }
        try await render("weather-checking", m, keyCheck: pending)
        pending.update(draft: "")

        let working = check(draft: Self.key) { _ in }
        await working.settled()
        try await render("weather-working", m, keyCheck: working)

        let rejected = check(draft: Self.key) { _ in throw WeatherError.keyRejected(.openWeather) }
        await rejected.settled()
        try await render("weather-rejected", m, keyCheck: rejected)

        let invalid = check(draft: "abc123") { _ in }
        try await render("weather-invalid", m, keyCheck: invalid)
    }

    @Test(.enabled(if: Snapshot.enabled)) func intelligence() async throws {
        try await render("intelligence", model(at: .intelligence))
        try await render("intelligence-off", model(at: .intelligence, scout: .appleIntelligenceNotEnabled))
    }

    @Test(.enabled(if: Snapshot.enabled)) func done() async throws {
        try await render("done", model(at: .done, location: .authorized))
    }

    @Test func askStateWording() {
        #expect(OnboardingView.askState(nil).text == "Not available in this build")
        #expect(OnboardingView.askState(.appleIntelligenceNotEnabled).offersSettings)
        #expect(!OnboardingView.askState(.available).offersSettings)
        #expect(OnboardingView.askState(.available).available)
    }
}
