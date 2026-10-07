import Testing
import Foundation
import SwiftUI
import UIKit
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

// MARK: - A minimal in-memory model

private struct NoWeather: WeatherProviding {
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw WeatherError.notEnabled }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct NoSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct NoGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Moab, UT", coordinate: coordinate,
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct EstimateDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

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

/// An isolated defaults suite that goes away with the test.
@MainActor
private final class Suite {
    let name = "IterOnboardingIOSTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: name)! }
    deinit { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }

    func model(location: LocationAuthorization = .notDetermined, scout: ScoutAvailability? = .available) -> AppModel {
        let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        return AppModel(store: store, weather: NoWeather(), search: NoSearch(), geocoder: NoGeocoder(), drives: EstimateDrives(),
                        scout: scout.map { AvailabilityScout(state: $0) },
                        location: UserLocationModel(provider: StatusLocation(location)), defaults: defaults)
    }
}

private let goodKey = "0123456789abcdef0123456789abcdef"

/// A probe that counts its calls.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    func bump() { lock.lock(); n += 1; lock.unlock() }
}

// MARK: - Shown once, re-openable

@MainActor @Suite struct OnboardingPresentationIOSTests {
    @Test func freshDefaultsPresentOnFirstAppear() {
        let suite = Suite()
        let onboarding = suite.model().onboarding
        #expect(!onboarding.isPresented)
        onboarding.presentIfNeeded()
        #expect(onboarding.isPresented)
        #expect(onboarding.step == .welcome)
    }

    @Test func finishingMeansItIsNotShownAgain() {
        let suite = Suite()
        let first = suite.model().onboarding
        first.presentIfNeeded()
        first.finish()
        #expect(!first.isPresented)
        first.presentIfNeeded()
        #expect(!first.isPresented)
        // A new launch on the same defaults.
        let second = suite.model().onboarding
        second.presentIfNeeded()
        #expect(!second.isPresented)
    }

    @Test func skippingMeansItIsNotShownAgain() {
        let suite = Suite()
        let first = suite.model().onboarding
        first.presentIfNeeded()
        first.skip()
        let second = suite.model().onboarding
        second.presentIfNeeded()
        #expect(!second.isPresented)
    }

    @Test func aSystemDismissalCountsAsSeen() {
        let suite = Suite()
        let first = suite.model().onboarding
        first.presentIfNeeded()
        first.dismissed()   // the sheet's onDismiss
        #expect(!first.isPresented)
        let second = suite.model().onboarding
        second.presentIfNeeded()
        #expect(!second.isPresented)
    }

    @Test func settingsActionReopensAtWelcomeAfterCompletion() async {
        let suite = Suite()
        let model = suite.model()
        model.onboarding.presentIfNeeded()
        model.onboarding.next()
        model.onboarding.finish()
        #expect(model.onboarding.isCompleted)
        let shell = ShellState()
        await shell.showWelcome(model.onboarding)
        #expect(model.onboarding.isPresented)
        #expect(model.onboarding.step == .welcome)
    }

    @Test func settingsActionOnPadClosesTheSettingsSheetFirst() async {
        let suite = Suite()
        let model = suite.model()
        let shell = ShellState()
        shell.usesTabs = false
        shell.showSettings()
        #expect(shell.showsSettingsSheet)
        await shell.showWelcome(model.onboarding)
        #expect(!shell.showsSettingsSheet)
        #expect(model.onboarding.isPresented)
    }

    @Test func weatherBannerOpensAtWeather() {
        let suite = Suite()
        let model = suite.model()
        model.onboarding.finish()
        model.onboarding.present(at: .weather)   // what WeatherStatusBanner's button calls
        #expect(model.onboarding.isPresented)
        #expect(model.onboarding.step == .weather)
    }
}

// MARK: - Key validation

@MainActor @Suite struct OnboardingKeyIOSTests {
    @Test func invalidFormatMakesNoCall() async {
        let calls = Calls()
        let check = OpenWeatherKeyCheck(debounce: .zero) { _ in calls.bump() }
        check.update(draft: "abc123")
        await check.settled()
        #expect(check.state == .invalidFormat)
        #expect(calls.count == 0)
        #expect(!check.canSave)
    }

