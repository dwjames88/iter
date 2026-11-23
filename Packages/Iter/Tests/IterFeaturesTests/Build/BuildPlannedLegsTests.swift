import Foundation
import Testing
import IterAstro
import IterModel
import IterPlan
import IterSky
import IterSources
@testable import IterFeatures

@MainActor
@Suite struct BuildPlannedLegsTests {
    private func settled(_ model: BuildModel) async -> Bool {
        let done = await settle { !model.isLoadingDrives }
        model.refreshIfChanged()
        return done
    }

    private func model(_ h: BuildHarness, store: any PlannedLegStoring, sample: Bool = false) -> BuildModel {
        let sleeper = h.sleeper
        return BuildModel(tripID: h.trip.id, library: h.library, conditions: h.conditions, packs: h.packs, routing: h.routing, now: { testNow },
                          engine: LightEngine(ephemeris: MemoizedEphemeris.shared), timing: BuildTiming(sleep: { try await sleeper.sleep($0) }),
                          legStore: store, isSampleData: sample)
    }

    @Test func buildKeepsItsRealDrivesForGoAndTheyStillFitTheTrip() async throws {
        let h = try BuildHarness()
        let store = InMemoryPlannedLegStore()
        let m = model(h, store: store)
        m.open()
        #expect(await settled(m))
        defer { m.close() }
        let saved = try #require(store.load(tripID: h.trip.id))
        #expect(saved.entries.count == 5, "one drive for each leg of the six-stop trip")
        #expect(saved.entries.allSatisfy { $0.mode == PlannedLegs.drivingMode && !$0.leg.isEstimate && $0.computedAt == testNow })
        let trip = h.trip.value()
        let legs = saved.legs(for: trip, start: nil)
        #expect(legs.count == 5)
        // A place that moved more than the tolerance drops its legs; the rest stay.
        var moved = trip
        moved.stops[1].place.coordinate = Coordinate(latitude: moved.stops[1].place.coordinate.latitude + 0.5, longitude: moved.stops[1].place.coordinate.longitude)
        let after = saved.legs(for: moved, start: nil)
        #expect(after.count == 3)
    }

    @Test func aSecondOpenWritesNothingNew() async throws {
        let h = try BuildHarness()
        let store = InMemoryPlannedLegStore()
        let first = model(h, store: store)
        first.open()
        #expect(await settled(first))
        first.close()
        let firstSave = try #require(store.load(tripID: h.trip.id))
        #expect(store.saveCount == 1, "written once, when the lookups settled")
        let again = model(h, store: store)
        again.open()
        #expect(await settled(again))
        again.close()
        // Same drives, same dates: a later open never shrinks or rewrites what a full plan saved.
        let saved = try #require(store.load(tripID: h.trip.id))
        #expect(saved == firstSave)
        #expect(store.saveCount == 1)
    }

    @Test func fileStoreRoundTripsAndKeepsPacksAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-legs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannedLegFileStore(directory: dir)
        let id = UUID(), a = UUID(), b = UUID()
        let leg = Leg(from: Coordinate(latitude: 1, longitude: 2), to: Coordinate(latitude: 3, longitude: 4), seconds: 600, meters: 9_000,
                      isEstimate: false, path: [Coordinate(latitude: 1, longitude: 2), Coordinate(latitude: 3, longitude: 4)])
        let legs = PlannedLegs(tripID: id, entries: [.init(from: a, to: b, computedAt: testNow, leg: leg)])
        #expect(store.load(tripID: id) == nil)
        store.save(legs)
        #expect(store.load(tripID: id) == legs)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["\(id.uuidString).legs"], "not a .json, so the pack loader never reads it")
    }

    @Test func sampleDataBuildsNoPackAndSaysSoInsteadOfFailing() async throws {
        let h = try BuildHarness()
        let m = model(h, store: InMemoryPlannedLegStore(), sample: true)
        m.open()
        m.setPinned(true)
        for _ in 0..<50 { await Task.yield() }
        #expect(h.packs.builds.isEmpty)
        #expect(m.packState == .sampleData)
        m.close()
    }
}
