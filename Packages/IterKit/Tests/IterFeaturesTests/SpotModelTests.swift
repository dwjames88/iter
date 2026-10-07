import Foundation
import Testing
import CoreGraphics
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let denver = TimeZone(identifier: "America/Denver")!
/// Tue 6 Oct 2026, 10:00 in Denver.
private let fixedNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: denver)

private struct FailingWeather: WeatherProviding {
    let error: WeatherError
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw error }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct NoSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct NoGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw WeatherError.notEnabled }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct NoDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

/// A fake explainer the test releases by hand.
private actor FakeExplainer: LightExplaining {
    private let available: Bool
    private var continuation: CheckedContinuation<String, any Error>?
    private(set) var calls = 0

    init(available: Bool = true) { self.available = available }

    nonisolated func isAvailable() -> Bool { available }

    func explain(spotName: String, window: LightWindow, intentName: String) async throws -> String {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ text: String) { continuation?.resume(returning: text); continuation = nil }
    func fail(_ error: LightExplainerError) { continuation?.resume(throwing: error); continuation = nil }
}

@MainActor
private func makeApp(_ weather: Weather = .sample, now: Date = fixedNow) throws -> AppModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let provider: any WeatherProviding
    switch weather {
    case .sample: provider = SampleWeatherService(now: { now })
    case .notEnabled: provider = FailingWeather(error: .notEnabled)
    case .failed: provider = FailingWeather(error: .failed("offline"))
    case .eightDays: provider = EightDayWeather(now: now)
    }
    return AppModel(store: store, weather: provider, search: NoSearch(), geocoder: NoGeocoder(), drives: NoDrives(), scout: nil,
                    defaults: UserDefaults(suiteName: "SpotModelTests-\(UUID().uuidString)")!, now: { now })
}

private enum Weather { case sample, notEnabled, failed, eightDays }

/// Like OpenWeather: hours from the start of the local day, for eight whole days (the later ones from daily summaries).
private struct EightDayWeather: WeatherProviding {
    var now: Date
    var source: ForecastSource { .openWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        let zone = CuratedSpots.all.first { $0.coordinate == coordinate }?.timeZone ?? denver
        let start = LocalDay(now, in: zone).start(in: zone)
        let hours = (0..<(8 * 24)).map { i in
            HourlyConditions(date: start.addingTimeInterval(Double(i) * 3600), cloudCover: 0.35, precipitationChance: 0.05, visibilityMeters: 10_000,
                             windSpeedKph: 5, temperatureC: 12, humidity: 0.5, symbolName: "sun.max", condition: "clear",
                             resolution: i < 48 ? .hourly : .dailySummary)
        }
        return Forecast(coordinate: coordinate, hours: hours, days: [], fetchedAt: now, source: .openWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private var mesaArch: Spot { CuratedSpots.spot(id: "mesa-arch")! }

private let tromso = Spot(id: "tromso", name: "Tromsø harbour", locality: "Tromsø, Norway",
                          coordinate: Coordinate(latitude: 69.65, longitude: 18.96), timeZoneIdentifier: "Europe/Oslo",
                          category: .coast, bestLight: [.night], origin: .user)

@MainActor
@Suite struct SpotModelTests {
    @Test func opensOnTheBestDayForTheIntentOnceTheForecastLoads() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        #expect(model.day == model.today)            // forecast not loaded yet
        #expect(model.best == nil)
        await model.start()
        let best = try #require(model.best)
        #expect(model.day == best.day)
        #expect(model.selectedWindow == best.window.kind)
        #expect(model.intent == mesaArch.defaultIntent)
        #expect(best.window.score != nil)
    }

    @Test func bestIsTheHighestScoreOverTenDaysForTheIntent() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        let best = try #require(model.best)
        let scores = model.outlook.compactMap { $0.headline(for: model.intent)?.score }
        #expect(best.window.score == scores.max())
        #expect(model.intent.windows.contains(best.window.kind))
    }

    @Test func anInitialDayIsKeptAfterTheForecastLoads() async throws {
        let app = try makeApp()
        let wanted = LocalDay(year: 2026, month: 10, day: 9)
        let model = SpotModel(app: app, spot: mesaArch, initialDay: wanted, explainer: FakeExplainer())
        await model.start()
        #expect(model.day == wanted)
        #expect(model.dayLight.day == wanted)
        #expect(model.selectedWindow != nil)
    }

    @Test func changingDayResetsSelectionScrubAndExplanation() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        let other = model.today.adding(days: 3) == model.day ? model.today.adding(days: 2) : model.today.adding(days: 3)
        model.scrub = model.dayInterval.start.addingTimeInterval(3600)
        model.selectDay(other)
        #expect(model.day == other)
        #expect(model.scrub == nil)
        #expect(model.explanation == .idle)
        #expect(model.expanded.isEmpty)
        #expect(model.dayLight.windows.contains { $0.kind == model.selectedWindow })
    }

