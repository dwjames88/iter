import Foundation
import Testing
import IterModel
import IterGoActivity
@testable import IterScreens

@Suite("GoSection words")
struct GoSectionTests {
    typealias F = GoSectionFixtures
    let loc = F.locale
    let now = F.now

    @Test func heroKindPerPhase() {
        #expect(GoText.heroKind(F.before()) == .beforeDeparture)
        #expect(GoText.heroKind(F.driving()) == .driving)
        #expect(GoText.heroKind(F.atStop()) == .atStop)
        var p = F.before(); p.phase = .paused
        #expect(GoText.heroKind(p) == .paused)
        #expect(GoText.heroKind(.idle(at: now)) == nil)
    }

    @Test func leaveHeadlineAndCountdown() {
        let s = F.before()
        #expect(GoText.leaveHeadline(s, locale: loc) == "Leave by 17:05")
        let c = GoText.leaveCountdown(s, now: now, locale: loc)
        #expect(c?.text == "in 42 min")
        #expect(c?.tone == .normal)
        #expect(GoText.leaveCountdown(F.before(status: .leaveNow, leaveBy: now), now: now, locale: loc)?.text == "Leave now")
        let late = GoText.leaveCountdown(F.before(status: .late, leaveBy: F.at(16, 17), late: 6 * 60), now: now, locale: loc)
        #expect(late?.text == "6 min late")
        #expect(late?.tone == .late)
    }

    @Test func etaQuality() {
        #expect(GoText.etaQuality(.live, locale: loc) == "Live traffic")
        #expect(GoText.etaQuality(.planned, locale: loc) == "Planned drive")
        #expect(GoText.etaQuality(.offlineEstimate, locale: loc) == "Offline estimate")
    }

    @Test func driveAndArrivalAgainstLight() {
        let s = F.before()
        #expect(GoText.driveLine(s.drive!, locale: Locale(identifier: "en_GB")).hasPrefix("48 min"))
        #expect(GoText.arrivalAgainstLight(s, locale: loc) == "Arrive 17:53 · 27 min before sunset")
    }

    @Test func eveningBeforeAndEarliest() {
        let s = F.before(suggested: F.at(20, 10), earliest: F.at(17, 40))
        #expect(GoText.eveningBefore(s, locale: loc) == "Drive tonight: leave after 20:10")
        #expect(GoText.earliestDeparture(s, now: now, locale: loc) == "Earliest you can leave: 17:40")
        #expect(GoText.eveningBefore(F.before(), locale: loc) == nil)
    }

    @Test func driving() {
        let s = F.driving()
        #expect(GoText.arriveHeadline(s, locale: loc) == "Arrive 17:42")
        #expect(GoText.arriveCountdown(s, now: now, locale: loc) == "in 1 hr, 19 min")
        #expect(GoText.drivingStatus(s, locale: loc).text == "38 min before sunset")
        let late = GoText.drivingStatus(F.driving(status: .late, late: 6 * 60), locale: loc)
        #expect(late.text == "6 min after set-up")
        #expect(late.tone == .late)
        #expect(GoText.drivingStatus(F.driving(status: .missed), locale: loc).text == "Sunset over on arrival")
    }

    @Test func alternative() {
        #expect(GoText.alternative(F.driving(), locale: loc) == nil)
        let a = GoText.alternative(F.driving(status: .missed, alternative: true), locale: loc)
        #expect(a?.title == "Next best: Dead Horse Point")
        #expect(a?.detail == "Evening Blue Hour 18:20 · arrive 18:05")
    }

    @Test func windowLeftAndStay() {
        let s = F.atStop()
        // current window ends 19:00, now 16:23 -> 2 hr, 37 min
        #expect(GoText.windowLeft(s, now: F.at(18, 37), locale: loc) == "Sunset · 23 min left")
        #expect(GoText.windowLeft(s, now: F.at(19, 5), locale: loc) == "Sunset · over")
        let fits = GoText.stayCost(s, locale: loc)
        #expect(fits?.text == "Shoot until 18:52 as planned")
        #expect(fits?.warns == false)
        let cut = GoText.stayCost(F.atStop(cuts: 12 * 60), locale: loc)
        #expect(cut?.text == "Leave by 18:40 to make evening blue hour at Dead Horse Point, 12 min before this window ends")
        #expect(cut?.warns == true)
    }

    @Test func paused() {
        var s = F.before(); s.phase = .paused
        #expect(GoText.pausedTitle == "Trip mode paused")
        #expect(GoText.pausedDetail(s, locale: loc) == "Next: Delicate Arch · leave by 17:05")
    }

