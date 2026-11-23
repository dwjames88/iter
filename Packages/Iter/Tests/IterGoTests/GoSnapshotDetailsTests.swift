import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel
import IterPlan
import IterSky
import IterSources
import IterConditions

private let t0 = RunFixture.t0

private func input(_ rig: RunRig, now: Date, conditions: GoConditionsState = GoConditionsState(), eta: GoETAFacts = GoETAFacts(),
                   fix: LocationFix? = nil, etaLive: ETA? = nil) -> GoSnapshotInput {
    let live = LiveSchedule.make(trip: rig.fx.trip, start: rig.fx.home, windows: rig.fx.windows, plannedLegs: [:], progress: rig.run.progress, now: now,
                                 origin: fix?.coordinate, liveETAs: etaLive.map { [rig.fx.s1.id: $0] } ?? [:])
    return GoSnapshotInput(now: now, trip: rig.fx.trip, run: rig.run, live: live, windows: rig.fx.windows, conditions: conditions, eta: eta, lastFix: fix)
}

private func prov(_ source: SourceID, fetchedAt: Date, origin: SourceOrigin? = nil, distance: Double? = nil) -> Provenance {
    Provenance(source: source, fetchedAt: fetchedAt, distanceKm: distance, licence: LicenceTag(key: "t", mayStore: true), origin: origin)
}

/// Conditions about S1 at `now`: a strip of eight hours from 08:00, an observation from a military airfield, a forecast whose
/// fields come from two sources.
private func s1Conditions(_ rig: RunRig, now: Date) -> GoConditionsState {
    let place = rig.fx.s1.place
    let strip = (0..<8).map { i -> LiveStripHour in
        let t = RunFixture.h(8 + Double(i))
        let basis: LiveStripHour.Basis = i == 0 ? .observation : (i == 1 ? .nowcast : .forecast)
        return LiveStripHour(time: t, conditions: HourlyConditions(time: t, cloudTotal: 0.1 * Double(i), precipChance: 0.02, visibilityKm: 20, tempC: 5, windMs: 3),
                             basis: basis)
    }
    let military = SourceOrigin(tier: .military, producer: "US Air Force", distributor: "NOAA Aviation Weather Center")
    let obsProv = prov(.aviationWeather, fetchedAt: now.addingTimeInterval(-300), origin: military, distance: 340)
    let obs = CurrentObservation(conditions: HourlyConditions(time: now), stationName: "KHIF (Hill AFB)", distanceKm: 340, age: 300, provenance: obsProv)
    let live = cLive(place, reading: cReading(score: 70, forecast: 60), at: now, current: obs, strip: strip)
    var report = cReport(place, windows: [], alerts: [WeatherAlert(id: "a", event: "Wind Advisory", severity: .moderate)])
    let hrrr = prov(.noaaNOMADS, fetchedAt: now.addingTimeInterval(-600))
    let met = prov(.metNorway, fetchedAt: now.addingTimeInterval(-900))
    report.fieldProvenance = [FieldProvenance(field: .cloudTotal, provenance: hrrr, contributors: [.noaaNOMADS]),
                              FieldProvenance(field: .cloudHigh, provenance: hrrr, contributors: [.noaaNOMADS]),
                              FieldProvenance(field: .precipChance, provenance: hrrr, contributors: [.noaaNOMADS]),
                              FieldProvenance(field: .windMs, provenance: met, contributors: [.metNorway])]
    return GoConditionsState(nextLive: live, nextReport: report, alerts: [GoAlertInfo(id: "a", event: "Wind Advisory", headline: nil, severity: "Moderate", ends: nil)],
                             conditionsAsOf: now.addingTimeInterval(-60))
}

@Test func builderFillsHoursFromTheNextStopsStrip() throws {
    let rig = RunRig()
    let now = RunFixture.h(8)
    let s = GoSnapshotBuilder.build(input(rig, now: now, conditions: s1Conditions(rig, now: now)))
    let hours = try #require(s.hours)
    #expect(hours.count == 6)
    #expect(hours.map(\.basis) == [.observation, .nowcast, .forecast, .forecast, .forecast, .forecast])
    #expect(hours[0].time == RunFixture.h(8) && hours[1].cloudTotal == 0.1)
    // The window is 10:00-11:00: only the 10:00 hour overlaps it.
    #expect(hours.map(\.isInWindow) == [false, false, true, false, false, false])
    #expect(hours[2].tempC == 5 && hours[2].windMs == 3 && hours[2].visibilityKm == 20)
}

@Test func builderOmitsHoursForAnotherStopsConditions() {
    let rig = RunRig()
    var c = s1Conditions(rig, now: RunFixture.h(8))
    c.nextLive?.placeID = rig.fx.s2.place.id
    let s = GoSnapshotBuilder.build(input(rig, now: RunFixture.h(8), conditions: c))
    #expect(s.hours == nil)
    #expect(s.sourceDetails?.contains { $0.role == "Observation" } != true)
}

