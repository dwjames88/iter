import Foundation
import Synchronization
import Testing
import IterCore
import IterServices
@testable import IterFeatures

private func scratch() -> UserDefaults { UserDefaults(suiteName: "iter.tests.onboarding." + UUID().uuidString)! }

private let goodKey = "0123456789abcdef0123456789ABCDEF"
private let otherKey = "fedcba9876543210fedcba9876543210"

/// Records every key the probe is asked about and answers from a script.
private final class FakeProbe: Sendable {
    private let calls = Mutex<[String]>([])
    private let outcome: @Sendable (String) async throws -> Void
    init(_ outcome: @escaping @Sendable (String) async throws -> Void = { _ in }) { self.outcome = outcome }
    var keys: [String] { calls.withLock { $0 } }
    var probe: OpenWeatherKeyCheck.Probe {
        { [self] key in
            calls.withLock { $0.append(key) }
            try await outcome(key)
        }
    }
}

private struct RejectingTransport: HTTPTransport {
    var status: Int
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(#"{"cod":401,"message":"Invalid API key"}"#.utf8),
         HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

@MainActor
@Suite struct OnboardingModelTests {
    @Test func showsOnceThenStaysAway() {
        let defaults = scratch()
        let first = OnboardingModel(defaults: defaults)
        #expect(!first.isPresented)
        first.presentIfNeeded()
        #expect(first.isPresented && first.step == .welcome)
        first.skip()
        #expect(!first.isPresented)
        let second = OnboardingModel(defaults: defaults)
        second.presentIfNeeded()
        #expect(!second.isPresented)
        #expect(defaults.integer(forKey: OnboardingModel.completedVersionKey) == OnboardingModel.currentVersion)
    }

    @Test func finishAlsoCompletes() {
        let defaults = scratch()
        let model = OnboardingModel(defaults: defaults)
        model.present(at: .done)
        model.finish()
        #expect(!model.isPresented)
        let again = OnboardingModel(defaults: defaults)
        again.presentIfNeeded()
        #expect(!again.isPresented)
    }

    @Test func aNewerGuideShowsAgain() {
        let defaults = scratch()
        let old = OnboardingModel(defaults: defaults, currentVersion: 1)
        old.presentIfNeeded(); old.skip()
        let newer = OnboardingModel(defaults: defaults, currentVersion: 2)
        newer.presentIfNeeded()
        #expect(newer.isPresented)
    }

    @Test func presentAtReopensAfterCompletion() {
        let model = OnboardingModel(defaults: scratch())
        model.presentIfNeeded(); model.finish()
        model.present(at: .weather)
        #expect(model.isPresented && model.step == .weather)
        model.skip()
        model.present()
        #expect(model.step == .welcome)
    }

    @Test func dismissedBySystemCountsAsSeen() {
        let defaults = scratch()
        let model = OnboardingModel(defaults: defaults)
        model.presentIfNeeded()
        model.dismissed()
        #expect(!model.isPresented)
        #expect(OnboardingModel(defaults: defaults).isCompleted)
    }

    @Test func nextAndBackStayInBounds() {
        let model = OnboardingModel(defaults: scratch())
        model.present()
        model.back()
        #expect(model.step == .welcome)
        for expected in OnboardingStep.allCases.dropFirst() {
            model.next()
            #expect(model.step == expected)
        }
        #expect(model.isLast)
        model.back()
        #expect(model.step == .intelligence)
        model.present(at: .done)
        model.next()
        #expect(!model.isPresented)
        #expect(model.isCompleted)
        #expect(model.position.count == 5)
    }
}

@MainActor
@Suite struct OpenWeatherKeyCheckTests {
    @Test func formatIsThirtyTwoHexCharacters() {
        #expect(OpenWeatherKeyCheck.isWellFormed(goodKey))
        #expect(!OpenWeatherKeyCheck.isWellFormed(String(goodKey.dropLast())))
        #expect(!OpenWeatherKeyCheck.isWellFormed(goodKey + "0"))
        #expect(!OpenWeatherKeyCheck.isWellFormed(String(goodKey.dropLast()) + "g"))
    }

    @Test func invalidFormatMakesNoCall() async {
        let fake = FakeProbe()
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: fake.probe)
        #expect(check.state == .idle)
        check.update(draft: "not a key")
        #expect(check.state == .invalidFormat)
        await check.settled()
        check.update(draft: "")
        #expect(check.state == .idle)
        #expect(fake.keys.isEmpty)
    }

    @Test func checkingThenWorkingTrimsTheDraft() async {
        let fake = FakeProbe()
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: fake.probe)
        check.update(draft: "  \(goodKey)\n")
        #expect(check.state == .checking)
        #expect(check.draft == goodKey)
        await check.settled()
        #expect(check.state == .working)
        #expect(fake.keys == [goodKey])
        #expect(check.canSave)
    }

