import Foundation
import Testing
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions
@testable import IterFeatures

private let today = ConditionsFixtures.today
private func day(_ n: Int) -> LocalDay { today.adding(days: n) }

@MainActor
@Suite("ConditionsModel: states")
struct ConditionsStateTests {
    @Test func loadingShowsNothingButAstronomyStillWorks() {
        let m = ConditionsPreviewData.model(.loading)
        #expect(m.status == .loading)
        #expect(m.headline == nil && m.windows.isEmpty && m.hours.isEmpty && m.observation == nil)
        #expect(m.whenToGo == nil)
        #expect(m.outlook.count == 10 && m.outlook.allSatisfy { $0.load == .loading && $0.score == nil })
        // The compass and the timeline are astronomy, not data: they are there before any forecast.
        #expect(m.compassDay.sunrise != nil && m.compassDay.sunset != nil)
        #expect(m.timeline.sun.count > 40 && m.timeline.clouds.isEmpty && !m.timeline.windows.isEmpty)
        #expect(m.timeline.windows.allSatisfy { $0.score == nil })
    }

    @Test func quickIsAScoreWithTheBetterTierOnItsWay() {
        let m = ConditionsPreviewData.model(.quick)
        #expect(m.status == .quick && m.status.isImproving)
        let h = try! #require(m.headline)
        #expect(h.tier == .quick)
        #expect(m.isUpdating)
        #expect(m.horizon.load == .loading)
        #expect(m.observation == nil && m.aurora == nil)
        #expect(m.windows.contains { $0.score != nil })
    }

    @Test func completeHasEverything() throws {
        let m = ConditionsPreviewData.model(.complete)
        #expect(m.status == .complete && !m.isUpdating)
        let h = try #require(m.headline)
        #expect(h.tier == .complete && h.kind == .goldenMorning, "Mesa Arch's intent is sunrise")
        #expect(m.windows.count >= 4)
        let sunrise = try #require(m.windows.first { $0.kind == .goldenMorning })
        #expect(sunrise.score != nil && !sunrise.contributors.isEmpty)
        #expect(sunrise.confidence != nil && sunrise.band != nil)
        #expect(m.outlook.count == 10 && m.outlook.allSatisfy { $0.load == .ready })
        #expect(m.whenToGo?.isProvisional == false)
        #expect(!m.hours.isEmpty && m.hours.allSatisfy { $0.cloudLow != nil })
        #expect(!m.timeline.clouds.isEmpty)
        #expect(m.horizon.load == .known && m.horizon.tallestDegrees == 9)
        #expect(!m.sourceLines.isEmpty && !m.attributions.isEmpty)
        #expect(m.aurora?.probabilityPercent == 3 && m.smoke.density == .light)
        #expect(m.alerts.isEmpty && m.comparison == nil)
    }

    @Test func terrainShortensTheMorningWindowAndSaysBy() throws {
        let m = ConditionsPreviewData.model(.complete)
        let w = try #require(m.windows.first { $0.kind == .goldenMorning })
        #expect(w.effectiveSpan != nil)
        #expect((w.terrainLostSeconds ?? 0) > 60)
        #expect(m.horizon.shortened.contains { $0.kind == .goldenMorning && $0.effective.duration < $0.natural.duration })
        let quick = ConditionsPreviewData.model(.quick)
        #expect(quick.windows.first { $0.kind == .goldenMorning }?.effectiveSpan == nil, "no horizon yet, so nothing is cut")
    }

    @Test func staleShowsItsAgeAndNeverLooksFresh() throws {
        let m = ConditionsPreviewData.model(.stale)
        #expect(m.status == .stale(age: 5 * 3600))
        let h = try #require(m.headline)
        #expect(h.isStale)
        #expect(m.windows.contains { $0.isStale })
    }

    @Test func offlineKeepsTheLastGoodForecastWithItsAge() throws {
        let m = ConditionsPreviewData.model(.offline)
        let fetched = ConditionsFixtures.now.addingTimeInterval(-5 * 3600)
        #expect(m.status == .offline(lastGood: fetched, age: 5 * 3600))
        #expect(m.offlineNote == "Forecast from 01:00, offline")
        #expect(m.headline != nil)
    }

