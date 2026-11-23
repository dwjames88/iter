import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel
import IterPlan

/// A day of two light stops: S1 at sunrise (10:00-11:00), S2 at sunset (17:00-18:00), 20 km apart on a straight road.
func simDay() -> SimWorld {
    SimWorld([SimStopSpec(name: "S1", eastKm: 20, session: .goldenMorning, window: (10, 11)),
              SimStopSpec(name: "S2", eastKm: 40, session: .goldenEvening, window: (17, 18))])
}

@MainActor
@Suite("Simulation") struct SimulationScenarioTests {
    // 1. A normal day.
    @Test func normalDay() async throws {
        let w = simDay()
        let h = SimHarness(w)
        await h.start()
        #expect(h.last.phase == .armed)
        // Four alarms from the start: leave-soon and leave-now for each stop.
        #expect(Set(h.notifications.pending.keys) == Set(w.stops.flatMap { [AlarmPlan.id(for: $0.id, kind: .leaveSoon), AlarmPlan.id(for: $0.id, kind: .leaveNow)] }))
        let s1Leave = try #require(h.last.leave?.leaveBy)
        #expect(h.notifications.pending[AlarmPlan.id(for: w.stop(0).id, kind: .leaveNow)]?.fireAt == s1Leave)
        #expect(h.activity.calls.count == 1)   // started: within 8 h of the first leave-by

        // The user sets off 4 minutes after the time-based departure and drives to S1.
        let setOff = s1Leave.addingTimeInterval(240)
        h.feed(SimWorld.drive(from: w.home.coordinate, to: w.stop(0).place.coordinate, start: setOff))
        await h.advance(to: simH(10.5))
        #expect(h.run?.phase == .atStop)
        #expect(h.last.current?.name == "S1")
        #expect(h.last.stay?.nextStopName == "S2")
        // The window ends at 11:00: automatic between-stops with an undo.
        await h.advance(to: simH(11).addingTimeInterval(60))
        #expect(h.run?.phase == .betweenStops)
        #expect(h.last.undo?.toPhase == .betweenStops)
        await h.advance(to: simH(11).addingTimeInterval(200))
        #expect(h.last.undo == nil)

        let s2Leave = try #require(h.last.leave?.leaveBy)
        h.feed(SimWorld.drive(from: w.stop(0).place.coordinate, to: w.stop(1).place.coordinate, start: s2Leave.addingTimeInterval(240)))
        await h.advance(to: simH(17.5))
        #expect(h.run?.phase == .atStop)
        await h.advance(to: simH(18).addingTimeInterval(120))
        #expect(h.run?.phase == .finished)

        #expect(h.phases == [.armed, .driving, .atStop, .betweenStops, .driving, .atStop, .finished])
        // Each alarm rang exactly once.
        for kind in [GoNotificationKind.leaveSoon, .leaveNow] {
            for i in 0..<2 { #expect(h.firedRequests(kind, stop: i).count == 1, "\(kind) \(i)") }
        }
        // One arrival notification per automatic geofence arrival, and nothing late or missed.
        #expect(h.immediates.filter { $0.request.kind == .arrival }.count == 2)
        #expect(h.firedRequests(.late).isEmpty && h.firedRequests(.missed).isEmpty)
        // One request at a time; the budget holds.
        #expect(h.routing.maxRunning == 1 && h.engine.maxETAInFlight == 1)
        #expect(h.maxETARequests(phases: [.driving]) <= 25)
        // Live Activity: started once, ended with the finished state.
        let calls = h.activity.calls
        if case .start = calls.first {} else { Issue.record("first activity call is not start") }
        if case .end(let content, _) = calls.last { #expect(content.phase == .finished) } else { Issue.record("last activity call is not end") }
        #expect(h.store.read()?.phase == .finished)
        #expect(h.snapshots.contains { $0.phase == .driving && $0.drive?.source == .live })
        #expect(h.background.calls.last == .cancel)
    }

    // 2. Traffic pushes leave-by earlier, then into the past.
    @Test func trafficMovesLeaveBy() async throws {
        let w = simDay()
        let h = SimHarness(w)
        let knob = SimKnob(1)
        h.routing.setTraffic { a, b, _ in SimWorld.driveSeconds(a, b) * knob.value }
        // The traveller dawdles at home with the phone awake: fixes keep coming, none moves.
        h.feed(LocationTrace.stationary(at: w.home.coordinate, duration: 4 * 3600, interval: 60, start: simH(8)))
        await h.start()
        let leaveNowID = AlarmPlan.id(for: w.stop(0).id, kind: .leaveNow)
        let soonID = AlarmPlan.id(for: w.stop(0).id, kind: .leaveSoon)
        let original = try #require(h.notifications.pending[leaveNowID]?.fireAt)
        await h.advance(to: simH(8.5))

        // Traffic doubles: the pending alarms move earlier under the same ids.
        knob.value = 2
        await h.advance(by: 7 * 60)
        let moved = try #require(h.notifications.pending[leaveNowID]?.fireAt)
        #expect(moved < original.addingTimeInterval(-15 * 60))
        #expect(h.notifications.pending[soonID]?.fireAt == moved.addingTimeInterval(-15 * 60))
        #expect(h.adds(.leaveNow, stop: 0).map(\.request.id).allSatisfy { $0 == leaveNowID })
        #expect(h.adds(.leaveNow, stop: 0).count >= 2)
        #expect(h.immediates.isEmpty)

        // Traffic jumps so that leave-by is already behind us but we can still make set-up: one immediate leave-now.
        await h.advance(to: simH(8.8))
        knob.value = 2.52
        await h.advance(by: 6 * 60)
        let leaveNows = h.immediates.filter { $0.request.kind == .leaveNow }
        #expect(leaveNows.count == 1)
        #expect(h.notifications.pending[leaveNowID] == nil)

        // Then worse: late. One late notification, once.
        knob.value = 3.6
        await h.advance(by: 15 * 60)
        #expect(h.last.leave?.status == .late)
        #expect(h.immediates.filter { $0.request.kind == .late }.count == 1)
        #expect(h.immediates.filter { $0.request.kind == .leaveNow }.count == 1)
        await h.advance(by: 20 * 60)
        #expect(h.immediates.filter { $0.request.kind == .late }.count == 1)
        #expect(h.immediates.count == 2)
        #expect(h.last.alternative?.name == "S2")
    }

    // 3a. Arriving early.
    @Test func arrivingEarly() async throws {
        let w = simDay()
        let h = SimHarness(w)
        await h.start()
        let setOff = simH(8.5)
        await h.advance(to: setOff)
        h.feed(SimWorld.drive(from: w.home.coordinate, to: w.stop(0).place.coordinate, start: setOff))
        await h.advance(to: setOff.addingTimeInterval(300))
        // Left by motion, well before leave-by: the card counts down.
        #expect(h.run?.phase == .driving)
        #expect(h.last.leave?.status == .early)
        #expect(h.last.next?.setUpBy == simH(10).addingTimeInterval(-20 * 60))
        let arrival = try #require(h.last.drive?.arrival)
        #expect(arrival < simH(9))
        await h.advance(to: simH(9.2))
        #expect(h.run?.phase == .atStop)
        #expect(h.last.current?.setUpBy == simH(10).addingTimeInterval(-20 * 60))
        #expect(h.firedRequests(.late).isEmpty)
        // Still no leave alarm for S1 once we are there.
        #expect(h.notifications.pending[AlarmPlan.id(for: w.stop(0).id, kind: .leaveNow)] == nil)
    }

    // 3b. Arriving late: one late notification, the alternative shown.
    @Test func arrivingLate() async throws {
        let w = simDay()
        let h = SimHarness(w)
        await h.start()
        let leave = try #require(h.last.leave?.leaveBy)
        // Set off 25 minutes after leave-by, by hand.
        await h.advance(to: leave.addingTimeInterval(-60))
        await h.perform(.leaveNow)
        await h.advance(by: 60)
        h.feed(SimWorld.drive(from: w.home.coordinate, to: w.stop(0).place.coordinate, start: leave.addingTimeInterval(25 * 60)))
        await h.advance(to: leave.addingTimeInterval(26 * 60))
        // The user pressed "Leave now" a minute early and then sat for 25 minutes: the ETA lapses into late.
        let late = h.snapshots.last { $0.leave?.status == .late }
        #expect(late != nil)
        #expect(late?.alternative?.name == "S2")
        await h.advance(to: simH(10.5))
        #expect(h.firedRequests(.late, stop: 0).count == 1)
        #expect(h.run?.phase == .atStop)
    }

    // 4. Staying past the window: the next stop's leave-by passes mid-shoot.
    @Test func stayingPastTheWindow() async throws {
        let w = SimWorld([SimStopSpec(name: "S1", eastKm: 20, session: .goldenMorning, window: (10, 11.5)),
                          SimStopSpec(name: "S2", eastKm: 40, session: .blueMorning, window: (11.75, 12.5))])
        let h = SimHarness(w)
        await h.start()
        h.feed(SimWorld.drive(from: w.home.coordinate, to: w.stop(0).place.coordinate, start: simH(9.2)))
        await h.advance(to: simH(10.2))
        #expect(h.run?.phase == .atStop)
        let stay = try #require(h.last.stay)
        #expect((stay.cutsShortBySeconds ?? 0) > 10 * 60)
        // No leave alarms for S2 while the conflict stands; one stay-check.
        #expect(h.notifications.pending[AlarmPlan.id(for: w.stop(1).id, kind: .leaveNow)] == nil)
        #expect(h.notifications.pending[GoNotificationKind.stayCheck.id(for: w.stop(1).id)] != nil)
        await h.advance(to: simH(11.45))
        #expect(h.firedRequests(.stayCheck).count == 1)
        #expect(h.firedRequests(.leaveNow, stop: 1).isEmpty && h.firedRequests(.leaveSoon, stop: 1).isEmpty)
        #expect(h.firedRequests(.late).isEmpty && h.immediates.filter { $0.request.kind != .arrival }.isEmpty)
        // The window ends. By then the next stop is overdue, so the run chains on by itself (between stops, then driving), with an
        // undo. The user stays put and taps Not yet. The overdue stop is announced once, as late, and nothing else is.
        await h.advance(to: simH(11.5).addingTimeInterval(60))
        #expect(h.run?.phase == .driving)
        #expect(h.last.undo?.toPhase == .driving)
        #expect(h.immediates.filter { $0.request.kind == .late }.count == 1)
        await h.perform(.notYet)
        #expect(h.run?.phase == .betweenStops)
        await h.advance(to: simH(12.5))
        #expect(h.run?.phase == .betweenStops)
        #expect(h.firedRequests(.stayCheck).count == 1)
        #expect(h.firedRequests(.leaveNow, stop: 1).isEmpty)
        #expect(h.firedRequests(.late).count == 1)
        // Once the stop's window can no longer be made it is announced once as missed; nothing else.
        #expect(h.immediates.filter { $0.request.kind != .arrival && $0.request.kind != .late && $0.request.kind != .missed }.isEmpty)
        #expect(h.firedRequests(.missed).count == 1)
    }

    // 5. Skipping a stop while an ETA is in flight.
    @Test func skippingAStop() async throws {
        let w = SimWorld([SimStopSpec(name: "S1", eastKm: 20, session: .goldenMorning, window: (10, 11)),
                          SimStopSpec(name: "S2", eastKm: 40, session: .goldenEvening, window: (17, 18)),
                          SimStopSpec(name: "S3", eastKm: 60, session: .blueEvening, window: (18.7, 19.2))])
        let h = SimHarness(w)
        await h.start()
        await h.advance(to: simH(9))
        let s1Alarms = [AlarmPlan.id(for: w.stop(0).id, kind: .leaveSoon), AlarmPlan.id(for: w.stop(0).id, kind: .leaveNow)]
        #expect(s1Alarms.allSatisfy { h.notifications.pending[$0] != nil })
        // Hold the router: an ETA request is in flight and stays the only one.
        h.routing.setHold(true)
        let callsBefore = h.routing.calls, logBefore = h.engine.etaRequestLog.count
        h.clock.advance(by: 40)
        await h.engine.foreground()
        for _ in 0..<50 where h.routing.heldCount == 0 { await Task.yield() }
        #expect(h.routing.heldCount == 1)
        h.clock.advance(by: 40)
        await h.engine.tick()
        await h.engine.foreground()
        for _ in 0..<20 { await Task.yield() }
        #expect(h.routing.heldCount == 1 && h.routing.calls == callsBefore + 1)
        #expect(h.engine.etaRequestLog.count == logBefore + 1 && h.engine.etaRequestLog.last?.finishedAt == nil)

        await h.engine.perform(.skip(w.stop(0).id))
        h.routing.release()
        await h.engine.settle()
        #expect(h.run?.status(of: w.stop(0).id) == .skipped)
        #expect(h.last.next?.name == "S2")
        // The request about S1 was cancelled (never finished); the one about S2 went through.
        #expect(h.engine.etaRequestLog[logBefore].finishedAt == nil)
        #expect(h.engine.maxETAInFlight == 1)
        #expect(h.engine.liveETA?.stopID == w.stop(1).id)
        // Its alarms are gone, the next stop's remain.
        #expect(s1Alarms.allSatisfy { h.notifications.pending[$0] == nil })
        #expect(h.notifications.pending[AlarmPlan.id(for: w.stop(1).id, kind: .leaveNow)] != nil)
    }
}
