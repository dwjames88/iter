import Foundation
import Testing
import IterGo
import IterGoActivity
import IterModel
import IterPlan

/// Go starts from the legs Build already worked out: planned times at once, no routing call for a leg it has, live ETAs
/// replace them only as they arrive, and a missing leg is the only thing Go routes.
@MainActor
@Suite("Planned legs in Go") struct PlannedLegsGoTests {
    @Test func storedLegsMeanNoRoutingAtStartAndPlannedTimesShow() async throws {
        let w = simDay()
        let h = SimHarness(w)
        await h.start()
        #expect(h.routing.calls == 0)
        #expect(h.last.phase == .armed)
        let planned = try #require(w.plannedLegs[LegKey(w.home.id, w.stop(0).id)])
        let drive = try #require(h.last.drive)
        #expect(drive.source == .planned)
        #expect(abs(drive.driveSeconds - planned.seconds) < 1)
        #expect(h.last.leave?.leaveBy != nil)
        #expect(h.last.next?.id == w.stop(0).id)
    }

    @Test func offlineStillHasPlannedTimes() async throws {
        let w = simDay()
        let h = SimHarness(w)
        h.routing.setOffline(true)
        await h.start()
        let leaveBy = try #require(h.last.leave?.leaveBy)
        // Run until the live request is due (30-60 min before leave-by it is every 5 minutes) and fails offline.
        await h.advance(to: leaveBy.addingTimeInterval(-25 * 60))
        #expect(h.routing.calls >= 1)
        #expect(h.last.freshness.isOffline)
        let planned = try #require(w.plannedLegs[LegKey(w.home.id, w.stop(0).id)])
        let drive = try #require(h.last.drive)
        #expect(abs(drive.driveSeconds - planned.seconds) < 1, "the planned drive time is still what Go shows")
        #expect(h.last.leave?.leaveBy == leaveBy, "and the leave-by did not move")
        #expect(h.routing.maxRunning <= 1)
    }

    @Test func aMissingLegIsRoutedOnceAndOnlyThatLeg() async throws {
        var w = simDay()
        // The leg into S1 is missing; the one into S2 is there.
        w.plannedLegs[LegKey(w.home.id, w.stop(0).id)] = nil
        let h = SimHarness(w)
        await h.start()
        #expect(h.routing.etaCalls == 1)
        #expect(h.routing.routeCalls == 0)
        #expect(h.last.drive?.source == .live)
        // Nothing else is asked about: the next ETA waits for its cadence.
        await h.advance(by: 60)
        #expect(h.routing.calls == 1)
        #expect(h.routing.maxRunning == 1)
    }

    @Test func aLiveEtaReplacesThePlannedOneOnlyWhenItArrives() async throws {
        let w = simDay()
        let h = SimHarness(w)
        await h.start()
        #expect(h.last.drive?.source == .planned)
        let leaveBy = try #require(h.last.leave?.leaveBy)
        h.routing.setTraffic { a, b, _ in SimWorld.driveSeconds(a, b) * 1.5 }
        await h.advance(to: leaveBy.addingTimeInterval(-28 * 60))
        #expect(h.routing.calls >= 1)
        #expect(h.last.drive?.source == .live)
        let planned = try #require(w.plannedLegs[LegKey(w.home.id, w.stop(0).id)])
        #expect(try #require(h.last.drive).driveSeconds > planned.seconds * 1.4)
        #expect(h.routing.maxRunning == 1)
    }

    @Test func aLegThatStartsFarFromTheTravellerIsNotTaken() async throws {
        let w = simDay()
        let h = SimHarness(w)
        // The traveller is 80 km from where the stored leg starts: the plan says nothing about their drive, so ask from here.
        let far = RunFixture.offset(w.home.coordinate, east: -80_000)
        await h.start()
        #expect(h.routing.calls == 0)
        h.feed([LocationFix(coordinate: far, accuracyM: 5, speedMs: 0, courseDeg: nil, timestamp: h.clock.now.addingTimeInterval(10))])
        await h.advance(by: 60)
        #expect(h.routing.etaCalls == 1)
        #expect(h.routing.maxRunning == 1)
    }
}
