import Foundation
import Testing
import IterModel
import IterSources
import IterConditions
import IterGo

private struct Rig {
    let clock = ManualClock(cT0)
    let fake = FakeConditions()
    let loop: ConditionsLoop
    let a = cStop("A", session: .goldenEvening)
    let b = cStop("B", session: .blueEvening, lat: 40.1)
    let c = cStop("C", session: .night, lat: 40.2)
    let trip: Trip

    @MainActor init() {
        let clock = self.clock
        fake.now = { clock.now }
        loop = ConditionsLoop(provider: fake, clock: clock)
        trip = cTrip([a, b, c])
    }

    func context(phase: GoPhase = .driving, next: Stop? = nil, today: [Stop]? = nil, fix: LocationFix? = cFix(),
                 power: PowerState = .normal) -> ConditionsContext {
        ConditionsContext(trip: trip, phase: phase, nextStop: next ?? a, todayRemaining: today ?? [a, b, c], fix: fix, power: power)
    }
}

@MainActor @Test func dueItemsRunSequentiallyInPriorityOrder() async {
    let r = Rig()
    r.fake.setLive(r.a.place.id, 70)
    r.fake.setReport(r.a.place.id, 65)
    r.fake.setReport(r.b.place.id, 50)
    r.fake.setReport(r.c.place.id, 50)
    let update = await r.loop.refreshIfDue(context: r.context())
    #expect(update.fetched == [.hereLive, .nextLive, .nextForecast, .todayForecast, .pack])
    let here = ConditionsLoop.herePlaceID
    #expect(r.fake.calls == [
        .live(here, nil, .onScreen),
        .live(r.a.place.id, .goldenEvening, .onScreen),
        .report(r.a.place.id, .onScreen),
        .report(r.b.place.id, .activeTrip),
        .report(r.c.place.id, .activeTrip),
        .pack(r.trip.id),
    ])
    #expect(update.requestCount == 6)
    #expect(update.state.sky?.basis == .blended && update.state.sky?.liveScore == 70)
    #expect(update.state.packBuiltAt == cT0)
    #expect(update.state.nextDueAt == cT0.addingTimeInterval(15 * 60))
}

@MainActor @Test func hereIsASyntheticPlaceAtTheFixInTheNextStopsZone() {
    let fix = cFix(lat: 41, lon: -105)
    let p = ConditionsLoop.herePlace(fix: fix, timeZoneIdentifier: "America/Chicago")
    #expect(p.name == "Here" && p.id == ConditionsLoop.herePlaceID && p.coordinate == fix.coordinate && p.timeZoneIdentifier == "America/Chicago")
}

@MainActor @Test func nothingFetchedUntilDueAgain() async {
    let r = Rig()
    _ = await r.loop.refreshIfDue(context: r.context())
    r.fake.clearCalls()
    r.clock.advance(by: 10 * 60)
    #expect(await r.loop.refreshIfDue(context: r.context()).fetched.isEmpty)
    r.clock.advance(by: 5 * 60)
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.fetched == [.nextLive])
    r.clock.advance(by: 15 * 60)
    #expect(await r.loop.refreshIfDue(context: r.context()).fetched == [.hereLive, .nextLive])
    r.clock.advance(by: 30 * 60)
    #expect(await r.loop.refreshIfDue(context: r.context()).fetched == [.hereLive, .nextLive, .nextForecast, .todayForecast])
}

@MainActor @Test func inactivePhasesDoNothing() async {
    let r = Rig()
    for phase in [GoPhase.idle, .paused, .finished] {
        let u = await r.loop.refreshIfDue(context: r.context(phase: phase))
        #expect(u.fetched.isEmpty && u.state.nextDueAt == nil)
    }
    #expect(r.fake.calls.isEmpty)
}

@MainActor @Test func nextStopChangeRefetchesAtOnceAndDropsOldData() async {
    let r = Rig()
    r.fake.setLive(r.a.place.id, 70)
    r.fake.setLive(r.b.place.id, nil)
    _ = await r.loop.refreshIfDue(context: r.context())
    r.fake.clearCalls()
    r.clock.advance(by: 60)
    let u = await r.loop.refreshIfDue(context: r.context(next: r.b, today: [r.b, r.c]))
    #expect(u.fetched == [.nextLive, .nextForecast])
    #expect(r.fake.calls == [.live(r.b.place.id, .blueEvening, .onScreen), .report(r.b.place.id, .onScreen)])
    #expect(u.state.sky?.stopID == r.b.id)
    #expect(u.state.nextLive?.placeID == r.b.place.id && u.state.nextReport?.placeID == r.b.place.id)
}

