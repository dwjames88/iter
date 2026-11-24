import Foundation
import Testing
import IterSky
import IterConditions
import IterModel
import IterDiscovery
@testable import IterFeatures

/// Today, Tomorrow and Near You: what each one asks discovery and which day the scores are for. No new scoring.
@MainActor @Suite("Find quick choices")
struct FindQuickChoiceTests {
    private let here = Coordinate(latitude: 38.57, longitude: -109.55)
    private let view = GeoRegion(center: Coordinate(latitude: 37.0, longitude: -111.5), latitudeDelta: 0.4, longitudeDelta: 0.3)

    @Test func todayAndTomorrowSearchTheMapInViewAndDifferOnlyInTheDay() throws {
        let today = try #require(FindQuickChoice.today.plan(mapRegion: view, location: here))
        let tomorrow = try #require(FindQuickChoice.tomorrow.plan(mapRegion: view, location: here))
        #expect(today.region == view && tomorrow.region == view)
        #expect(today.query == tomorrow.query)
        #expect(today.dayOffset == 0 && tomorrow.dayOffset == 1)
    }

    @Test func withNoMapYetTodayFallsBackToAroundYou() throws {
        let plan = try #require(FindQuickChoice.today.plan(mapRegion: nil, location: here))
        #expect(plan.region.center == here)
        #expect(plan.region.latitudeDelta == FindQuickChoice.fallbackSpanDegrees)
        #expect(FindQuickChoice.today.plan(mapRegion: nil, location: nil) == nil)
    }

    @Test func nearYouIsASquareAroundYouWithTheRadiusAsItsHalfSide() throws {
        let plan = try #require(FindQuickChoice.nearYou.plan(mapRegion: view, location: here))
        #expect(plan.region.center == here)
        // 100 miles each way is about 2 x 1.45 degrees of latitude.
        #expect(abs(plan.region.latitudeDelta - 2 * FindQuickChoice.nearYouRadiusMiles / 69) < 1e-9)
        #expect(plan.region.longitudeDelta > plan.region.latitudeDelta)
        #expect(plan.dayOffset == 0)
        #expect(FindQuickChoice.nearYou.plan(mapRegion: view, location: nil) == nil)
    }

    @Test func runningAChoiceSendsThatRegionToDiscoveryAndScoresTheRightDay() async throws {
        let runner = ControlledRunner()
        let fake = FakeFindScores()
        let rig = try Rig(runner: runner, scores: fake)
        rig.model.mapRegion = view
        #expect(rig.model.offersQuickChoices)
        rig.model.runQuickChoice(.tomorrow)
        #expect(runner.requests.count == 1)
        #expect(runner.requests[0].mapRegion == view)
        #expect(rig.model.activeQuickChoice == .tomorrow)
        #expect(rig.model.phase == .discovering)
        #expect(!rig.model.offersQuickChoices)
        // A typed search afterwards is back to today.
        rig.model.text = "waterfalls in Yosemite"
        rig.model.askIter()
        #expect(rig.model.activeQuickChoice == nil)
        #expect(rig.model.scoreDayOffset == 0)
    }

    @Test func nearYouWithoutALocationSaysSoAndRunsNothing() throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner, location: nil)
        rig.model.runQuickChoice(.nearYou)
        #expect(runner.requests.isEmpty)
        #expect(rig.model.notice != nil)
        #expect(rig.model.phase == .idle)
    }

    @Test func tomorrowsScoresAskForTomorrowsDay() async throws {
        let fake = FakeFindScores()
        var config = Rig.fastFind
        config.scoreLeadCount = 2
        let rig = try Rig(configuration: config, scores: fake)
        rig.model.mapRegion = GeoRegion(center: FindFixtures.moab, latitudeDelta: 1.0, longitudeDelta: 1.0)
        rig.model.runQuickChoice(.tomorrow)
        _ = await waitUntil { rig.model.phase == .finished }
        #expect(!rig.model.rows.isEmpty)
        let asked = try #require(fake.requests.first)
        let target = try #require(rig.model.scoreTargets.values.first { $0.place.id == asked.placeID })
        #expect(target.day == LocalDay(FindFixtures.retrievedAt.addingTimeInterval(86_400), in: target.place.timeZone))
    }
}

/// Today when the light has gone: no night "0" in place of a score, and one quiet line instead of a list of zeros.
@MainActor @Suite("Find: Today after sunset")
struct FindTodayOverTests {
    private let area = GeoRegion(center: FindFixtures.moab, latitudeDelta: 1.0, longitudeDelta: 1.0)

    private func report(for place: Place, scores: [LightWindowKind: Int]) -> SkyReport {
        let base = ConditionsFixtures.report(day: LocalDay(FindFixtures.retrievedAt, in: place.timeZone), place: place)
        return ConditionsFixtures.report(base, scores: scores)
    }

    private func runToday(clock: Date, scores: [LightWindowKind: Int]) async throws -> (Rig, FakeFindScores) {
        let fake = FakeFindScores()
        fake.script = { place, day in .ready(ConditionsFixtures.report(ConditionsFixtures.report(day: day, place: place), scores: scores)) }
        var config = Rig.fastFind
        config.scoreLeadCount = 6
        let rig = try Rig(configuration: config, scores: fake, now: { clock })
        rig.model.mapRegion = area
        rig.model.runQuickChoice(.today)
        _ = await waitUntil { rig.model.phase == .finished }
        _ = await waitUntil { rig.model.rows.contains { $0.score?.isLoading == false } }
        return (rig, fake)
    }

