import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel
import IterPlan
import IterSky
import IterConditions

private func input(_ rig: RunRig, now: Date, conditions: GoConditionsState = GoConditionsState(), eta: GoETAFacts = GoETAFacts(),
                   fix: LocationFix? = nil, power: PowerState = .normal, etaLive: ETA? = nil) -> GoSnapshotInput {
    let origin = fix?.coordinate
    let live = LiveSchedule.make(trip: rig.fx.trip, start: rig.fx.home, windows: rig.fx.windows, plannedLegs: [:], progress: rig.run.progress, now: now,
                                 origin: origin, liveETAs: etaLive.map { [rig.fx.s1.id: $0] } ?? [:])
    return GoSnapshotInput(now: now, trip: rig.fx.trip, run: rig.run, live: live, windows: rig.fx.windows, conditions: conditions, eta: eta, lastFix: fix,
                           power: power)
}

@Test func snapshotIdleWithoutARun() {
    let rig = RunRig()
    var i = input(rig, now: RunFixture.h(8))
    i.run = nil
    let s = GoSnapshotBuilder.build(i)
    #expect(s.phase == .idle && s.runID == nil && s.next == nil)
}

@Test func snapshotArmedFillsStopsLeaveAndDrive() throws {
    let rig = RunRig()
    let now = RunFixture.h(8)
    let s = GoSnapshotBuilder.build(input(rig, now: now))
    #expect(s.phase == .armed && s.tripID == rig.fx.trip.id && s.runID == rig.run.id && s.tripName == "Run")
    let next = try #require(s.next)
    #expect(next.id == rig.fx.s1.id && next.number == 1 && next.name == "S1" && next.kind == .light && next.timeZoneIdentifier == "UTC")
    #expect(next.windowStart == RunFixture.h(10) && next.windowEnd == RunFixture.h(11))
    #expect(next.setUpBy == RunFixture.h(10).addingTimeInterval(-20 * 60) && next.arriveBy == next.setUpBy)
    #expect(next.windowKind == .goldenMorning)
    #expect(s.current == nil && s.remainingCount == 4)
    let leave = try #require(s.leave)
    #expect(leave.leaveBy != nil && leave.status == .early && leave.lateBySeconds == nil && leave.suggestedDeparture == nil)
    let drive = try #require(s.drive)
    #expect(drive.source == .planned && drive.driveMeters == nil && drive.driveSeconds > 0)
    #expect(s.stay == nil && s.undo == nil && s.alternative == nil)
    // No live ETA yet: the ETA is stale; the location is not (not driving).
    #expect(s.freshness.etaIsStale && !s.freshness.locationIsStale && !s.freshness.isOffline)
}

@Test func snapshotDrivingArrivesNowPlusDriveAndFlagsStaleLocation() throws {
    let rig = RunRig.driving(to: RunFixture().s1, now: RunFixture.h(8))
    let now = RunFixture.h(8).addingTimeInterval(600)
    let eta = ETA(seconds: 900, arrival: now.addingTimeInterval(900), departing: now)
    let fix = rig.fx.fix(RunFixture.offset(RunFixture.origin, east: 5_000), speed: 20, at: now.addingTimeInterval(-60))
    var facts = GoETAFacts(fetchedAt: now.addingTimeInterval(-30), meters: 12_345, isOffline: false, cadence: 180)
    var s = GoSnapshotBuilder.build(input(rig, now: now, eta: facts, fix: fix, etaLive: eta))
    #expect(s.phase == .driving)
    #expect(s.drive?.source == .live && s.drive?.driveMeters == 12_345 && s.drive?.asOf == now.addingTimeInterval(-30))
    #expect(s.drive?.arrival == now.addingTimeInterval(900))
    #expect(s.freshness.etaIsStale == false && s.freshness.locationIsStale == false && s.freshness.locationAsOf == fix.timestamp)
    #expect(s.sources.contains("Apple Maps"))
    // ETA stale after twice its cadence; location stale after 5 min while driving.
    facts.fetchedAt = now.addingTimeInterval(-7 * 60)
    let old = rig.fx.fix(RunFixture.offset(RunFixture.origin, east: 5_000), speed: 20, at: now.addingTimeInterval(-6 * 60))
    s = GoSnapshotBuilder.build(input(rig, now: now, eta: facts, fix: old, etaLive: eta))
    #expect(s.freshness.etaIsStale && s.freshness.locationIsStale)
    // Offline: reflected; power saving: reflected.
    facts.isOffline = true
    s = GoSnapshotBuilder.build(input(rig, now: now, eta: facts, fix: fix, power: PowerState(isLowPowerMode: true)))
    #expect(s.freshness.isOffline && s.freshness.isPowerSaving)
}

