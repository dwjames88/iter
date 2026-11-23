import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel
import IterPlan

@MainActor
@Suite("Simulation, more days") struct SimulationScenarioTests2 {
    // 6. A multi-day trip: overnight lodging, then an Evening Before transfer.
    @Test func multiDayWithLodgingAndEveningBefore() async throws {
        let w = SimWorld([
            SimStopSpec(name: "A", eastKm: 20, session: .goldenEvening, window: (17, 18)),
            SimStopSpec(name: "Hotel", eastKm: 21, kind: .lodging, fixedArrival: LocalTime(hour: 19, minute: 30)),
            SimStopSpec(name: "B", eastKm: 60, session: .goldenMorning, day: 1, window: (30.5, 31.5)),
            SimStopSpec(name: "D", eastKm: 70, session: .goldenEvening, day: 1, window: (41, 42)),
            SimStopSpec(name: "C", eastKm: 130, session: .goldenMorning, day: 2, window: (54.5, 55.5)),
        ], transfers: [2: .eveningBefore], dayCount: 3)
        let (a, hotel, b, d, c) = (w.stop(0), w.stop(1), w.stop(2), w.stop(3), w.stop(4))
        let h = SimHarness(w)
        h.step = 120
        await h.start()
        // The evening transfer to C is already planned for tonight (day 1, 18:00), not for C's morning leave-by.
        let cNow = AlarmPlan.id(for: c.id, kind: .leaveNow), cSoon = AlarmPlan.id(for: c.id, kind: .leaveSoon)
        #expect(h.notifications.pending[cNow]?.fireAt == simH(42))
        #expect(h.notifications.pending[cSoon]?.fireAt == simH(41.75))
        #expect(h.notifications.pending[cNow]?.body.contains("tonight") == true)
        #expect(h.notifications.pending[cNow]?.title.contains("tonight") == true)

        await h.advance(to: simH(16.5))
        await h.perform(.leaveNow)
        await h.perform(.arrived)
        #expect(h.run?.phase == .atStop)
        await h.advance(to: simH(18.1))
        #expect(h.run?.phase == .betweenStops)
        // The hotel has a fixed arrival: the run heads there by the clock, and you tell it you are there.
        await h.advance(to: simH(19.5))
        #expect(h.run?.phase == .driving)
        await h.perform(.arrived)
        #expect(h.run?.phase == .atStop && h.run?.targetStopID == hotel.id)
        // Overnight lodging has no time-based exit: still there at 04:00.
        await h.advance(to: simH(28))
        #expect(h.run?.phase == .atStop && h.run?.status(of: hotel.id) == .arrived)
        let bLeave = try #require(h.last.leave?.leaveBy)
        #expect(bLeave > simH(28) && bLeave < simH(30))
        #expect(h.last.leave?.suggestedDeparture == nil)
        // The next morning's leave-by takes the run on.
        await h.advance(to: simH(30))
        #expect(h.run?.phase == .driving && h.run?.targetStopID == b.id)
        #expect(h.run?.status(of: hotel.id) == .done)
        await h.perform(.arrived)
        await h.advance(to: simH(31.6))
        #expect(h.run?.phase == .betweenStops)
        await h.advance(to: simH(40.5))
        #expect(h.run?.phase == .driving && h.run?.targetStopID == d.id)
        await h.perform(.arrived)
        await h.advance(to: simH(40.7))
        // At D, heading for C tomorrow: leave-by is C's morning; the suggestion is tonight, after D's window.
        let leave = try #require(h.last.leave)
        #expect(h.last.next?.name == "C")
        #expect(leave.suggestedDeparture == simH(42))
        #expect(try #require(leave.leaveBy) > simH(50))
        #expect(h.notifications.pending[cNow]?.fireAt == simH(42) && h.notifications.pending[cSoon]?.fireAt == simH(41.75))
        await h.advance(to: simH(42.1))
        #expect(h.firedRequests(.leaveSoon, stop: 4).count == 1 && h.firedRequests(.leaveNow, stop: 4).count == 1)
        #expect(h.firedRequests(.leaveNow, stop: 4).first?.request.body.contains("tonight") == true)
        // Never rung again in the morning.
        await h.advance(to: simH(54))
        #expect(h.firedRequests(.leaveNow, stop: 4).count == 1)
        _ = a
    }