    @Test func outOfCoverageHasNoScoreAndSaysWhy() throws {
        let m = ConditionsPreviewData.model(.outOfCoverage)
        #expect(m.status == .outOfCoverage)
        #expect(m.headline == nil)
        #expect(m.windows.allSatisfy { $0.score == nil && $0.unavailable != nil })
        #expect(m.whenToGo == nil)
        let w = try #require(m.windows.first)
        if case .noForecast(let reasons) = w.unavailable { #expect(reasons.contains(.outsideCoverage)) } else { Issue.record("expected noForecast") }
        #expect(ConditionsText.phrase(try #require(w.unavailable)).contains("no source covers this place"))
    }

    @Test func otherReasonsAreNamedNotGuessed() {
        var r = ConditionsFixtures.report(day: today)
        r.forecast = .none([.needsKey("some.key")])
        #expect(ConditionsDerivation.status(r, now: ConditionsFixtures.now) == .unavailable([.needsKey("some.key")]))
        var past = ConditionsFixtures.report(day: day(-1))
        past.forecast = .none([])
        #expect(ConditionsDerivation.status(past, now: ConditionsFixtures.now) == .pastDay)
        var off = ConditionsFixtures.report(day: today)
        off.forecast = .none([.offline(lastGood: nil)])
        #expect(ConditionsDerivation.status(off, now: ConditionsFixtures.now) == .offline(lastGood: nil, age: nil))
        #expect(ConditionsDerivation.status(nil, now: ConditionsFixtures.now) == .loading)
    }

    @Test func lightPollutionAndSeeingAreNamedGapsNeverNumbers() throws {
        let m = ConditionsPreviewData.model(.complete)
        let lp = try #require(m.gaps.first { $0.subject == .lightPollution })
        let seeing = try #require(m.gaps.first { $0.subject == .seeing })
        #expect(lp.title == "Light Pollution" && seeing.title == "Seeing")
        #expect(lp.reasons == ["no source provides it yet"] && seeing.reasons == ["no source provides it yet"])
        // Even a report that forgot to list them gets them once it has settled.
        var r = ConditionsFixtures.report(day: today)
        r.gaps = []
        #expect(ConditionsDerivation.gaps(r).map(\.subject).sorted { "\($0)" < "\($1)" } == [.lightPollution, .seeing].sorted { "\($0)" < "\($1)" })
        r.loading = [.lightAndSeeing]
        #expect(ConditionsDerivation.gaps(r).isEmpty, "still loading: not a gap yet")
    }

    @Test func theNearestStationIsLabelledHonestlyIncludingMilitaryOrigin() throws {
        let civil = ConditionsPreviewData.model(.complete).observation
        #expect(civil?.stationName == "Canyonlands Field" && civil?.distanceKm == 38 && civil?.isMilitary == false)
        #expect(civil?.originLabel.contains("Government") == true)
        #expect(Int(civil?.ageSeconds ?? 0) == 47 * 60 && civil?.isOld == false)
        let mil = try #require(ConditionsPreviewData.model(.complete, configure: { $0.militaryStation = true }).observation)
        #expect(mil.isMilitary && mil.stationID == "KDPG")
        #expect(mil.originLabel == "Military-origin (US Army) via NOAA Aviation Weather Center")
        #expect(mil.rawMETAR?.hasPrefix("KDPG") == true)
    }

    @Test func aDisagreeingSecondSourceIsShownWithHowFar() throws {
        let m = ConditionsPreviewData.model(.complete, configure: { $0.withComparison = true; $0.withAlert = true })
        let c = try #require(m.comparison)
        #expect(c.sourceName == "MET Norway" && c.disagrees && c.maxCloudDifference == 0.42)
        #expect(m.alerts.map(\.event) == ["Wind Advisory"])
        #expect(m.alerts.first?.sender == "NWS Grand Junction CO")
    }

    @Test func reasonsAndCausesReadInPlainWords() throws {
        let m = ConditionsPreviewData.model(.complete)
        let w = try #require(m.windows.first { $0.kind == .goldenMorning })
        let lines = w.contributors.map(ConditionsText.reason)
        #expect(!lines.isEmpty && lines.allSatisfy { !$0.isEmpty })
        #expect(lines.contains { $0.contains("cloud") || $0.contains("Cloud") })
        #expect(ConditionsText.phrase(ConfidenceCause.leadTime(hours: 52)) == "The window is 52 hours after the forecast run.")
        #expect(ConditionsText.phrase(ConfidenceCause.sourceSpread) == "Two forecasts disagree about cloud.")
        #expect(ConditionsText.age(7800) == "2 h 10 min")
        #expect(ConditionsText.name(.goldenEvening) == "Sunset")
    }
}

@MainActor
@Suite("ConditionsModel: loading, best window, no flicker")
struct ConditionsFlowTests {
    private func settle(_ m: ConditionsModel, _ check: @MainActor () -> Bool) async -> Bool { await waitUntil(.seconds(20), check) }