    @Test func aWorkingKey() async {
        let calls = Calls()
        let check = OpenWeatherKeyCheck(debounce: .zero) { key in #expect(key == goodKey); calls.bump() }
        check.update(draft: "  \(goodKey)\n")
        #expect(check.state == .checking)
        await check.settled()
        #expect(check.state == .working)
        #expect(check.canSave)
        #expect(calls.count == 1)
    }

    @Test func aRejectedKey() async {
        let check = OpenWeatherKeyCheck(debounce: .zero) { _ in throw WeatherError.keyRejected(.openWeather) }
        check.update(draft: goodKey)
        await check.settled()
        #expect(check.state == .failed(.keyRejected(.openWeather)))
        #expect(check.isRejected)
        #expect(check.canSave)   // "Save Key Anyway": a new key may not be active yet
    }

    @Test func offline() async {
        let check = OpenWeatherKeyCheck(debounce: .zero) { _ in throw WeatherError.offline(.openWeather) }
        check.update(draft: goodKey)
        await check.settled()
        #expect(check.state == .failed(.offline(.openWeather)))
        #expect(!check.canSave)
    }

    @Test func clearingTheFieldReturnsToIdle() async {
        let check = OpenWeatherKeyCheck(debounce: .zero) { _ in }
        check.update(draft: goodKey)
        await check.settled()
        check.update(draft: "")
        #expect(check.state == .idle)
    }
}

private let snapshotsEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

// MARK: - Snapshots (iPhone 17 Pro, 402 x 874 pt at 3x), offscreen

/// Renders `OnboardingView` into a `UIWindow` that is never made key, and draws it into a PNG. Only runs with
/// `ITER_SNAPSHOTS=1` (scripts/snapshots-ios.sh); files go to `ITER_SNAPSHOT_DIR`.
@MainActor @Suite(.serialized) struct OnboardingIOSSnapshotTests {
    private static let size = CGSize(width: 402, height: 874)

    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private func render(_ name: String, step: OnboardingStep, location: LocationAuthorization = .notDetermined,
                        keyCheck: OpenWeatherKeyCheck = OpenWeatherKeyCheck()) async throws {
        let suite = Suite()
        let model = suite.model(location: location)
        model.onboarding.present(at: step)
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let view = OnboardingView(keyCheck: keyCheck)
                .environment(model)
                .modelContainer(model.store.container)
                .environment(\.colorScheme, style == .dark ? .dark : .light)
            let host = UIHostingController(rootView: view)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: Self.size)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false   // visible to the Simulator only; never made key
            try await Task.sleep(for: .milliseconds(500))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: Self.size, format: format).image { _ in
                host.view.drawHierarchy(in: CGRect(origin: .zero, size: Self.size), afterScreenUpdates: true)
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-onboarding-\(name)-\(scheme).png"))
        }
    }

    private func check(draft: String, probe: @escaping OpenWeatherKeyCheck.Probe) -> OpenWeatherKeyCheck {
        let check = OpenWeatherKeyCheck(debounce: .zero, probe: probe)
        check.update(draft: draft)
        return check
    }

    @Test(.enabled(if: snapshotsEnabled)) func welcome() async throws {
        try await render("welcome", step: .welcome)
    }

    @Test(.enabled(if: snapshotsEnabled)) func location() async throws {
        try await render("location", step: .location)
    }

    @Test(.enabled(if: snapshotsEnabled)) func weather() async throws {
        try await render("weather-empty", step: .weather)
        let working = check(draft: goodKey) { _ in }
        await working.settled()
        try await render("weather-working", step: .weather, keyCheck: working)
        let rejected = check(draft: goodKey) { _ in throw WeatherError.keyRejected(.openWeather) }
        await rejected.settled()
        try await render("weather-rejected", step: .weather, keyCheck: rejected)
    }

    @Test(.enabled(if: snapshotsEnabled)) func intelligence() async throws {
        try await render("intelligence", step: .intelligence)
    }

    @Test(.enabled(if: snapshotsEnabled)) func done() async throws {
        try await render("done", step: .done, location: .authorized)
    }
}