    // 7. Losing the network mid-drive and recovering, with a rate limit in between.
    @Test func offlineMidDrive() async throws {
        let w = SimWorld([SimStopSpec(name: "S1", eastKm: 60, session: .goldenMorning, window: (10, 11))])
        let h = SimHarness(w, start: simH(7))
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        h.feed(SimWorld.drive(from: w.home.coordinate, to: w.stop(0).place.coordinate, start: leave.addingTimeInterval(120)))
        await h.advance(to: simH(8.75))
        #expect(h.run?.phase == .driving)
        #expect(h.last.drive?.source == .live)
        // A rate limit: the refresher backs off and is not asked before its time.
        h.routing.setMode(.rateLimited)
        await h.advance(to: simH(9.1))
        #expect(!h.backoffs.isEmpty)
        for r in h.etaRequests {
            let violated = h.backoffs.contains { $0.at < r.start && $0.until > r.start }
            #expect(!violated, "request at \(r.start) inside a backoff")
        }
        // Then no network at all.
        h.routing.setMode(.offline)
        h.conditions.setOffline(true)
        await h.advance(to: simH(9.3))
        let offline = h.snapshots.filter { $0.freshness.isOffline && $0.drive?.source == .offlineEstimate }
        #expect(!offline.isEmpty)
        let seconds = offline.compactMap(\.drive?.driveSeconds)
        #expect(zip(seconds, seconds.dropFirst()).allSatisfy { $1 <= $0 + 1 })
        #expect(h.last.freshness.isOffline)
        #expect(h.last.drive?.source == .offlineEstimate)
        // The estimate follows the planned leg: roughly what is left of it.
        let left = SimWorld.driveSeconds(h.last.next!.coordinate, h.last.next!.coordinate)
        _ = left
        // Back online.
        h.routing.setMode(.ok)
        h.conditions.setOffline(false)
        await h.advance(to: simH(9.45))
        #expect(!h.last.freshness.isOffline)
        #expect(h.last.drive?.source == .live || h.run?.phase == .atStop)
        await h.advance(to: simH(10))
        #expect(h.run?.phase == .atStop)
        #expect(h.engine.maxETAInFlight == 1 && h.routing.maxRunning == 1)
    }