    @Test func selectedDayLoadsOnScreenThenTheOutlookAtBackgroundPriority() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        #expect(feed.requests == [.init(day: today, priority: .onScreen, isRefresh: false)])
        feed.set(.loading(previous: nil), day: today)
        try await Task.sleep(for: .milliseconds(30))
        #expect(feed.requests.count == 1, "the outlook waits for the selected day")
        feed.set(.ready(ConditionsFixtures.report(day: today, options: quickOptions)), day: today)
        #expect(await settle(m) { feed.requests.count == 10 })
        let background = feed.requests.dropFirst()
        #expect(background.allSatisfy { $0.priority == .background && !$0.isRefresh })
        #expect(Set(background.map(\.day)) == Set((1..<10).map(day)))
        feed.set(.ready(ConditionsFixtures.report(day: today)), day: today)
        try await Task.sleep(for: .milliseconds(30))
        #expect(feed.requests.count == 10, "asked once")
        m.stop()
    }

    var quickOptions: ConditionsFixtures.Options { var o = ConditionsFixtures.Options(); o.tier = .quick; return o }

    @Test func whenToGoPicksTheHighestScoreAndTiesGoToTheSoonerDay() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        let base = ConditionsFixtures.report(day: today)
        func put(_ n: Int, _ scores: [LightWindowKind: Int], _ c: Confidence = .high) {
            let d = day(n)
            feed.set(.ready(ConditionsFixtures.report(ConditionsFixtures.report(day: d), scores: scores, confidence: c)), day: d)
        }
        _ = base
        put(0, [.goldenMorning: 55])
        put(3, [.goldenEvening: 82])
        put(5, [.goldenMorning: 82, .blueMorning: 60])
        #expect(await settle(m) { m.whenToGo != nil })
        #expect(m.whenToGo?.day == day(3), "tie at 82: the sooner day")
        #expect(m.whenToGo?.kind == .goldenEvening && m.whenToGo?.score == 82)
        #expect(m.whenToGo?.isProvisional == true, "seven days have not answered")
        put(7, [.night: 91])
        #expect(await settle(m) { m.whenToGo?.day == day(7) })
        #expect(m.whenToGo?.kind == .night && m.whenToGo?.band == LightBand(score: 91))
        for n in [1, 2, 4, 6, 8, 9] { put(n, [.goldenMorning: 20]) }
        #expect(await settle(m) { m.whenToGo?.isProvisional == false })
        #expect(m.whenToGo?.day == day(7))
        m.stop()
    }

    @Test func withinADayTheEarlierWindowWinsATie() {
        let r = ConditionsFixtures.report(ConditionsFixtures.report(day: today), scores: [.goldenMorning: 70, .goldenEvening: 70])
        #expect(ConditionsDerivation.bestWindow(r.daylight)?.kind == .goldenMorning)
    }

    @Test func outlookRowsFadeWithConfidence() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        feed.set(.ready(ConditionsFixtures.report(ConditionsFixtures.report(day: day(0)), scores: [.goldenMorning: 80], confidence: .high)), day: day(0))
        feed.set(.ready(ConditionsFixtures.report(ConditionsFixtures.report(day: day(1)), scores: [.goldenMorning: 80], confidence: .low)), day: day(1))
        #expect(await settle(m) { m.outlook[1].score != nil })
        let high = try #require(m.outlook[0].opacity), low = m.outlook[1].opacity
        #expect(high == 1 && low < high && low > 0.35)
        #expect(m.outlook[2].opacity == 0.35 && m.outlook[2].load == .loading)
        #expect(m.outlook[0].isToday && m.outlook[0].isSelected && !m.outlook[1].isSelected)
        m.stop()
    }

    @Test func theShownScoreNeverDropsOutBetweenQuickAndComplete() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        #expect(m.headline == nil && m.status == .loading)
        var seen: [HeadlineScore?] = []
        let quick = ConditionsFixtures.report(day: today, options: quickOptions)
        feed.set(.loading(previous: nil), day: today)
        feed.set(.ready(quick), day: today)
        #expect(await settle(m) { m.headline != nil })
        seen.append(m.headline)
        let quickHeadline = try #require(m.headline)
        #expect(quickHeadline.tier == .quick && m.status == .quick)
        let revision = m.scoreRevision
        // The store restarts the load: the quick report stays as `previous`.
        feed.set(.loading(previous: quick), day: today)
        try await Task.sleep(for: .milliseconds(30))
        seen.append(m.headline)
        #expect(m.headline == quickHeadline, "still showing the quick score, not an empty or loading state")
        #expect(m.status == .quick && m.scoreRevision == revision)
        // The complete report replaces it.
        let complete = ConditionsFixtures.report(day: today)
        feed.set(.ready(complete), day: today)
        #expect(await settle(m) { m.status == .complete })
        seen.append(m.headline)
        #expect(seen.allSatisfy { $0 != nil }, "never nil between quick and complete")
        let final = try #require(m.headline)
        #expect(final.tier == .complete)
        if final.value != quickHeadline.value || final.kind != quickHeadline.kind || final.confidence != quickHeadline.confidence {
            #expect(m.scoreRevision == revision + 1)
            #expect(m.previousHeadline == quickHeadline)
        } else {
            #expect(m.scoreRevision == revision, "same score: a quiet update, no cross-fade")
        }
        m.stop()
    }

    @Test func aSecondReportWithADifferentScoreBumpsTheRevisionOnce() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        let q = ConditionsFixtures.report(ConditionsFixtures.report(day: today, options: quickOptions), scores: [.goldenMorning: 40], confidence: .low)
        feed.set(.ready(q), day: today)
        #expect(await settle(m) { m.headline?.value == 40 })
        let before = m.scoreRevision
        feed.set(.ready(ConditionsFixtures.report(ConditionsFixtures.report(day: today), scores: [.goldenMorning: 78], confidence: .high)), day: today)
        #expect(await settle(m) { m.headline?.value == 78 })
        #expect(m.scoreRevision == before + 1)
        #expect(m.previousHeadline?.value == 40)
        #expect(m.headline?.band == .great)
        m.stop()
    }

    @Test func aRefreshKeepsTheScoreOnScreen() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        let r = ConditionsFixtures.report(day: today)
        feed.set(.ready(r), day: today)
        #expect(await settle(m) { m.status == .complete })
        let h = m.headline
        m.refresh()
        #expect(feed.requests.last?.isRefresh == true)
        feed.set(.loading(previous: r), day: today)
        // Wait for the loading state to reach the model (a fixed sleep raced under load), then check nothing blanked.
        #expect(await settle(m) { m.isUpdating })
        #expect(m.headline == h && m.status == .complete)
        m.stop()
    }

    @Test func changingTheDayShowsLoadingNotTheOtherDaysScore() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        m.start()
        feed.set(.ready(ConditionsFixtures.report(day: today)), day: today)
        #expect(await settle(m) { m.headline != nil })
        let todaysScrub = m.scrubTime
        m.select(day: day(2))
        #expect(feed.requests.last == .init(day: day(2), priority: .onScreen, isRefresh: false))
        #expect(m.headline == nil && m.windows.isEmpty && m.status == .loading)
        #expect(m.scrubTime != todaysScrub)
        #expect(m.outlook.first { $0.isSelected }?.day == day(2))
        feed.set(.ready(ConditionsFixtures.report(day: day(2))), day: day(2))
        #expect(await settle(m) { m.headline != nil })
        // A day already held shows at once.
        m.select(day: today)
        #expect(m.headline != nil && m.status == .complete)
        m.stop()
    }

    @Test func nowComesFromTheLiveService() async throws {
        let feed = FakeConditionsFeed()
        let m = ConditionsModel(place: ConditionsFixtures.place, feed: feed, now: { ConditionsFixtures.now })
        #expect(m.liveLoad == .idle && m.live == nil)
        await m.loadLive()
        #expect(m.liveLoad == .ready && m.live?.placeID == ConditionsFixtures.place.id)
        #expect(m.live?.notice == .forecastOnly)
        #expect(feed.liveCalls == 1)
    }
}

