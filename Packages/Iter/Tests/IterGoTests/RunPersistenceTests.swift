import Foundation
import Testing
import IterGo
import IterModel
import IterPlan

private func h(_ x: Double) -> Date { RunFixture.h(x) }

@MainActor
@Suite struct RunPersistenceTests {
    /// Persists a run the way the engine does after each handled event, then rebuilds it as a relaunch would.
    private func relaunch(_ run: TripRun, now: Date, store: InMemoryRunPersistence = InMemoryRunPersistence()) -> TripRun? {
        store.save(run.persisted)
        store.saveSidecar(run.sidecar, runID: run.id)
        guard let stored = store.activeRun(tripID: run.tripID) else { return nil }
        return TripRun.restore(from: stored, sidecar: store.loadSidecar(runID: run.id), now: now)
    }

    @Test func armedRoundTrips() {
        let rig = RunRig(at: RunFixture().s2)
        #expect(rig.run.persisted.stateRaw == "armed")
        #expect(relaunch(rig.run, now: h(8)) == rig.run)
    }

    @Test func drivingRoundTrips() {
        let rig = RunRig.driving(to: RunFixture().s1)
        #expect(rig.run.persisted.stateRaw == "active")
        #expect(rig.run.persisted.currentStopID == rig.fx.s1.id)
        #expect(relaunch(rig.run, now: h(9)) == rig.run)
    }

    @Test func atStopRoundTrips() {
        let rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        #expect(relaunch(rig.run, now: h(10)) == rig.run)
        #expect(relaunch(rig.run, now: h(10))?.progress.atCurrentStop == true)
    }

    @Test func betweenStopsRoundTrips() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        rig.send(.user(.doneHere), at: h(10.5))
        let back = relaunch(rig.run, now: h(11))
        #expect(back == rig.run)
        #expect(back?.phase == .betweenStops)
    }

    @Test func pausedRoundTripsWithItsPhase() {
        var rig = RunRig(at: RunFixture().s1, alreadyThere: true, now: h(9.6))
        rig.send(.user(.pause), at: h(9.7))
        #expect(rig.run.persisted.stateRaw == "paused")
        let back = relaunch(rig.run, now: h(10))
        #expect(back == rig.run)
        #expect(back?.pausedFrom == .atStop)
    }

    @Test func pausedWithoutASidecarDerivesThePhase() {
        var rig = RunRig.driving(to: RunFixture().s1)
        rig.send(.user(.pause), at: h(9))
        let back = TripRun.restore(from: rig.run.persisted, sidecar: nil, now: h(9))
        #expect(back.phase == .paused && back.pausedFrom == .driving)
    }

    @Test func finishedRoundTripsAndIsNotActive() {
        var rig = RunRig(at: RunFixture().way, alreadyThere: true, now: h(40))
        rig.send(.user(.doneHere), at: h(41))
        let store = InMemoryRunPersistence()
        store.save(rig.run.persisted)
        #expect(store.activeRun(tripID: rig.run.tripID) == nil)
        let back = TripRun.restore(from: rig.run.persisted, sidecar: nil, now: h(42))
        #expect(back == rig.run)
        #expect(back.phase == .finished && back.endedAt == h(41))
    }

    @Test func pendingUndoSurvivesARelaunchUntilItExpires() {
        var rig = RunRig()
        let lb = rig.leaveBy(of: rig.fx.s1)
        rig.send(.tick, at: lb)
        #expect(rig.run.sidecar?.pendingUndo != nil)
        var back = relaunch(rig.run, now: lb.addingTimeInterval(60))!
        #expect(back == rig.run)
        // "Not yet" still works after the relaunch.
        let out = back.handle(.user(.notYet), context: rig.context(at: lb.addingTimeInterval(61)))
        #expect(out.count == 1 && back.phase == .armed)
        // After expiry the undo is dropped on restore.
        let expired = relaunch(rig.run, now: lb.addingTimeInterval(121))!
        #expect(expired.pendingUndo == nil)
        #expect(expired.phase == .driving)
    }

    @Test func suppressionsSurviveARelaunch() {
        var rig = RunRig()
        rig.send(.tick, at: rig.leaveBy(of: rig.fx.s1))
        rig.send(.user(.notYet), at: rig.leaveBy(of: rig.fx.s1).addingTimeInterval(5))
        let back = relaunch(rig.run, now: h(9))
        #expect(back == rig.run)
        #expect(back?.suppressions.count == 1)
    }

    @Test func nothingToKeepMeansNoSidecar() {
        let rig = RunRig()
        #expect(rig.run.sidecar == nil)
    }

    @Test func recordPersistsExactlyTheChangedVisits() {
        var rig = RunRig()
        let store = InMemoryRunPersistence()
        store.save(rig.run.persisted)
        let out = rig.send(.user(.leaveNow), at: h(8))
        store.record(rig.run, transitions: out)
        let stored = store.runs[rig.run.id]!
        #expect(stored.stateRaw == "active")
        #expect(stored.visits.count == 5)
        #expect(stored.visits.first { $0.stopID == rig.fx.s1.id }?.statusRaw == "enRoute")
        #expect(stored.visits.first { $0.stopID == rig.fx.s2.id }?.statusRaw == "pending")
        #expect(TripRun.restore(from: stored, sidecar: store.loadSidecar(runID: rig.run.id), now: h(8)) == rig.run)
    }

    @Test func visitRawValuesMatchTheStore() {
        #expect(VisitStatus.allCases.map(\.rawValue) == ["pending", "enRoute", "arrived", "done", "skipped"])
        let v = StopVisit(stopID: UUID(), status: .arrived, departedForAt: h(1), arrivedAt: h(2), leftAt: h(3), plannedLeaveBy: h(4), plannedArrival: h(5))
        #expect(PersistedVisit(v).visit == v)
        #expect(PersistedVisit(v).statusRaw == "arrived")
        #expect(PersistedVisit(stopID: UUID(), statusRaw: "bogus").visit.status == .pending)
    }

    @Test func runIsCodable() throws {
        var rig = RunRig()
        rig.send(.tick, at: rig.leaveBy(of: rig.fx.s1))
        let data = try JSONEncoder().encode(rig.run)
        #expect(try JSONDecoder().decode(TripRun.self, from: data) == rig.run)
    }

    @Test func activeRunIsPerTrip() {
        let store = InMemoryRunPersistence()
        let a = RunRig(), other = TripRun(id: UUID(), tripID: UUID(), phase: .armed)
        store.save(a.run.persisted)
        store.save(other.persisted)
        #expect(store.activeRun(tripID: a.run.tripID)?.id == a.run.id)
        #expect(store.activeRun(tripID: UUID()) == nil)
    }
}