@Test func snapshotAtStopCarriesStayAndUndo() throws {
    var rig = RunRig.driving(to: RunFixture().s1, now: RunFixture.h(9))
    rig.fix(near: rig.fx.s1, east: 0, speed: 0, at: RunFixture.h(9.5))
    #expect(rig.run.phase == .atStop)
    let now = RunFixture.h(9.5)
    let s = GoSnapshotBuilder.build(input(rig, now: now))
    #expect(s.phase == .atStop && s.current?.name == "S1" && s.next?.name == "S2")
    let stay = try #require(s.stay)
    #expect(stay.plannedDeparture == RunFixture.h(11) && stay.nextStopName == "S2" && stay.nextWindowKind == .goldenEvening)
    #expect(stay.cutsShortBySeconds == nil)
    let undo = try #require(s.undo)
    #expect(undo.toPhase == .atStop && undo.stopID == rig.fx.s1.id && undo.stopName == "S1" && undo.expiresAt == now.addingTimeInterval(120))
    // After two minutes it is gone.
    #expect(GoSnapshotBuilder.build(input(rig, now: now.addingTimeInterval(121))).undo == nil)
}

@Test func snapshotLateShowsAlternativeAndLateness() throws {
    var rig = RunRig(now: RunFixture.h(9.9))
    rig.run.visits[rig.fx.s1.id]?.status = .pending
    let now = RunFixture.h(9.9)
    let fix = rig.fx.fix(rig.fx.home.coordinate, at: now)
    let s = GoSnapshotBuilder.build(input(rig, now: now, fix: fix))
    let leave = try #require(s.leave)
    #expect(leave.status == .late || leave.status == .missed)
    #expect((leave.lateBySeconds ?? 0) > 0)
    #expect(s.alternative?.name == "S2" && s.alternative?.windowStart == RunFixture.h(17))
}

@Test func snapshotEveningBeforeSuggestsTonight() throws {
    let w = SimWorld([SimStopSpec(name: "D", eastKm: 70, session: .goldenEvening, day: 1, window: (41, 42)),
                      SimStopSpec(name: "C", eastKm: 130, session: .goldenMorning, day: 2, window: (54.5, 55.5))],
                     transfers: [2: .eveningBefore], dayCount: 3)
    var run = TripRun.start(trip: w.trip, runID: UUID(), at: w.stop(0).id, now: simH(40), alreadyThere: true)
    run.visits[w.stop(0).id]?.status = .arrived
    let live = LiveSchedule.make(trip: w.trip, start: w.home, windows: w.windows, plannedLegs: w.plannedLegs, progress: run.progress, now: simH(40.5),
                                 origin: nil, liveETAs: [:])
    let s = GoSnapshotBuilder.build(GoSnapshotInput(now: simH(40.5), trip: w.trip, run: run, live: live, windows: w.windows))
    #expect(s.next?.name == "C")
    #expect(s.leave?.suggestedDeparture == simH(42))
    #expect((s.leave?.leaveBy ?? .distantPast) > simH(50))
}