@MainActor
@Suite("ConditionsModel: compass and timeline")
struct ConditionsCompassTests {
    @Test func scrubbingToSunsetPutsTheSunNearWestAndOnTheHorizon() throws {
        let m = ConditionsPreviewData.model(.complete)
        let sunset = try #require(m.compassDay.sunset)
        m.scrubTime = sunset.time
        #expect((245.0...290.0).contains(m.compass.sun.azimuth), "October sunset at 38N is west-southwest: \(m.compass.sun.azimuth)")
        #expect(abs(m.compass.sun.altitude) < 1.5)
        #expect(abs(sunset.azimuth - m.compass.sun.azimuth) < 0.01)
        #expect(!m.compass.coreIsInDark)
    }

    @Test func scrubbingToSunriseAndNoonIsEastThenHigh() throws {
        let m = ConditionsPreviewData.model(.complete)
        m.scrubTime = try #require(m.compassDay.sunrise).time
        #expect((70.0...115.0).contains(m.compass.sun.azimuth) && abs(m.compass.sun.altitude) < 1.5)
        m.scrubTime = m.compassDay.solarNoon
        #expect(m.compass.sun.altitude > 40 && (150.0...210.0).contains(m.compass.sun.azimuth))
        #expect(m.compass.sunIsUp)
        m.scrub(toWindow: .goldenEvening)
        let w = try #require(m.windows.first { $0.kind == .goldenEvening })
        #expect(m.scrubTime == w.span.midpoint)
        #expect(m.compass.sun.altitude > 0 && m.compass.sun.altitude < 8)
    }