    @Test func rejectedKeyFailsWithTheExactError() async {
        let fake = FakeProbe { _ in throw WeatherError.keyRejected(.openWeather) }
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: fake.probe)
        check.update(draft: goodKey)
        await check.settled()
        #expect(check.state == .failed(.keyRejected(.openWeather)))
        #expect(check.isRejected && check.canSave)
    }

    @Test func offlineFailsWithOffline() async {
        let fake = FakeProbe { _ in throw WeatherError.offline(.openWeather) }
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: fake.probe)
        check.update(draft: goodKey)
        await check.settled()
        #expect(check.state == .failed(.offline(.openWeather)))
        #expect(!check.canSave)
    }

    @Test func aNewDraftCancelsTheOldCheck() async {
        let fake = FakeProbe()
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(200), probe: fake.probe)
        check.update(draft: goodKey)
        check.update(draft: otherKey)
        await check.settled()
        #expect(check.state == .working)
        #expect(fake.keys == [otherKey])
        // Going back to a malformed draft cancels the pending call too.
        check.update(draft: goodKey)
        check.update(draft: "oops")
        await check.settled()
        #expect(check.state == .invalidFormat)
        #expect(fake.keys == [otherKey])
    }

    @Test func aLateAnswerForAReplacedDraftIsIgnored() async {
        let fake = FakeProbe { key in
            if key == goodKey { try await Task.sleep(for: .milliseconds(300)); throw WeatherError.keyRejected(.openWeather) }
        }
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: fake.probe)
        check.update(draft: goodKey)
        try? await Task.sleep(for: .milliseconds(50))
        check.update(draft: otherKey)
        await check.settled()
        try? await Task.sleep(for: .milliseconds(400))
        #expect(check.state == .working)
    }

    @Test func liveProbeMapsHTTPStatusWithoutTouchingTheSavedKey() async {
        let probe = OpenWeatherKeyCheck.liveProbe(transport: RejectingTransport(status: 401))
        await #expect(throws: WeatherError.keyRejected(.openWeather)) { try await probe(goodKey) }
        let ok = OpenWeatherKeyCheck.liveProbe(transport: RejectingTransport(status: 429))
        await #expect(throws: WeatherError.overDailyLimit(.openWeather)) { try await ok(goodKey) }
    }

    @Test func saveStoresTheKeyAndSelectsOpenWeather() async throws {
        let keys = InMemoryAPIKeyStore()
        let setup = WeatherSetup(keyStore: keys, cacheDirectory: nil, defaults: scratch(),
                                 transport: RejectingTransport(status: 401),
                                 environment: { [:] }, launchArgument: { _ in nil })
        #expect(setup.settings.primary == .appleWeather)
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: FakeProbe().probe)
        #expect(!check.hasSavedKey(in: setup))
        check.update(draft: goodKey)
        await check.settled()
        try check.save(into: setup)
        await setup.settled()
        #expect(keys.key(for: .openWeather) == goodKey)
        #expect(setup.settings.primary == .openWeather)
        #expect(check.hasSavedKey(in: setup))
    }

    @Test func savingAMalformedDraftDoesNothing() throws {
        let keys = InMemoryAPIKeyStore()
        let setup = WeatherSetup(keyStore: keys, cacheDirectory: nil, defaults: scratch(),
                                 environment: { [:] }, launchArgument: { _ in nil })
        let check = OpenWeatherKeyCheck(debounce: .milliseconds(1), probe: FakeProbe().probe)
        check.update(draft: "short")
        try check.save(into: setup)
        #expect(keys.key(for: .openWeather) == nil)
        #expect(setup.settings.primary == .appleWeather)
    }
}