@Test func snapshotConditionsOnlyForTheNextStop() throws {
    let rig = RunRig()
    let s1 = rig.fx.s1, s2 = rig.fx.s2
    let now = RunFixture.h(8)
    func sky(_ id: UUID, _ live: Int) -> GoSkyInfo {
        GoSkyInfo(stopID: id, windowKind: .goldenMorning, windowStart: RunFixture.h(10), windowEnd: RunFixture.h(11), liveScore: live, forecastScore: 45,
                  band: .good, confidence: .high, trend: .rising, basis: .blended, asOf: now, notice: nil, isStale: false)
    }
    func weather(_ subject: GoWeatherInfo.Subject) -> GoWeatherInfo {
        GoWeatherInfo(subject: subject, basis: .observation, tempC: 4, cloudTotal: 0.3, visibilityKm: 20, precipChance: 0, windMs: 2, stationName: "K",
                      stationDistanceKm: 5, asOf: now)
    }
    let alert = GoAlertInfo(id: "a", event: "Wind", headline: nil, severity: "Moderate", ends: nil)
    var c = GoConditionsState(sky: sky(s1.id, 72), weather: [weather(.here), weather(.stop(s1.id)), weather(.stop(s2.id))], alerts: [alert],
                              packBuiltAt: now.addingTimeInterval(-3600), conditionsAsOf: now.addingTimeInterval(-120), isStale: true, isOffline: true)
    var s = GoSnapshotBuilder.build(input(rig, now: now, conditions: c))
    #expect(s.sky?.liveScore == 72 && s.sky?.displayScore == 72)
    #expect(s.weather.count == 2 && s.alerts == [alert])
    #expect(s.freshness.conditionsAsOf == now.addingTimeInterval(-120) && s.freshness.packBuiltAt == now.addingTimeInterval(-3600))
    #expect(s.freshness.conditionsAreStale && s.freshness.isOffline)
    // A sky about another stop is not shown.
    c.sky = sky(s2.id, 30)
    s = GoSnapshotBuilder.build(input(rig, now: now, conditions: c))
    #expect(s.sky == nil)
    // The activity content mirrors it.
    let content = GoActivityContent(snapshot: GoSnapshotBuilder.build(input(rig, now: now, conditions: GoConditionsState(sky: sky(s1.id, 72)))))
    #expect(content.liveScore == 72 && content.nextStopName == "S1" && content.status == .early)
}

@Test func snapshotFinishedAndPausedAreQuiet() throws {
    var rig = RunRig(now: RunFixture.h(8))
    rig.send(.user(.pause), at: RunFixture.h(8))
    var s = GoSnapshotBuilder.build(input(rig, now: RunFixture.h(8.1)))
    #expect(s.phase == .paused && !s.freshness.etaIsStale && s.freshness.nextRefreshAt == nil)
    rig.send(.user(.resume), at: RunFixture.h(8.2))
    rig.send(.user(.end), at: RunFixture.h(8.3))
    s = GoSnapshotBuilder.build(input(rig, now: RunFixture.h(8.4)))
    #expect(s.phase == .finished && !s.freshness.etaIsStale && !s.freshness.conditionsAreStale)
}

@Test func sampleDataIsFlaggedAndNeverCreditsAppleMaps() throws {
    let rig = RunRig()
    let now = RunFixture.h(9)
    let eta = ETA(seconds: 1200, arrival: now.addingTimeInterval(1200), departing: now)
    let fix = LocationFix(coordinate: rig.fx.home.coordinate, accuracyM: 5, timestamp: now)
    let facts = GoETAFacts(fetchedAt: now, meters: 9_000)
    var sample = input(rig, now: now, eta: facts, fix: fix, etaLive: eta)
    let real = GoSnapshotBuilder.build(sample)
    #expect(real.drive?.source == .live && real.sources.contains("Apple Maps") && real.isSampleData == nil)
    sample.isSampleData = true
    let s = GoSnapshotBuilder.build(sample)
    #expect(s.isSampleData == true)
    #expect(!s.sources.contains("Apple Maps") && s.sourceDetails?.contains { $0.name == "Apple Maps" } != true)
    #expect(GoActivityContent(snapshot: s).isSampleData == true && GoActivityContent(snapshot: real).isSampleData == nil)
    // It survives the App Group file.
    let again = try JSONDecoder().decode(GoSnapshot.self, from: JSONEncoder().encode(s))
    #expect(again.isSampleData == true)
}