    @Test func scrubTimeIsClampedToTheSelectedDay() {
        let m = ConditionsPreviewData.model(.complete)
        m.scrubTime = ConditionsFixtures.now.addingTimeInterval(5 * 86_400)
        #expect(m.scrubTime == today.adding(days: 1).start(in: ConditionsFixtures.zone))
        m.scrubTime = ConditionsFixtures.now.addingTimeInterval(-5 * 86_400)
        #expect(m.scrubTime == today.start(in: ConditionsFixtures.zone))
        m.scrubToNow()
        #expect(m.scrubTime == ConditionsFixtures.now)
    }

    @Test func theMoonAndMilkyWayAreReportedForTheNight() throws {
        let m = ConditionsPreviewData.model(.complete)
        #expect(m.compassDay.moonIllumination >= 0 && m.compassDay.moonIllumination <= 1)
        let mw = try #require(m.compassDay.milkyWay)
        #expect(mw.peakAltitude > -90 && (0...360).contains(mw.peakAzimuth))
        #expect(mw.isVisible == (mw.coreUpInDark != nil))
        // The core's position at its own peak time matches the day's summary.
        m.scrubTime = mw.peakTime
        #expect(abs(m.compass.milkyWayCore.altitude - mw.peakAltitude) < 0.01)
        if let rise = m.compassDay.moonrise { #expect((0...360).contains(rise.azimuth)) }
    }

    @Test func theCompassStartsAtNowOnTodayAndAtSunsetOnOtherDays() throws {
        let m = ConditionsPreviewData.model(.complete)
        #expect(m.scrubTime == ConditionsFixtures.now)
        m.select(day: day(3))
        #expect(m.scrubTime == m.compassDay.sunset?.time)
    }

    @Test func theTimelineHoldsSunAltitudeCloudLayersAndWindowSpans() throws {
        let m = ConditionsPreviewData.model(.complete)
        let t = m.timeline
        #expect(t.sun.first?.time == t.dayStart && t.sun.last?.time == t.dayEnd)
        #expect(t.sun.map(\.altitude).max()! > 40 && t.sun.map(\.altitude).min()! < -20)
        #expect(t.clouds.allSatisfy { $0.low != nil && $0.mid != nil && $0.high != nil })
        #expect(t.clouds.first?.time == Date(timeIntervalSince1970: 1_791_806_400), "the forecast starts at the current hour")
        #expect(t.windows.count == m.windows.count)
        #expect(t.sunrise != nil && t.sunset != nil && t.sunrise! < t.sunset!)
    }
}