@MainActor @Test func hereLiveWhenStoppedOnlyAfterMovingFar() async {
    let r = Rig()
    _ = await r.loop.refreshIfDue(context: r.context(phase: .atStop))
    r.fake.clearCalls()
    r.clock.advance(by: 15 * 60)
    #expect(await r.loop.refreshIfDue(context: r.context(phase: .atStop)).fetched == [.nextLive])
    r.clock.advance(by: 60)
    let moved = await r.loop.refreshIfDue(context: r.context(phase: .atStop, fix: cFix(lat: 39.74 + 0.1)))
    #expect(moved.fetched == [.hereLive])
}

@MainActor @Test func noLiveScoreUsesNextWindowForecastWithTrendOverThreeRefreshes() async {
    let r = Rig()
    r.fake.setLive(r.a.place.id, nil)
    var trends: [GoTrend] = []
    for score in [60, 64, 68] {
        r.fake.setReport(r.a.place.id, score)
        let u = await r.loop.refreshIfDue(context: r.context())
        #expect(u.state.sky?.basis == .nextWindowForecast)
        #expect(u.state.sky?.forecastScore == score)
        trends.append(u.state.sky?.trend ?? .unknown)
        r.clock.advance(by: 60 * 60)
    }
    #expect(trends == [.unknown, .steady, .rising])
}

@MainActor @Test func noDataAtTheNextStop() async {
    let r = Rig()
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.state.sky?.basis == .noData && u.state.sky?.notice == "No live data")
}

@MainActor @Test func changesRaisedWhenTheNextStopsScoreMoves() async {
    let r = Rig()
    r.fake.setLive(r.a.place.id, 80)
    r.fake.setStrip(cStrip(highFirst: 0.1, highLast: 0.5, totalFirst: 0.3, totalLast: 0.6))
    var u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.state.changes.isEmpty)
    r.fake.setLive(r.a.place.id, 55)
    r.clock.advance(by: 15 * 60)
    u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.state.changes.count == 1)
    #expect(u.state.changes.first?.stopID == r.a.id && u.state.changes.first?.previous == 80 && u.state.changes.first?.current == 55)
    #expect(u.state.changes.first?.cause == "high cloud moving in")
    // The next refresh replaces the list.
    r.clock.advance(by: 15 * 60)
    #expect(await r.loop.refreshIfDue(context: r.context()).state.changes.isEmpty)
}

@MainActor @Test func todayStopsFeedChangeDetectionFromTheirForecast() async {
    let r = Rig()
    r.fake.setReport(r.b.place.id, 80)
    _ = await r.loop.refreshIfDue(context: r.context())
    r.fake.setReport(r.b.place.id, 40)
    r.clock.advance(by: 61 * 60)
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.state.changes.contains { $0.stopID == r.b.id && $0.previous == 80 && $0.current == 40 && $0.cause == "forecast updated" })
}

@MainActor @Test func offlineFlagFromAnOfflineReport() async {
    let r = Rig()
    #expect(await r.loop.refreshIfDue(context: r.context()).state.isOffline == false)
    r.fake.setOffline(true)
    r.clock.advance(by: 60 * 60)
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.state.isOffline)
}

@MainActor @Test func weatherAndAlertsAndFreshness() async {
    let r = Rig()
    r.fake.setLive(r.a.place.id, 70)
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.state.conditionsAsOf == cT0)
    #expect(!u.state.isStale)
    #expect(u.state.alerts.isEmpty)
    // Fakes carry no weather observations or forecast hours.
    #expect(u.state.weather.isEmpty)
    r.clock.advance(by: 20 * 60)
    #expect(await r.loop.refreshIfDue(context: r.context(phase: .atStop, fix: nil, power: .normal)).state.isStale == false)
    r.clock.advance(by: 30 * 60)
    // Nothing fetched in the last 50 minutes by a loop that is not asked: stale after 3 live intervals.
    let paused = await r.loop.refreshIfDue(context: r.context(phase: .paused))
    #expect(paused.fetched.isEmpty)
}

