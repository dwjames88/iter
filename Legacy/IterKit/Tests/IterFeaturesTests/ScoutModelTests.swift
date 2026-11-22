import Foundation
import Testing
import IterCore
import IterServices
@testable import IterFeatures

@MainActor
@Suite(.serialized) struct ScoutModelTests {
    private func settle() async { for _ in 0..<20 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(30)) }

    @Test func emptyRequestDoesNotRun() {
        let fake = FakeScout()
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake))
        model.request = "   "
        #expect(!model.canRun)
        model.run()
        #expect(model.state == .idle)
        #expect(fake.started == 0)
    }

    @Test func runReportsStagesThenResults() async {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        fake.stages = [.understanding, .searching("Moab"), .writing]
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake))
        model.request = "  arches at sunrise "
        model.run()
        guard case .running(_, let started) = model.state else { Issue.record("not running: \(model.state)"); return }
        #expect(started == scoutTestNow)
        await settle()
        #expect(model.state == .results([scoutSuggestion("mesa-arch")]))
        #expect(model.submittedRequest == "arches at sunrise")
    }

    @Test func stageUpdatesWhileRunning() async {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        fake.stages = [.searching("Portland, Oregon")]
        fake.holdUntilReleased()
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake))
        model.request = "fog"
        model.run()
        await settle()
        guard case .running(let stage, _) = model.state else { Issue.record("not running"); return }
        #expect(stage == .searching("Portland, Oregon"))
        #expect(model.isRunning && !model.canRun)
        fake.release()
        await settle()
        #expect(!model.isRunning)
    }

    @Test func cancelStopsTheTaskAndKeepsTheText() async {
        let fake = FakeScout(outcome: .success([scoutSuggestion("mesa-arch")]))
        fake.holdUntilReleased()
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake))
        model.request = "waterfalls"
        model.run()
        await settle()
        model.cancel()
        #expect(model.state == .idle)
        await settle()
        #expect(fake.cancelledCount == 1)
        // The cancelled run's late answer must not bring results back.
        #expect(model.state == .idle)
        #expect(model.request == "waterfalls")
    }

    @Test func eachErrorMapsToItsOwnFailure() async {
        let cases: [(ScoutError, ScoutFailure)] = [
            (.noResults, .noResults), (.guardrail, .guardrail), (.contextTooLong, .tooLong),
            (.unsupportedLanguage, .unsupportedLanguage), (.failed("x"), .failed("x")),
        ]
        for (error, expected) in cases {
            let fake = FakeScout(outcome: .failure(error))
            let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake))
            model.request = "anything"
            model.run()
            await settle()
            #expect(model.state == .failed(expected))
        }
    }

    @Test func emptyResultsAreNoResults() async {
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: FakeScout(outcome: .success([]))))
        model.request = "x"
        model.run()
        await settle()
        #expect(model.state == .failed(.noResults))
    }

    @Test func unavailableScoutNeverStarts() {
        let fake = FakeScout(availability: .appleIntelligenceNotEnabled)
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: fake))
        model.request = "x"
        model.run()
        #expect(model.state == .failed(.unavailable(.appleIntelligenceNotEnabled)))
        #expect(fake.started == 0)
        #expect(model.availability == .appleIntelligenceNotEnabled)
    }

    @Test func missingScoutIsUnavailable() {
        let model = ScoutModel(app: scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: nil))
        if case .unavailable = model.availability {} else { Issue.record("expected unavailable") }
        model.request = "x"
        model.run()
        if case .failed(.unavailable) = model.state {} else { Issue.record("expected failure") }
    }

    @Test func noForecastGivesAnUnscoredNextEventAndAStatus() async {
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: nil)
        let model = ScoutModel(app: app)
        let s = scoutSuggestion("mesa-arch")
        _ = await app.forecasts.load(s.spot.coordinate)
        guard case .window(_, let window) = model.light(for: s) else { Issue.record("expected a window"); return }
        #expect(window.score == nil)
        #expect(app.weatherStatus == .failed(.weatherServiceNotEnabled, lastUpdate: nil))
    }

    @Test func offlineIsAStatusNotARowState() async {
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .offline(.appleWeather)), scout: nil)
        let s = scoutSuggestion("tunnel-view")
        _ = await app.forecasts.load(s.spot.coordinate)
        #expect(app.weatherStatus == .offline(.appleWeather, lastUpdate: nil))
    }

    @Test func forecastNotYetLoadedIsLoadingNotAScore() {
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: nil)
        let model = ScoutModel(app: app)
        #expect(model.light(for: scoutSuggestion("mesa-arch")) == .loading)
    }

    @Test func sampleForecastScoresTheNextEvent() async {
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: nil)
        app.setSampleData(true)
        let model = ScoutModel(app: app)
        let s = scoutSuggestion("mesa-arch", window: .goldenMorning)
        _ = await app.forecasts.load(s.spot.coordinate)
        guard case .window(_, let window) = model.light(for: s) else { Issue.record("expected a window"); return }
        // 10:00 in Denver: the next event is this evening's sunset, whatever light the suggestion named.
        #expect(window.kind == .goldenEvening)
        #expect(window.score != nil)
    }

    @Test func sessionIsSharedPerApp() {
        let app = scoutAppModel(weather: ScoutFailingWeather(error: .notEnabled), scout: nil)
        #expect(ScoutModel.session(for: app) === ScoutModel.session(for: app))
    }
}
