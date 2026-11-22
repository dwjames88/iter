import Foundation
import Testing
import IterModel
import IterStore
@testable import IterFeatures

/// Pins the builder's work: how often it recomputes, how many days of light it computes, how many schedules it runs and how
/// many directions it asks for (the old `TripBuilderPerfTests`, on the 4-day, 6-stop, 5-leg Canyon Country trip).
@MainActor
@Suite struct BuildPerfTests {
    @Test func aLoadRecomputesOnceAndComputesOneDayOfLightPerStop() throws {
        let h = try BuildHarness()
        let model = h.model()
        #expect(model.recomputeCount == 1)
        #expect(model.dayLightCount == 6)
        #expect(model.scheduleCount == 1)
        #expect(model.directionsRequestCount == 0)
        model.open()
        #expect(model.recomputeCount == 1, "opening recomputes nothing")
        model.close()
    }

    @Test func aBurstOfDriveAnswersRecomputesOncePerWaveAndComputesNoLight() async throws {
        // The coalescing wait is held by the test; spacing is not.
        let sleeper = TestSleeper(holds: { $0 == .milliseconds(60) })
        let h = try BuildHarness(sleeper: sleeper)
        let model = h.model()
        model.open()
        // Wave 1: five typical drives answer; nothing is rebuilt until the coalescing window ends.
        #expect(await settle { model.directionsRequestCount == 5 && !model.drivesPending && sleeper.waiting.contains(.milliseconds(60)) })
        for _ in 0..<100 { await Task.yield() }
        #expect(model.recomputeCount == 1)
        sleeper.fire()
        // Wave 2: the typical drives fixed the plan, so the five traffic-aware ones are asked for.
        #expect(await settle { model.recomputeCount == 2 })
        #expect(await settle { model.directionsRequestCount == 10 && !model.drivesPending && sleeper.waiting.contains(.milliseconds(60)) })
        sleeper.fire()
        #expect(await settle { model.recomputeCount == 3 })
        for _ in 0..<100 { await Task.yield() }
        #expect(model.recomputeCount == 3)
        #expect(model.dayLightCount == 6, "drives do not change the light")
        #expect(model.scheduleCount == 1 + 1 + 2, "the first load, wave 1, then wave 2 with its traffic overlay")
        #expect(model.directionsRequestCount == 10)
        #expect(!model.isLoadingDrives)
        model.close()
    }

    @Test func anEditComputesLightOnlyForTheStopThatMoved() throws {
        let h = try BuildHarness()
        let model = h.model()
        let lights = model.dayLightCount
        model.setNote(model.stopIDs[0], to: "x")
        model.setBuffer(model.stopIDs[1], minutes: 30)
        #expect(model.dayLightCount == lights, "an edit that moves nothing reuses every day of light")
        model.moveStop(model.stopIDs[3], toDay: 1, index: 0)
        #expect(model.dayLightCount == lights + 1, "only the stop on a new day needs its light")
        #expect(model.recomputeCount == 4)
    }

    @Test func anIdenticalRecomputePublishesNothing() throws {
        let h = try BuildHarness()
        let model = h.model()
        let rows = model.rowsPublishCount, maps = model.mapPublishCount
        model.recompute()
        model.recompute()
        #expect(model.rowsPublishCount == rows && model.mapPublishCount == maps)
    }

    @Test func idleStaysIdle() async throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        #expect(await settle { !model.isLoadingDrives })
        model.refreshIfChanged()
        for _ in 0..<50 { await Task.yield() }
        let recomputes = model.recomputeCount, requests = model.directionsRequestCount
        for _ in 0..<500 { await Task.yield() }
        model.refreshIfChanged()
        #expect(model.recomputeCount == recomputes && model.directionsRequestCount == requests)
        model.close()
    }
}