    @Test func skyWords() {
        let s = F.before()
        #expect(GoText.skyBasis(s, now: now, locale: loc) == "Based on KCNY observation · 7 mi away · 8 min ago"
                || GoText.skyBasis(s, now: now, locale: loc).hasPrefix("Based on KCNY observation · "))
        #expect(GoText.trendWord(.rising, locale: loc) == "Rising")
        #expect(GoText.trendSymbol(.falling) == "arrow.down.right")
        #expect(GoText.trendWord(.unknown, locale: loc) == nil)
        #expect(GoText.forecastBeside(s.sky!, locale: loc) == "Forecast 64")
        var fo = s; fo.sky = F.sky(basis: .forecastOnly); fo.weather = []
        #expect(GoText.skyBasis(fo, now: now, locale: loc) == "Forecast only, no recent observation")
        var nw = s
        var sky = F.sky(live: nil, forecast: 64, trend: .rising, basis: .nextWindowForecast, kind: .goldenMorning)
        sky.windowStart = F.at(6, 0).addingTimeInterval(86_400)
        nw.sky = sky
        #expect(GoText.skyBasis(nw, now: now, locale: loc) == "Next window: Sunrise tomorrow · forecast 64, rising")
        #expect(GoText.skyTitle(sky, now: now, locale: loc) == "Forecast Sky Index")
    }

    @Test func weatherWords() {
        let w = F.obs(here: true)
        #expect(GoText.weatherSource(w, now: now, locale: loc) == "Observed at KCNY · 7 mi away · 8 min ago")
        let f = GoText.facts(w, locale: loc)
        #expect(f.cloud == "40%")
        #expect(f.precip == "10%")
        #expect(GoText.weatherSource(F.obs(here: false, basis: .forecast), now: now, locale: loc) == "Forecast for this hour")
        #expect(GoText.weatherSubject(F.obs(here: false), in: F.before(), locale: loc) == "At Delicate Arch")
    }

    @Test func hourStrip() {
        let cols = GoText.hourColumns(F.before(), locale: loc)
        #expect(cols.count == 6)
        #expect(cols[0].label == "16:00")
        #expect(cols[2].inWindow)
        #expect(GoText.hourColumns(F.before(), locale: F.usLocale)[1].label == "5 PM")
        #expect(GoText.hourBasisNote(F.before(), locale: loc) == "Nowcast until 18:00, forecast after")
        #expect(GoText.hourColumns(.idle(at: now)).isEmpty)
    }

    @Test func militaryMarkerShown() {
        let words = F.sources.map { GoText.sourceWords($0, now: now, zone: F.zone, locale: loc) }
        #expect(words[0].isMilitary)
        #expect(words[0].tier == "Military-origin data · US Air Force")
        #expect(words[0].primary.hasPrefix("Cloud · NOAA HRRR"))
        #expect(!words[1].isMilitary)
        #expect(words[1].primary == "Observation · KCNY METAR · 7 mi away · 8 min ago")
        let stale = GoSourceInfo(role: "Cloud", name: "GFS", tier: .military, asOf: F.at(10, 0), isStale: true)
        #expect(GoText.sourceWords(stale, now: now, zone: F.zone, locale: loc).primary == "Cloud · GFS · Stale, as of 10:00")
    }

    @Test func alerts() {
        #expect(GoText.alertLevel("Severe") == .danger)
        #expect(GoText.alertLevel("Moderate") == .warning)
        let a = GoAlertInfo(id: "1", event: "Flash Flood Warning", headline: nil, severity: "Severe", ends: F.at(21, 0))
        #expect(GoText.alertDetail(a, zone: F.zone, locale: loc) == "Severe · until 21:00")
        #expect(GoText.alertSymbol(.danger) != GoText.alertSymbol(.warning))
    }

    @Test func freshness() {
        #expect(GoText.freshnessLines(F.before(), now: now, locale: loc).isEmpty)
        var off = F.before()
        off.freshness = GoFreshness(conditionsAsOf: F.at(16, 10), isOffline: true, isPowerSaving: true)
        off.drive?.source = .offlineEstimate
        let lines = GoText.freshnessLines(off, now: now, locale: loc).map(\.text)
        #expect(lines.contains("Offline · showing values from 16:10"))
        #expect(lines.contains("Offline estimate"))
        #expect(lines.contains("Saving power: updates every 10 min"))
        var old = F.before()
        old.generatedAt = now.addingTimeInterval(-3 * 3600)
        old.freshness = GoFreshness(conditionsAsOf: now.addingTimeInterval(-3 * 3600), conditionsAreStale: true)
        let t = GoText.freshnessLines(old, now: now, locale: loc).map(\.text)
        #expect(t.contains("Conditions updated 3 hrs ago"))
        #expect(t.contains("Updated 3 hrs ago"))
        #expect(GoText.freshnessLines(.idle(at: now), now: now).isEmpty)
    }

    @Test func oldSnapshotNeverSoundsCurrent() {
        // Snapshot from 13:30, now 16:23: leave-by 16:04 passed 19 min ago, stored status still "early".
        var s = F.before(status: .early, leaveBy: F.at(16, 4))
        s.generatedAt = F.at(13, 30)
        let c = GoText.leaveCountdown(s, now: now, locale: loc)
        #expect(c?.text == "19 min past leave-by")
        #expect(c?.tone == .late)
        #expect(GoText.staleBanner(s, now: now, locale: loc) == "As of 13:30 · 2 hrs, 53 min old")
        let badge = GoText.statusWord(s, now: now, locale: loc)
        #expect(badge?.text == "Past leave-by")
        var ahead = s; ahead.leave?.leaveBy = F.at(17, 5)
        #expect(GoText.statusWord(ahead, now: now, locale: loc) == nil)   // no "On time" from an old snapshot
        #expect(GoText.leaveCountdown(ahead, now: now, locale: loc)?.text == "in 42 min")
        // A fresh snapshot has no banner and keeps its badge.
        #expect(GoText.staleBanner(F.before(), now: now, locale: loc) == nil)
        #expect(GoText.statusWord(F.before(), now: now, locale: loc)?.text == "On time")
    }

    @Test func oldSkyIsNotLive() {
        let s = F.before()
        #expect(GoText.skyTitle(s.sky!, now: now, locale: loc) == "Live Sky Index")
        var old = F.sky(); old.asOf = F.at(13, 30)
        #expect(GoText.skyIsOld(old, now: now))
        #expect(GoText.skyTitle(old, now: now, locale: loc) == "Last Sky Reading")
        var flagged = F.sky(); flagged.isStale = true
        #expect(GoText.skyTitle(flagged, now: now, locale: loc) == "Last Sky Reading")
        var snap = s; snap.sky = old
        #expect(GoText.skyAgeLine(snap, now: now, locale: loc) == "As of 13:30 · 2 hrs, 53 min old")
        #expect(GoText.skyAgeLine(s, now: now, locale: loc) == nil)
    }
}