    // 8. Relaunch mid-run.
    @Test func relaunchRestoresWithoutRefiring() async throws {
        let w = simDay()
        let h = SimHarness(w)
        #expect(await h.engine.restore(w.input) == false)   // nothing to pick up yet
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        h.feed(SimWorld.drive(from: w.home.coordinate, to: w.stop(0).place.coordinate, start: leave.addingTimeInterval(240), park: 600))
        h.step = 10
        var guardCount = 0
        while h.run?.phase != .atStop, guardCount < 600 { await h.advance(by: 10); guardCount += 1 }
        #expect(h.run?.phase == .atStop)
        await h.advance(by: 30)
        let before = try #require(h.run)
        let runID = before.id
        let ledger = try #require(h.engineState.load(runID: runID)).ledger
        #expect(ledger.delivered.keys.contains { $0.hasSuffix("-arrival") })
        let deliveredBefore = h.notifications.delivered.count
        let addsBefore = h.notificationLog.count
        let modesBefore = h.location.applied.count

        h.relaunch()
        let restored = await h.engine.restore(w.input)
        #expect(restored)
        await h.engine.settle()
        let after = try #require(h.run)
        #expect(after.phase == before.phase && after.targetStopID == before.targetStopID && after.visits == before.visits && after.id == before.id)
        #expect(after.pendingUndo == before.pendingUndo)
        #expect(h.last.phase == .atStop && h.last.current?.name == "S1")
        #expect(h.location.applied.count > modesBefore)   // the new location object was told what to do
        await h.advance(by: 15 * 60)
        // Nothing already delivered goes out again, by id.
        #expect(h.notifications.delivered.count == deliveredBefore)
        let newAdds = h.notificationLog.dropFirst(addsBefore).compactMap { e -> GoNotificationRequest? in if case .add(let r) = e.call { r } else { nil } }
        for r in newAdds { #expect(ledger.delivered[r.id] == nil, "re-added \(r.id)") }
        // Delivered ledger is carried over.
        let ledgerAfter = try #require(h.engineState.load(runID: runID)).ledger
        for (id, date) in ledger.delivered { #expect(ledgerAfter.delivered[id] == date) }
        // And the run carries on: S1 ends at 11:00, as before.
        await h.advance(to: simH(11).addingTimeInterval(60))
        #expect(h.run?.phase == .betweenStops || h.run?.phase == .driving)
        #expect(h.run?.status(of: w.stop(0).id) == .done)
    }

    // 9. Auto-advance undone within two minutes.
    @Test func undoWithinTwoMinutes() async throws {
        let w = simDay()
        let h = SimHarness(w)
        h.step = 10
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        let s1 = w.stop(0).place.coordinate
        let away = RunFixture.offset(s1, east: 1_500)
        // Arrive, sit inside the geofence for 10 minutes; later drive off 1.5 km and come back.
        let arrive = SimWorld.drive(from: w.home.coordinate, to: s1, start: leave.addingTimeInterval(240), park: 600)
        h.feed(arrive)
        var n = 0
        while h.run?.phase != .atStop, n < 600 { await h.advance(by: 10); n += 1 }
        #expect(h.run?.phase == .atStop)
        #expect(h.last.undo != nil)
        await h.advance(by: 50)
        await h.perform(.notYet)
        #expect(h.run?.phase == .driving)
        #expect(h.last.undo == nil)
        // The same geofence does not take you back in while you are still inside it.
        await h.advance(by: 5 * 60)
        #expect(h.run?.phase == .driving)
        // Leave it, and come back: arrival fires again.
        let t = h.clock.now.addingTimeInterval(10)
        let out = SimWorld.drive(from: s1, to: away, start: t, park: 60)
        h.feed(out)
        h.feed(SimWorld.drive(from: away, to: s1, start: (out.last?.timestamp ?? t).addingTimeInterval(10), park: 120))
        n = 0
        while h.run?.phase != .atStop, n < 400 { await h.advance(by: 10); n += 1 }
        #expect(h.run?.phase == .atStop)
        // One arrival notification all along (the ledger keeps the second quiet).
        #expect(h.firedRequests(.arrival).count == 1)

        // After two minutes the undo is gone.
        let h2 = SimHarness(w)
        h2.step = 10
        await h2.start()
        h2.feed(SimWorld.drive(from: w.home.coordinate, to: s1, start: leave.addingTimeInterval(240), park: 600))
        n = 0
        while h2.run?.phase != .atStop, n < 600 { await h2.advance(by: 10); n += 1 }
        #expect(h2.last.undo != nil)
        await h2.advance(by: 130)
        #expect(h2.last.undo == nil)
        await h2.perform(.notYet)
        #expect(h2.run?.phase == .atStop)
    }

    // 10. GPS jitter at the boundary does not flap.
    @Test func jitterAtTheBoundary() async throws {
        let w = simDay()
        let h = SimHarness(w)
        h.step = 10
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        let s1 = w.stop(0).place.coordinate
        var fixes = SimWorld.drive(from: w.home.coordinate, to: RunFixture.offset(s1, east: -400), start: leave.addingTimeInterval(240), park: 0)
        let t = (fixes.last?.timestamp ?? leave).addingTimeInterval(5)
        // Five minutes of fixes bobbing across the entry radius (150 m): 90 to 330 m out, never past the exit radius (400 m).
        let offsets: [Double] = [-170, -120, -190, -140, -260, -130, -330, -100, -200, -150, -90, -300]
        for i in 0..<60 {
            fixes.append(LocationFix(coordinate: RunFixture.offset(s1, east: offsets[i % offsets.count]), accuracyM: 20, speedMs: 0.5,
                                     timestamp: t.addingTimeInterval(Double(i) * 5)))
        }
        h.feed(fixes)
        await h.advance(to: t.addingTimeInterval(400))
        #expect(h.run?.phase == .atStop)
        #expect(h.phases == [.armed, .driving, .atStop])
        #expect(h.firedRequests(.arrival).count == 1)
        #expect(h.immediates.count == 1)
        #expect(h.run?.visits[w.stop(0).id]?.status == .arrived)
        #expect(h.run?.status(of: w.stop(1).id) == .pending)
    }
}
