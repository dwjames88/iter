import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel
import IterPlan

@MainActor
@Suite("Simulation, request budget") struct SimulationBudgetTests {
    /// A typical driving day: two long drives (87 min and 35 min), a shoot, a long wait, scores that move.
    @Test func typicalDrivingDay() async throws {
        let w = SimWorld([SimStopSpec(name: "S1", eastKm: 100, session: .goldenMorning, window: (10, 11)),
                          SimStopSpec(name: "S2", eastKm: 140, session: .goldenEvening, window: (17, 18))])
        let s1 = w.stop(0), s2 = w.stop(1)
        let h = SimHarness(w, start: simH(6))
        // S2 swings 45 -> 72 -> 40 -> 80 through the day, S1 stays put: change alerts must hold to one per stop per hour.
        h.conditions.setScore { place, at in
            if place == s2.place.id {
                let hour = at.timeIntervalSince(simT0) / 3600
                return hour < 9 ? 45 : hour < 12 ? 72 : hour < 12.4 ? 40 : 80
            }
            return 60
        }
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        h.feed(SimWorld.drive(from: w.home.coordinate, to: s1.place.coordinate, start: leave.addingTimeInterval(120)))
        await h.advance(to: simH(11).addingTimeInterval(120))
        let s2Leave = try #require(h.last.leave?.leaveBy)
        h.feed(SimWorld.drive(from: s1.place.coordinate, to: s2.place.coordinate, start: s2Leave.addingTimeInterval(120)))
        await h.advance(to: simH(18).addingTimeInterval(120))
        #expect(h.run?.phase == .finished)

        // Phase durations from the snapshots.
        var seconds: [GoPhase: TimeInterval] = [:]
        for (a, b) in zip(h.snapshots, h.snapshots.dropFirst()) { seconds[a.phase, default: 0] += b.generatedAt.timeIntervalSince(a.generatedAt) }
        let driveHours = (seconds[.driving] ?? 0) / 3600
        let waitHours = ((seconds[.armed] ?? 0) + (seconds[.atStop] ?? 0) + (seconds[.betweenStops] ?? 0)) / 3600
        let totalHours = (h.snapshots.last!.generatedAt.timeIntervalSince(h.snapshots.first!.generatedAt)) / 3600

        let log = h.etaRequests
        let driving = log.filter { $0.phase == .driving }.count
        let waiting = log.filter { $0.phase != .driving && $0.phase != nil }.count
        let waitingPhases: Set<GoPhase> = [.armed, .atStop, .betweenStops]
        let maxDriving = h.maxETARequests(phases: [.driving])
        let maxWaiting = h.maxETARequests(phases: waitingPhases)
        let maxAll = h.maxETARequests()
        let fetchItems = h.engine.conditionsFetchLog.reduce(0) { $0 + $1.items.count }
        let fetchRequests = h.engine.conditionsFetchLog.reduce(0) { $0 + $1.requestCount }
        let maxItems = h.maxConditionsItems()
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        print("BUDGET eta driving: \(driving) requests in \(f(driveHours)) h = \(f(Double(driving) / max(driveHours, 0.01)))/h; busiest driving hour \(maxDriving)")
        print("BUDGET eta waiting: \(waiting) requests in \(f(waitHours)) h = \(f(Double(waiting) / max(waitHours, 0.01)))/h; busiest waiting hour \(maxWaiting)")
        print("BUDGET eta overall: \(log.count) requests in \(f(totalHours)) h = \(f(Double(log.count) / totalHours))/h; busiest hour \(maxAll)")
        print("BUDGET conditions: \(fetchItems) fetch-items (\(fetchRequests) provider requests) in \(f(totalHours)) h = \(f(Double(fetchItems) / totalHours))/h; busiest hour \(maxItems) items")
        print("BUDGET provider calls: live \(h.conditions.liveCalls.count), report \(h.conditions.reportCalls.count), pack \(h.conditions.packCalls.count); router \(h.routing.calls)")

        #expect(maxDriving <= 25)
        // Cadence: next stop live every 15 min, its forecast and today's stops hourly, "here" every 30 min while driving: 6 an hour
        // parked, 8 driving; a next-stop change refetches at once, so the busiest rolling hour measures 11.
        #expect(maxItems <= 11)
        let parked = h.engine.conditionsFetchLog.filter { r in r.at > simH(9.3) && r.at < simH(15.7) }.reduce(0) { $0 + $1.items.count }
        #expect(Double(parked) / 6.4 <= 6.5)
        #expect(h.engine.maxETAInFlight == 1 && h.routing.maxRunning == 1)
        #expect(h.conditions.packCalls.count <= 5)   // once at start, then every 3 h

        // The hourly cap: at most one conditions notice per stop in any hour; the swings did raise some.
        let notices = h.immediates.filter { $0.request.kind == .conditionsChanged }
        #expect(!notices.isEmpty)
        for stop in [s1, s2] {
            let times = notices.filter { $0.request.stopID == stop.id }.map(\.at).sorted()
            for (a, b) in zip(times, times.dropFirst()) { #expect(b.timeIntervalSince(a) >= 3600) }
        }
        // And the Live Activity never updated faster than once a minute without a phase, status or next-stop change.
        let calls = h.activity.calls, times = h.activity.callTimes
        var lastUpdate: (Date, GoActivityContent)?
        for (call, at) in zip(calls, times) {
            guard case .update(let content, _) = call else { continue }
            if let (prevAt, prev) = lastUpdate, prev.phase == content.phase, prev.status == content.status, prev.nextStopName == content.nextStopName,
               (prev.undoExpiresAt != nil) == (content.undoExpiresAt != nil) {
                #expect(at.timeIntervalSince(prevAt) >= 60)
            }
            lastUpdate = (at, content)
        }
    }

    /// A deviation of more than a kilometre from the planned leg asks for a fresh route, once.
    @Test func deviationAsksForARoute() async throws {
        let w = SimWorld([SimStopSpec(name: "S1", eastKm: 60, session: .goldenMorning, window: (10, 11))])
        let h = SimHarness(w, start: simH(7))
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        let offLeg = (RunFixture.offset(w.home.coordinate, north: 3_000), RunFixture.offset(w.stop(0).place.coordinate, north: 3_000))
        h.feed(LocationTrace.fixes(along: [offLeg.0, offLeg.1], speedMs: 25, interval: 10, start: leave.addingTimeInterval(120)))
        await h.advance(to: leave.addingTimeInterval(1_200))
        let routes = h.etaRequests.filter { $0.kind == .route }
        #expect(routes.count >= 1 && routes.count <= 2)
        #expect(h.routing.routeCalls == routes.count)
        #expect(h.engine.maxETAInFlight == 1)
    }

    /// Parked for over five minutes while "driving" (a fuel stop): the cadence relaxes to 6 minutes.
    @Test func stationaryRelaxesTheCadence() async throws {
        let w = SimWorld([SimStopSpec(name: "S1", eastKm: 60, session: .goldenMorning, window: (10, 11))])
        let h = SimHarness(w, start: simH(7))
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        await h.advance(to: leave.addingTimeInterval(60))
        let from = RunFixture.offset(w.home.coordinate, east: 800)
        h.feed(LocationTrace.stationary(at: from, duration: 40 * 60, interval: 10, start: leave.addingTimeInterval(90)))
        await h.advance(to: leave.addingTimeInterval(45 * 60))
        #expect(h.run?.phase == .driving)
        let late = h.etaRequests.filter { $0.start > leave.addingTimeInterval(15 * 60) }.map(\.start)
        #expect(late.count >= 3)
        for (a, b) in zip(late, late.dropFirst()) { #expect(b.timeIntervalSince(a) >= 6 * 60 - 1) }
    }

    /// Pausing silences everything; ending turns everything off and clears what was kept.
    @Test func pauseAndEndTearDown() async throws {
        let w = simDay()
        let h = SimHarness(w)
        await h.start()
        #expect(!h.notifications.pending.isEmpty)
        await h.perform(.pause)
        #expect(h.last.phase == .paused && h.notifications.pending.isEmpty)
        #expect(h.location.currentMode == .off)
        let calls = h.notifications.calls.count
        await h.advance(by: 600)   // paused ticks do not keep telling the system to remove everything
        #expect(h.notifications.calls.count == calls)
        await h.perform(.resume)
        #expect(!h.notifications.pending.isEmpty)
        let runID = try #require(h.run?.id)
        #expect(h.engineState.load(runID: runID) != nil)
        await h.perform(.end)
        #expect(h.last.phase == .finished && h.notifications.pending.isEmpty)
        #expect(h.engineState.load(runID: runID) == nil)
        #expect(h.persistence.activeRun(tripID: w.trip.id) == nil)
        #expect(h.location.currentMode == .off)
        #expect(h.background.calls.last == .cancel)
        if case .end = h.activity.calls.last { } else { Issue.record("activity not ended") }
    }
}
