import Foundation
import Testing
import IterGo
import IterModel
import IterStore
@testable import IterFeatures

@MainActor
@Suite("StoreRunPersistence")
struct GoStorePersistenceTests {
    @Test func roundTripWithVisitsAndSidecar() throws {
        let rig = try GoRig()
        let store = try #require(rig.store)
        let p = rig.persistence
        let runID = UUID(), tripID = goID(100), s1 = goID(1), s2 = goID(2)
        let visit = PersistedVisit(stopID: s1, statusRaw: "arrived", departedForAt: goH(9), arrivedAt: goH(9.5), plannedLeaveBy: goH(9))
        p.save(PersistedRun(id: runID, tripID: tripID, stateRaw: "active", startedAt: goH(8), currentStopID: s1,
                            visits: [visit, PersistedVisit(stopID: s2, statusRaw: "pending")]))
        // RunSuppression has no public initialiser: build one through its Codable form.
        let json = "{\"stopID\":\"\(s2.uuidString)\",\"from\":\"atStop\",\"to\":\"betweenStops\",\"cause\":\"time\",\"restOfRun\":true}"
        let suppression = try JSONDecoder().decode(RunSuppression.self, from: Data(json.utf8))
        let sidecar = RunSidecar(pausedFrom: .driving, suppressions: [suppression])
        p.saveSidecar(sidecar, runID: runID)

        let loaded = try #require(p.activeRun(tripID: tripID))
        #expect(loaded.id == runID)
        #expect(loaded.stateRaw == "active")
        #expect(loaded.currentStopID == s1)
        #expect(loaded.startedAt == goH(8))
        #expect(loaded.visits.first { $0.stopID == s1 } == visit)
        #expect(loaded.visits.count == 2)
        #expect(p.loadSidecar(runID: runID) == sidecar)
        // One record in the store, under its own id (not the engine's).
        #expect(store.runs.runs(forTrip: tripID).count == 1)
        #expect(store.runs.runs(forTrip: tripID)[0].id != runID)

        p.saveVisit(runID: runID, PersistedVisit(stopID: s1, statusRaw: "done", departedForAt: goH(9), arrivedAt: goH(9.5), leftAt: goH(10.5)))
        p.saveSidecar(nil, runID: runID)
        #expect(p.activeRun(tripID: tripID)?.visits.first { $0.stopID == s1 }?.statusRaw == "done")
        #expect(p.loadSidecar(runID: runID) == nil)

        p.save(PersistedRun(id: runID, tripID: tripID, stateRaw: "finished", startedAt: goH(8), endedAt: goH(12), currentStopID: nil))
        #expect(p.activeRun(tripID: tripID) == nil)
        #expect(store.runs.runs(forTrip: tripID)[0].stateRaw == "finished")
    }

    @Test func aFreshInstanceFindsTheRunByItsFile() throws {
        let rig = try GoRig()
        let store = try #require(rig.store)
        let runID = UUID()
        rig.persistence.save(PersistedRun(id: runID, tripID: goID(100), stateRaw: "armed"))
        rig.persistence.saveSidecar(RunSidecar(pausedFrom: .atStop), runID: runID)
        let again = StoreRunPersistence(store: store, directory: rig.directory)
        // Sidecar and visit calls before any activeRun still resolve through the file.
        #expect(again.loadSidecar(runID: runID)?.pausedFrom == .atStop)
        #expect(again.activeRun(tripID: goID(100))?.id == runID)
    }

    @Test func engineRunRestoresOnANewEngine() async throws {
        let rig = try GoRig()
        let world = rig.world
        let a = rig.engine()
        await a.start(world.input, at: nil, alreadyThere: false)
        await a.perform(.leaveNow)
        #expect(a.run?.phase == .driving)
        rig.clock.advance(by: 600)
        await a.perform(.arrived)
        await a.perform(.doneHere)
        await a.perform(.leaveNow)
        let before = try #require(a.run)
        #expect(before.phase == .driving)
        #expect(before.targetStopID == world.stops[1].id)
        #expect(before.visits[world.stops[0].id]?.status == .done)
        a.stop()

        let b = rig.engine()
        #expect(b.run == nil)
        #expect(await b.restore(world.input))
        let after = try #require(b.run)
        #expect(after.id == before.id)
        #expect(after.phase == before.phase)
        #expect(after.targetStopID == before.targetStopID)
        #expect(after.visits == before.visits)
        #expect(after.startedAt == before.startedAt)
        b.stop()
    }

    @Test func pausedRunKeepsItsSidecarAcrossRelaunch() async throws {
        let rig = try GoRig()
        let a = rig.engine()
        await a.start(rig.world.input, at: nil, alreadyThere: false)
        await a.perform(.leaveNow)
        await a.perform(.pause)
        a.stop()
        let b = rig.engine()
        #expect(await b.restore(rig.world.input))
        #expect(b.run?.phase == .paused)
        #expect(b.run?.pausedFrom == .driving)
        b.stop()
    }
}
