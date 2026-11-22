import Foundation
import Testing
import IterModel
import IterSources
@testable import IterConditions

@Suite("Offline packs")
struct PackTests {
    @Test func aPackRoundTripsThroughItsFileAndKnowsItsAge() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(noaaDescriptor, clock: clock, recipe: clearRecipe),
                           FakeForecast(metDescriptor, clock: clock, recipe: metRecipe), FakeNoSource()], clock: clock, packDirectory: dir)
        let a = makePlace("A"), b = makePlace("B", lat: 39.9, lon: -104.6)
        let day = localDay(of: a)
        let tripID = UUID()
        let built = try await env.service.buildPack(tripID: tripID, stops: [PackStop(place: a, days: [day, day.adding(days: 1)]),
                                                                              PackStop(place: b, days: [day])])
        #expect(built.entries.count == 3)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(tripID.uuidString).json").path))
        let loaded = try #require(await env.service.pack(for: tripID))
        #expect(loaded == built.scrubbedForStorage())
        #expect(loaded.entry(placeID: a.id, day: day)?.report.forecast.value != nil)
        clock.advance(by: .seconds(5400))
        #expect(loaded.age(now: clock.now) == .seconds(5400))
        // No temporary file is left behind by the atomic write.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
    }

    @Test func aReportServedFromAPackSaysSoAndCarriesItsAge() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)], clock: clock, packDirectory: dir)
        let place = makePlace()
        let day = localDay(of: place)
        let tripID = UUID()
        try await env.service.buildPack(tripID: tripID, stops: [PackStop(place: place, days: [day])])
        clock.advance(by: .seconds(2 * 3600))
        let r = try #require(await env.service.packedReport(for: place, day: day))
        #expect(r.pack == PackServing(tripID: tripID, builtAt: t0))
        guard case .stale(_, let age) = r.forecast else { Issue.record("not stale"); return }
        #expect(age == .seconds(7200))
        #expect(r.offlineNote == "Forecast from 06:00, offline")
        #expect(r.daylight.windows.compactMap { $0.assessment.skyScore }.allSatisfy { $0.isStale })
        #expect(await env.service.packedReport(for: place, day: day.adding(days: 5)) == nil)
    }

    @Test func aTripBuildsItsPackFromItsStops() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = ManualSourceClock(now: t0)
        let env = makeEnv([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)], clock: clock, packDirectory: dir)
        let a = makePlace("A"), b = makePlace("B", lat: 39.9, lon: -104.6)
        let start = localDay(of: a)
        let trip = Trip(name: "T", startDay: start, dayCount: 2,
                        stops: [Stop(place: a, dayIndex: 0, session: .goldenEvening), Stop(place: b, dayIndex: 1, session: .goldenMorning)])
        let pack = try await env.service.buildPack(for: trip)
        #expect(pack.tripID == trip.id)
        #expect(Set(pack.entries.map(\.day)) == [start, start.adding(days: 1)])
        #expect(pack.entries.count == 2)
    }

    @Test func dataThatMayNotBeStoredStaysOutOfTheFileButNotOutOfMemory() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = ManualSourceClock(now: t0)
        let memoryOnly = makeDescriptor("test.memory", name: "Memory only", kinds: [.forecast], ranks: [.forecast: 5], mayStore: false)
        let env = makeEnv([FakeForecast(memoryOnly, clock: clock, recipe: Recipe(cloudTotal: 0.4, layers: (0.1, 0.1, 0.1))),
                           FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)], clock: clock, packDirectory: dir)
        let place = makePlace()
        let day = localDay(of: place)
        let tripID = UUID()
        let built = try await env.service.buildPack(tripID: tripID, stops: [PackStop(place: place, days: [day])])
        #expect(built.entries[0].report.forecast.value?.fieldSources[.cloudTotal] == memoryOnly.id)
        let onDisk = try #require(await env.service.pack(for: tripID))
        let report = try #require(onDisk.entry(placeID: place.id, day: day)?.report)
        #expect(report.forecast.value?.fieldSources[.cloudTotal] == nil)
        #expect(report.forecast.value?.hours.allSatisfy { $0.cloudTotal == nil } == true)
        #expect(report.fieldProvenance.allSatisfy { $0.provenance.licence.mayStore })
        // The disk cache of the source does not hold it either: only memory.
        let raw = try String(contentsOf: dir.appendingPathComponent("\(tripID.uuidString).json"), encoding: .utf8)
        #expect(!raw.contains("test.memory"))
    }

    @Test func withoutAPackDirectoryPacksAreDisabled() async {
        let env = makeEnv([])
        await #expect(throws: ConditionsError.packsDisabled) {
            try await env.service.buildPack(tripID: UUID(), stops: [])
        }
    }
}
