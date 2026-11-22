import Foundation
import Testing
import IterModel
import IterSources
@testable import IterConditions

@MainActor
@Suite("ConditionsStore")
struct StoreTests {
    private func store(_ sources: [any SourceDescribing], clock: ManualSourceClock) -> ConditionsStore {
        ConditionsStore(service: makeEnv(sources, clock: clock).service)
    }

    private func waitReady(_ s: ConditionsStore, _ p: Place, _ day: LocalDay) async -> Bool {
        await eventuallyOnMain { s.state(for: p.id, day: day).report?.tier == .complete && s.activeLoadCount == 0 }
    }

    @Test func aRequestLoadsAndReadiesTheSlot() async {
        let clock = ManualSourceClock(now: t0)
        let s = store([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        #expect(s.state(for: place.id, day: day) == .idle)
        s.request(place, day: day)
        #expect(s.state(for: place.id, day: day).isLoading)
        #expect(await waitReady(s, place, day))
        guard case .ready(let r) = s.state(for: place.id, day: day) else { Issue.record("not ready"); return }
        #expect(r.forecast.isFresh)
    }

    @Test func repeatedRequestsAreDeduplicated() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let s = store([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        for _ in 0..<5 { s.request(place, day: day) }
        #expect(s.activeLoadCount == 1)
        #expect(await waitReady(s, place, day))
        #expect(met.callCount == 1)
    }

    @Test func aLateAnswerForACancelledLoadIsDropped() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let s = store([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, gate: gate)], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        s.request(place, day: day)
        s.cancel(place.id, day: day)
        gate.open()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(s.state(for: place.id, day: day) == .idle)
    }

    @Test func aSupersededLoadCannotOverwriteTheNewerOne() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, gate: gate)
        let s = store([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        s.request(place, day: day, priority: .background)
        s.setVisible([place.id])
        #expect(s.loadPriority(for: place.id, day: day) == .onScreen)
        gate.open()
        #expect(await waitReady(s, place, day))
        #expect(s.state(for: place.id, day: day).report?.tier == .complete)
    }

    @Test func visibilityReprioritisesRunningLoads() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let s = store([FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, gate: gate)], clock: clock)
        let a = makePlace("A", lat: 39.1), b = makePlace("B", lat: 39.5)
        let day = localDay(of: a)
        s.request(a, day: day, priority: .background)
        s.request(b, day: day, priority: .background)
        #expect(s.loadPriority(for: a.id, day: day) == .background)
        s.setVisible([a.id])
        #expect(s.loadPriority(for: a.id, day: day) == .onScreen)
        #expect(s.loadPriority(for: b.id, day: day) == .background)
        s.setVisible([b.id])
        #expect(s.loadPriority(for: a.id, day: day) == .background)
        #expect(s.loadPriority(for: b.id, day: day) == .onScreen)
        s.setActiveTrip([a.id])
        #expect(s.loadPriority(for: a.id, day: day) == .activeTrip)
        s.setPinned([a.id])
        #expect(s.loadPriority(for: a.id, day: day) == .activeTrip)
        s.cancelAll()
        gate.open()
        #expect(s.activeLoadCount == 0)
    }

    @Test func theLastGoodReportStaysVisibleWhileARefreshLoads() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let env = makeEnv([met], clock: clock)
        let s = ConditionsStore(service: env.service)
        let place = makePlace()
        let day = localDay(of: place)
        s.request(place, day: day)
        #expect(await waitReady(s, place, day))
        let good = try! #require(s.report(for: place.id, day: day))
        // Forget everything cached and hold the next fetch: the slot says loading, and the old report is still there.
        clock.advance(by: .seconds(4 * 3600))
        await env.cache.removeAll()
        let gate = HoldGate()
        met.setGate(gate)
        s.refresh(place, day: day)
        #expect(s.state(for: place.id, day: day) == .loading(previous: good))
        #expect(s.report(for: place.id, day: day) == good)
        gate.open()
        #expect(await waitReady(s, place, day))
        #expect(s.report(for: place.id, day: day) != good)
    }
}
