import Foundation
import Testing
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
