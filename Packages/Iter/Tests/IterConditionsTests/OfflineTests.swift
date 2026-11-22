import Foundation
import Testing
import IterModel
import IterSources
import IterSky
@testable import IterConditions

@Suite("Offline and stale")
struct OfflineTests {
    @Test func offlineWithACachedForecastIsStaleWithItsAge() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        _ = await env.service.report(for: place, day: day, waitFor: .complete)
        #expect(met.callCount == 1)
        clock.advance(by: .seconds(7200))
        met.setFailure(.offline)
        let r = await env.service.report(for: place, day: day, waitFor: .complete)
        guard case .stale(_, let age) = r.forecast else { Issue.record("expected stale, got \(r.forecast)"); return }
        #expect(age >= .seconds(7200))
        #expect(r.offlineNote == "Forecast from 06:00, offline")
        #expect(r.provenanceLines.contains { $0.label == "Cloud layers" && $0.staleAge != nil })
        #expect(r.daylight.windows.compactMap { $0.assessment.skyScore }.allSatisfy { $0.isStale })
    }

    @Test func aStaleCacheIsReturnedAtOnceWhileOneRefetchRuns() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        _ = await env.service.report(for: place, day: day, waitFor: .complete)
        clock.advance(by: .seconds(3 * 3600))
        let events = await collect(env.service.reports(for: [ConditionsRequest(place: place, day: day)]))
        #expect(events.first?.forecast.isStale == true)
        #expect(events.last?.forecast.isFresh == true)
        #expect(met.callCount == 2)
        // A second consumer joined to the same refetch does not start another.
        clock.advance(by: .seconds(3 * 3600))
        async let a = env.service.report(for: place, day: day, waitFor: .complete)
        async let b = env.service.report(for: place, day: day, waitFor: .complete)
        _ = await (a, b)
        #expect(met.callCount == 3)
    }

    @Test func offlineWithNothingIsNoDataWithTheReason() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, failure: .offline)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let r = await env.service.report(for: place, day: localDay(of: place), waitFor: .complete)
        #expect(r.forecast.reasons == [.offline(lastGood: nil)])
        #expect(r.forecast.value == nil)
        #expect(r.daylight.windows.allSatisfy { $0.score == nil })
        #expect(r.gap(.forecast)?.reasons == [.offline(lastGood: nil)])
    }

    @Test func offlineFallsBackToTheTripPackWithThePacksAge() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let place = makePlace()
        let day = localDay(of: place)
        let tripID = UUID()
        let online = makeEnv([FakeForecast(noaaDescriptor, clock: ManualSourceClock(now: t0), recipe: clearRecipe)],
                             clock: ManualSourceClock(now: t0), packDirectory: dir)
        try await online.service.buildPack(tripID: tripID, stops: [PackStop(place: place, days: [day])])

        let later = ManualSourceClock(now: t0.addingTimeInterval(3 * 3600))
        let offline = makeEnv([FakeForecast(noaaDescriptor, clock: later, recipe: clearRecipe, failure: .offline)], clock: later, packDirectory: dir)
        let r = await offline.service.report(for: place, day: day, waitFor: .complete)
        guard case .stale(_, let age) = r.forecast else { Issue.record("expected stale from the pack, got \(r.forecast)"); return }
        #expect(age == .seconds(3 * 3600))
        #expect(r.pack?.tripID == tripID)
        #expect(r.pack?.builtAt == t0)
        #expect(r.offlineNote == "Forecast from 06:00, offline")
        #expect(r.forecast.value?.fieldSources[.cloudTotal] == noaaDescriptor.id)
        #expect(r.daylight.windows.contains { $0.score != nil })
    }

    @Test func aPackIsNeverUsedForAnotherDay() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let place = makePlace()
        let day = localDay(of: place)
        let online = makeEnv([FakeForecast(metDescriptor, clock: ManualSourceClock(now: t0), recipe: metRecipe)], packDirectory: dir)
        try await online.service.buildPack(tripID: UUID(), stops: [PackStop(place: place, days: [day])])
        let offline = makeEnv([FakeForecast(metDescriptor, clock: ManualSourceClock(now: t0), recipe: metRecipe, failure: .offline)],
                              packDirectory: dir)
        let r = await offline.service.report(for: place, day: day.adding(days: 1), waitFor: .complete)
        #expect(r.forecast.value == nil)
        #expect(r.pack == nil)
    }
}