    @Test func changingIntentChangesTheHeadlineWindow() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        model.selectDay(model.today.adding(days: 2))
        model.selectIntent(.sunrise)
        #expect(model.headline(on: model.day)?.kind == .goldenMorning)
        model.selectIntent(.night)
        #expect(model.headline(on: model.day)?.kind == .night)
        #expect(model.selectedWindow == .night)
        // A night window never answers a daytime intent.
        model.selectIntent(.sunset)
        #expect(model.best.map { $0.window.kind == .goldenEvening } ?? true)
    }

    @Test func strippedDaysIncludeADayBeyondTheOutlook() async throws {
        let app = try makeApp()
        let far = LocalDay(year: 2026, month: 11, day: 20)
        let model = SpotModel(app: app, spot: mesaArch, initialDay: far, explainer: FakeExplainer())
        await model.start()
        #expect(model.outlook.count == model.outlookDayCount)
        #expect(model.stripDays.count == model.outlookDayCount + 1)
        #expect(model.stripDays.last?.day == far)
        // Far beyond the forecast: scored by persistence, at the lowest confidence.
        let headline = try #require(model.headline(on: far))
        let score = try #require(headline.assessment.lightScore)
        #expect(score.confidence == .low)
        #expect(score.notes.contains(.persistence))
    }

    @Test func outlookIsClampedToTheDaysTheForecastCovers() async throws {
        let app = try makeApp(.eightDays)
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        // Before the forecast arrives there is nothing to clamp to.
        #expect(model.outlookDayCount == SpotModel.outlookDays)
        await model.start()
        #expect(model.outlookDayCount == 8)
        #expect(model.outlook.count == 8)
        #expect(model.outlook.allSatisfy { $0.windows.allSatisfy { $0.score != nil || $0.assessment == .noForecast(.inThePast) } })
        if let best = model.best { #expect(best.day < model.today.adding(days: 8)) }
    }

    @Test func upcomingWindowsAreTodaysRemainingAndTomorrows() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        let list = model.upcomingWindows
        #expect(list.first?.day == model.today)
        #expect(list.last?.day == model.today.adding(days: 1))
        #expect(list.allSatisfy { $0.window.span.end > fixedNow })
    }

    @Test func selectingAWindowIsSharedAndExpandingSelectsIt() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        model.selectWindow(.blueEvening)
        #expect(model.selectedWindow == .blueEvening)
        model.toggleExpanded(.goldenMorning)
        #expect(model.expanded == [.goldenMorning])
        #expect(model.selectedWindow == .goldenMorning)
        model.toggleExpanded(.goldenMorning)
        #expect(model.expanded.isEmpty)
    }

    @Test func markerTimeFollowsScrubThenSelectionAndStaysInsideTheDay() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        let window = try #require(model.selectedLightWindow)
        #expect(model.markerTime == window.span.midpoint)
        let t = model.dayInterval.start.addingTimeInterval(5 * 3600)
        model.scrub = t
        #expect(model.markerTime == t)
        model.scrub = model.dayInterval.end.addingTimeInterval(9999)
        #expect(model.markerTime == model.dayInterval.end)
    }

    @Test func chosenTimePersistsUnderTheTransientScrub() async throws {
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        #expect(!model.hasChosenTime)
        let chosen = model.dayInterval.start.addingTimeInterval(10 * 3600)
        model.setTime(chosen)
        #expect(model.markerTime == chosen)
        #expect(model.chosenTime == chosen)
        #expect(model.hasChosenTime)
        let hover = chosen.addingTimeInterval(3600)
        model.scrub = hover
        #expect(model.markerTime == hover)
        model.scrub = nil
        #expect(model.markerTime == chosen)
        // A drag ends by committing the scrub.
        model.scrub = hover
        model.commitScrub()
        #expect(model.scrub == nil)
        #expect(model.markerTime == hover)
        #expect(model.chosenTime == hover)
    }

    @Test func steppingMovesTheMarkerAndStopsAtTheDayEdges() async throws {
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        let (start, end) = model.dayInterval
        model.setTime(start.addingTimeInterval(12 * 3600))
        model.stepTime(minutes: 15)
        #expect(model.markerTime == start.addingTimeInterval(12 * 3600 + 900))
        model.stepTime(minutes: 60)
        #expect(model.markerTime == start.addingTimeInterval(13 * 3600 + 900))
        model.stepTime(minutes: -60)
        #expect(model.markerTime == start.addingTimeInterval(12 * 3600 + 900))
        model.setTime(end.addingTimeInterval(-600))
        model.stepTime(minutes: 60)
        #expect(model.markerTime == end)
        model.setTime(start.addingTimeInterval(600))
        model.stepTime(minutes: -60)
        #expect(model.markerTime == start)
    }

    @Test func selectingAWindowOrADayClearsTheChosenTime() async throws {
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        model.setTime(model.dayInterval.start.addingTimeInterval(5 * 3600))
        let other = try #require(model.dayLight.windows.first { $0.kind != model.selectedWindow })
        model.selectWindow(other.kind)
        #expect(model.chosenTime == nil)
        #expect(model.markerTime == other.span.midpoint)
        model.setTime(model.dayInterval.start.addingTimeInterval(5 * 3600))
        let otherDay = model.today.adding(days: 3) == model.day ? model.today.adding(days: 2) : model.today.adding(days: 3)
        model.selectDay(otherDay)
        #expect(model.chosenTime == nil)
        #expect(!model.hasChosenTime)
    }

    @Test func roseToModelToRoseRoundTrip() async throws {
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        let sunset = try #require(model.dayLight.sun.sunset)
        let t = sunset.addingTimeInterval(-3600 + 23)
        let pos = model.readout(at: t).sun
        let proj = RoseProjection(center: CGPoint(x: 200, y: 200), radius: 160)
        let original = proj.point(azimuth: pos.azimuth, altitude: pos.altitude)
        let hit = try #require(model.rose.nearestTime(to: original, projection: proj, maxDistance: 24))
        #expect(hit.body == .sun)
        model.setTime(hit.date)
        #expect(abs(model.markerTime.timeIntervalSince(t)) < 60)
        let back = model.readout(at: model.markerTime).sun
        let backPoint = proj.point(azimuth: back.azimuth, altitude: back.altitude)
        #expect(hypot(backPoint.x - original.x, backPoint.y - original.y) < 1)
        #expect(model.rose.dayStart == model.dayInterval.start)
        #expect(model.rose.event(.sunset)?.date == sunset)
        _ = model.moonPhase(at: t)
    }

    @Test func zoomDomainIsFourHoursAroundTheEvent() async throws {
        let app = try makeApp()
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        #expect(model.domain.lowerBound == model.dayInterval.start)
        model.setFocus(.aroundSunset)
        let sunset = try #require(model.dayLight.sun.sunset)
        #expect(model.domain == sunset.addingTimeInterval(-7200)...sunset.addingTimeInterval(7200))
        model.selectDay(model.day.adding(days: 1))
        #expect(model.focus == .fullDay)
    }

    // MARK: No forecast

    @Test func noForecastHasNoScoresButFullGeometry() async throws {
        let app = try makeApp(.notEnabled)
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        #expect(model.forecast == nil)
        #expect(model.unavailableReason == .weatherServiceNotEnabled)
        #expect(model.best == nil)
        #expect(model.hours.isEmpty)
        #expect(model.day == model.today)
        for light in model.outlook {
            #expect(light.windows.count == 5)
            #expect(light.windows.allSatisfy { $0.score == nil })
        }
        #expect(model.nextSunTimes.kind == .normal)
        #expect(model.nextSunTimes.sunrise != nil)
        #expect(model.nextSunTimes.sunset != nil)
        #expect(model.paths.sun.count > 100)
        #expect(!model.canExplain)
    }

    @Test func failedForecastCanBeRetried() async throws {
        let app = try makeApp(.failed)
        let model = SpotModel(app: app, spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        guard case .serviceFailed = model.unavailableReason else { Issue.record("expected serviceFailed"); return }
        model.retry()
        #expect(model.isLoadingForecast)
        await Task.yield()
        for _ in 0..<50 where model.isLoadingForecast { await Task.yield() }
        guard case .serviceFailed = model.unavailableReason else { Issue.record("expected serviceFailed again"); return }
    }

    // MARK: Polar

    @Test func polarNightOffersOnlyTheNoonBlueHour() async throws {
        let now = LocalDay(year: 2026, month: 12, day: 10).at(hour: 10, in: TimeZone(identifier: "Europe/Oslo")!)
        let app = try makeApp(.sample, now: now)
        let model = SpotModel(app: app, spot: tromso, explainer: FakeExplainer())
        await model.start()
        #expect(model.dayLight.sun.kind == .polarNight)
        #expect(model.dayLight.windows.allSatisfy { !$0.kind.isGolden })
        #expect(model.dayLight.windows.contains { $0.kind.isBlue })
        #expect(model.nextSunTimes.kind == .polarNight)
        #expect(model.nextSunTimes.sunrise == nil)
    }

    // MARK: Explanation

    @Test func explanationRunsThroughLoadingToDone() async throws {
        let fake = FakeExplainer()
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: fake)
        await model.start()
        #expect(model.canExplain)
        model.explain(intentName: "Sunset")
        #expect(model.explanation == .loading)
        for _ in 0..<50 where await fake.calls == 0 { await Task.yield() }
        await fake.finish("A calm evening.")
        for _ in 0..<50 where model.explanation == .loading { await Task.yield() }
        #expect(model.explanation == .done("A calm evening."))
    }

    @Test func explanationCanBeCancelledAndALateResultIsDropped() async throws {
        let fake = FakeExplainer()
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: fake)
        await model.start()
        model.explain(intentName: "Sunset")
        for _ in 0..<50 where await fake.calls == 0 { await Task.yield() }
        model.cancelExplanation()
        #expect(model.explanation == .idle)
        await fake.finish("Too late.")
        for _ in 0..<10 { await Task.yield() }
        #expect(model.explanation == .idle)
    }

    @Test func explanationFailuresAreMappedAndSelectionResetsIt() async throws {
        let fake = FakeExplainer()
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: fake)
        await model.start()
        model.explain(intentName: "Sunset")
        for _ in 0..<50 where await fake.calls == 0 { await Task.yield() }
        await fake.fail(.ungroundedNumbers)
        for _ in 0..<50 where model.explanation == .loading { await Task.yield() }
        #expect(model.explanation == .failed(.ungrounded))
        model.selectWindow(model.dayLight.windows.first { $0.kind != model.selectedWindow }?.kind)
        #expect(model.explanation == .idle)
    }

    @Test func explainerUnavailableMeansNoExplainButton() async throws {
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: FakeExplainer(available: false))
        await model.start()
        #expect(!model.explainerAvailable)
        #expect(!model.canExplain)
    }

    @Test func editingTheSpotKeepsThePage() async throws {
        let model = SpotModel(app: try makeApp(), spot: mesaArch, explainer: FakeExplainer())
        await model.start()
        var edited = mesaArch
        edited.name = "Mesa Arch (renamed)"
        model.update(spot: edited)
        #expect(model.spot.name == "Mesa Arch (renamed)")
        #expect(model.selectedWindow != nil)
    }
}