    @Test func theDecisionUsesTheClock() {
        let t = Date(timeIntervalSince1970: 1_791_806_400)
        let windows = [LightWindowSpan(kind: .goldenEvening, end: t.addingTimeInterval(3600)),
                       LightWindowSpan(kind: .blueEvening, end: t.addingTimeInterval(5400)),
                       LightWindowSpan(kind: .night, end: t.addingTimeInterval(20_000))]
        #expect(FindTodayLight.hasLightLeft(windows: windows, now: t))
        #expect(FindTodayLight.hasLightLeft(windows: windows, now: t.addingTimeInterval(5000)))
        #expect(!FindTodayLight.hasLightLeft(windows: windows, now: t.addingTimeInterval(5400)))
        // Night does not count as light, however much of it is left.
        #expect(!FindTodayLight.hasLightLeft(windows: [windows[2]], now: t))
        #expect(FindTodayLight.isOver(results: [windows], now: t.addingTimeInterval(6000)))
        #expect(!FindTodayLight.isOver(results: [windows], now: t))
        // Nothing reported yet is not "over".
        #expect(!FindTodayLight.isOver(results: [], now: t))
        #expect(!FindTodayLight.isOver(results: [[]], now: t))
    }

    @Test func afterSunsetANightZeroIsNotShownAndTheListSaysTodayIsOver() async throws {
        let place = ConditionsFixtures.place
        let late = report(for: place, scores: [:]).daylight.window(.blueEvening)!.span.end.addingTimeInterval(1800)
        let (rig, _) = try await runToday(clock: late, scores: [.night: 0])
        #expect(!rig.model.rows.isEmpty)
        // The night window is scored 0, but it is not what a daytime place shows: no number at all.
        let shown = rig.model.rows.compactMap(\.score)
        #expect(!shown.isEmpty && shown.allSatisfy { $0.value == nil })
        #expect(rig.model.todayLightIsOver)
    }

    @Test func beforeSunsetTheScoreShowsAndTodayIsNotOver() async throws {
        let place = ConditionsFixtures.place
        let early = report(for: place, scores: [:]).daylight.window(.goldenMorning)!.span.start.addingTimeInterval(-3600)
        let (rig, _) = try await runToday(clock: early, scores: [.goldenEvening: 70, .night: 0])
        let values = rig.model.rows.compactMap(\.score).compactMap(\.value)
        #expect(values.contains(70))
        #expect(!rig.model.todayLightIsOver)
    }

    @Test func tomorrowIsNeverCalledOver() async throws {
        let clock = FindFixtures.retrievedAt
        let fake = FakeFindScores()
        let rig = try Rig(scores: fake, now: { clock })
        rig.model.mapRegion = area
        rig.model.runQuickChoice(.tomorrow)
        _ = await waitUntil { rig.model.phase == .finished }
        #expect(!rig.model.todayLightIsOver)
    }
}

@MainActor @Suite("One-time notices")
struct OneTimeNoticesTests {
    @Test func aNoticeIsSeenOnceAndStaysSeen() {
        let name = "iter.notices.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = OneTimeNotices(defaults: defaults)
        #expect(!first.hasSeen(.moveSpotTip))
        first.markSeen(.moveSpotTip)
        #expect(first.hasSeen(.moveSpotTip) && !first.hasSeen(.firstRunGuide))
        // A relaunch reads the persisted flag.
        #expect(OneTimeNotices(defaults: defaults).hasSeen(.moveSpotTip))
    }

    @Test func firstRunIsShownOnceOnARealLaunchAndNeverInAnInMemoryRun() {
        #expect(OneTimeNotices.shouldShowFirstRun(forced: nil, inMemoryStore: false, seen: false))
        #expect(!OneTimeNotices.shouldShowFirstRun(forced: nil, inMemoryStore: false, seen: true))
        #expect(!OneTimeNotices.shouldShowFirstRun(forced: nil, inMemoryStore: true, seen: false))
    }

    @Test func theLaunchSwitchForcesItOnOrOff() {
        #expect(OneTimeNotices.shouldShowFirstRun(forced: true, inMemoryStore: true, seen: true))
        #expect(!OneTimeNotices.shouldShowFirstRun(forced: false, inMemoryStore: false, seen: false))
    }

    @Test func anInMemoryLaunchStartsCleanEveryTime() {
        let a = OneTimeNotices.forLaunch(inMemoryStore: true)
        a.markSeen(.firstRunGuide)
        #expect(!OneTimeNotices.forLaunch(inMemoryStore: true).hasSeen(.firstRunGuide))
    }
}

@Suite("Launch clock")
struct FixedNowTests {
    @Test func theClockSwitchIsHonouredOnlyForAnInMemoryStore() {
        let args = ["-IterNow", "2026-11-23T01:19:00Z"]
        #expect(LaunchOptions(arguments: args + ["-IterInMemoryStore", "YES"]).fixedNow == Date(timeIntervalSince1970: 1_795_396_740))
        #expect(LaunchOptions(arguments: args).fixedNow == nil)
        #expect(LaunchOptions(arguments: ["-IterInMemoryStore", "YES", "-IterNow", "tonight"]).fixedNow == nil)
    }
}