@Test func builderFillsSourceDetailsBestTierFirst() throws {
    let rig = RunRig.driving(to: RunFixture().s1, now: RunFixture.h(8))
    let now = RunFixture.h(8).addingTimeInterval(600)
    let eta = ETA(seconds: 900, arrival: now.addingTimeInterval(900), departing: now)
    let facts = GoETAFacts(fetchedAt: now.addingTimeInterval(-30), meters: 12_345)
    let s = GoSnapshotBuilder.build(input(rig, now: now, conditions: s1Conditions(rig, now: now), eta: facts, etaLive: eta))
    let details = try #require(s.sourceDetails)
    let tiers = details.map(\.tier)
    #expect(tiers == tiers.sorted())
    let military = try #require(details.first)
    #expect(military.isMilitary && military.role == "Observation" && military.producer == "US Air Force" && military.distanceKm == 340)
    #expect(military.asOf == now.addingTimeInterval(-300))
    // Several fields from one source merge into one entry with each role once.
    let hrrr = try #require(details.first { $0.name == SourceCatalogue.noaaNOMADS.name })
    #expect(hrrr.role == "Cloud, Precipitation" && hrrr.tier == .government && hrrr.producer == "NOAA NCEP")
    #expect(details.filter { $0.name == SourceCatalogue.noaaNOMADS.name }.count == 1)
    #expect(details.contains { $0.role == "Wind" && $0.tier == .government })
    let maps = try #require(details.first { $0.name == "Apple Maps" })
    #expect(maps.role == "Drive time" && maps.asOf == now.addingTimeInterval(-30) && maps.tier == SourceCatalogue.appleDirections.tier)
    #expect(details.contains { $0.role == "Alerts" })
    #expect(details.allSatisfy { !$0.isStale })
}

@Test func builderMarksSourcesStaleWhenConditionsAre() throws {
    let rig = RunRig()
    var c = s1Conditions(rig, now: RunFixture.h(8))
    c.isStale = true
    let details = try #require(GoSnapshotBuilder.build(input(rig, now: RunFixture.h(8), conditions: c)).sourceDetails)
    #expect(!details.isEmpty && details.allSatisfy(\.isStale))
}

@Test func builderFillsScheduleAndHere() throws {
    let rig = RunRig()
    let now = RunFixture.h(8)
    let fix = rig.fx.fix(RunFixture.offset(RunFixture.origin, east: 3_000), at: now)
    let s = GoSnapshotBuilder.build(input(rig, now: now, fix: fix))
    let schedule = try #require(s.schedule)
    #expect(schedule.map(\.stop.name) == ["S1", "S2", "Hotel", "S3", "Way"])
    #expect(schedule.map(\.stop.number) == [1, 2, 3, 4, 5])
    #expect(schedule.count == s.remainingCount + 1)
    #expect(schedule[0].stop.id == s.next?.id && schedule[0].leaveBy == s.leave?.leaveBy && schedule[0].status == s.leave?.status)
    #expect(schedule[1].leaveBy != nil && schedule[1].arrival != nil)
    #expect(s.here == fix.coordinate)
    #expect(GoSnapshotBuilder.build(input(rig, now: now)).here == nil)
}

@Test func builderFillsSummaryWhenFinished() throws {
    var rig = RunRig(now: RunFixture.h(8))
    let fx = rig.fx
    rig.send(.user(.end), at: RunFixture.h(13))
    rig.run.visits[fx.s1.id] = StopVisit(stopID: fx.s1.id, status: .done, arrivedAt: RunFixture.h(9.7), leftAt: RunFixture.h(11))
    rig.run.visits[fx.s2.id] = StopVisit(stopID: fx.s2.id, status: .skipped)
    var c = GoConditionsState()
    c.memory.trends.record(stopID: fx.s1.id, kind: .goldenMorning, score: 77)
    let s = GoSnapshotBuilder.build(input(rig, now: RunFixture.h(13.1), conditions: c))
    #expect(s.phase == .finished && s.schedule == nil && s.hours == nil)
    let summary = try #require(s.summary)
    #expect(summary.stops.map(\.name) == ["S1", "S2", "Hotel", "S3", "Way"])
    #expect(summary.stops.map(\.outcome) == [.shot, .skipped, .missed, .missed, .missed])
    #expect(summary.stops[0].arrivedAt == RunFixture.h(9.7) && summary.stops[0].leftAt == RunFixture.h(11))
    #expect(summary.stops[0].score == 77 && summary.stops[1].score == nil)
    #expect(summary.stops[0].windowKind == .goldenMorning && summary.stops[2].windowKind == nil)
    #expect(summary.startedAt == RunFixture.h(8) && summary.endedAt == RunFixture.h(13))
    // A run still going has no summary.
    #expect(GoSnapshotBuilder.build(input(RunRig(), now: RunFixture.h(8))).summary == nil)
}

@Test func builderLeavesNewFieldsEmptyWithoutARun() {
    var i = input(RunRig(), now: RunFixture.h(8))
    i.run = nil
    let s = GoSnapshotBuilder.build(i)
    #expect(s.hours == nil && s.sourceDetails == nil && s.schedule == nil && s.here == nil && s.summary == nil)
}

@Test func snapshotWrittenWithoutTheNewKeysStillDecodes() throws {
    let rig = RunRig()
    let now = RunFixture.h(8)
    let full = GoSnapshotBuilder.build(input(rig, now: now, conditions: s1Conditions(rig, now: now),
                                             fix: rig.fx.fix(RunFixture.origin, at: now)))
    #expect(full.hours != nil && full.sourceDetails != nil && full.schedule != nil && full.here != nil)
    let data = try JSONEncoder().encode(full)
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    for key in ["hours", "sourceDetails", "schedule", "here", "summary"] { object.removeValue(forKey: key) }
    let old = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(GoSnapshot.self, from: old)
    #expect(decoded.hours == nil && decoded.sourceDetails == nil && decoded.schedule == nil && decoded.here == nil && decoded.summary == nil)
    #expect(decoded.next == full.next && decoded.leave == full.leave && decoded.sky == full.sky)
}