@MainActor @Test func packRefreshCadenceAndFailureTolerance() async {
    let r = Rig()
    r.fake.setPackFails(true)
    let built = await r.loop.refreshPack(trip: r.trip)
    #expect(built == nil)
    #expect(r.loop.state.packError != nil && r.loop.state.packBuiltAt == nil)
    // A failure is retried after 30 minutes, not 3 hours, and never thrown out of refreshIfDue.
    r.clock.advance(by: 29 * 60)
    #expect(!(await r.loop.refreshIfDue(context: r.context())).fetched.contains(.pack))
    r.clock.advance(by: 2 * 60)
    r.fake.setPackFails(false)
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(u.fetched.contains(.pack))
    #expect(u.state.packError == nil && u.state.packBuiltAt == r.clock.now)
    // Then every 3 hours.
    r.clock.advance(by: 3 * 3600 - 1)
    #expect(!(await r.loop.refreshIfDue(context: r.context())).fetched.contains(.pack))
    r.clock.advance(by: 1)
    #expect(await r.loop.refreshIfDue(context: r.context()).fetched.contains(.pack))
}

@MainActor @Test func runStartBuildsThePackOnceThenCadenceTakesOver() async {
    let r = Rig()
    let built = await r.loop.refreshPack(trip: r.trip)
    #expect(built == cT0)
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(!u.fetched.contains(.pack))
    #expect(r.fake.calls.filter { if case .pack = $0 { true } else { false } }.count == 1)
}

@MainActor @Test func anExistingPackIsNotRebuiltAtOnce() async {
    let r = Rig()
    r.fake.setPackBuilt(r.trip.id, cT0.addingTimeInterval(-3600))
    let u = await r.loop.refreshIfDue(context: r.context())
    #expect(!u.fetched.contains(.pack))
    #expect(u.state.packBuiltAt == cT0.addingTimeInterval(-3600))
}

@MainActor @Test func aSecondCallWhileOneRunsReturnsWithoutFetching() async {
    let r = Rig()
    let gate = Gate()
    r.fake.setGate(gate)
    let ctx = r.context()
    let loop = r.loop
    let first = Task { @MainActor in await loop.refreshIfDue(context: ctx) }
    while r.fake.calls.isEmpty { await Task.yield() }
    let second = await loop.refreshIfDue(context: ctx)
    #expect(second.skipped && second.fetched.isEmpty && second.requestCount == 0)
    #expect(await loop.refreshPack(trip: r.trip) == nil)
    gate.open()
    let done = await first.value
    #expect(!done.skipped && done.fetched.first == .hereLive)
    #expect(r.fake.calls.filter { $0 == .live(ConditionsLoop.herePlaceID, nil, .onScreen) }.count == 1)
}

@MainActor @Test func stateSurvivesARelaunch() async throws {
    let r = Rig()
    r.fake.setLive(r.a.place.id, 70)
    r.fake.setReport(r.a.place.id, 66)
    let u = await r.loop.refreshIfDue(context: r.context())
    let data = try JSONEncoder().encode(u.state)
    let restored = try JSONDecoder().decode(GoConditionsState.self, from: data)
    #expect(restored == u.state)
    let relaunched = ConditionsLoop(provider: r.fake, clock: r.clock)
    relaunched.restore(restored)
    r.fake.clearCalls()
    r.clock.advance(by: 60)
    let again = await relaunched.refreshIfDue(context: r.context())
    #expect(again.fetched.isEmpty)
    #expect(again.state.sky == u.state.sky)
}

@MainActor @Test func aDifferentTripResetsTheMemory() async {
    let r = Rig()
    _ = await r.loop.refreshIfDue(context: r.context())
    let other = cTrip([r.a])
    let ctx = ConditionsContext(trip: other, phase: .driving, nextStop: r.a, todayRemaining: [r.a], fix: cFix())
    let u = await r.loop.refreshIfDue(context: ctx)
    #expect(u.fetched == [.hereLive, .nextLive, .nextForecast, .todayForecast, .pack])
}
