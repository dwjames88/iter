import Foundation
import Testing
import IterModel
import IterSources
import IterSky
@testable import IterConditions

@Suite("Batching, priority, cancellation")
struct SchedulingTests {
    private func areaPlaces(_ n: Int) -> [Place] {
        (0..<n).map { i in makePlace("P\(i)", lat: 39.40 + Double(i) * 0.03, lon: -105.2 + Double(i) * 0.02) }
    }

    @Test func concurrentRequestsInOneAreaShareOneBatchCallPerHorizon() async {
        let clock = ManualSourceClock(now: t0)
        let noaa = FakeBatch(noaaDescriptor, clock: clock, recipe: clearRecipe)
        let env = makeEnv([noaa], clock: clock, configuration: ConditionsConfiguration())
        let places = areaPlaces(20)
        let day = localDay(of: places[0])
        let events = await collect(env.service.reports(for: places.map { ConditionsRequest(place: $0, day: day) }))
        #expect(Set(events.map(\.placeID)).count == 20)
        #expect(events.filter { $0.tier == .complete }.count == 20)
        // Near term (12 h) and the longer horizon: two calls in all, each carrying all 20 places, not 40 single calls.
        #expect(noaa.batchCount <= 2)
        #expect(noaa.batches.allSatisfy { $0.coordinates.count == 20 })
        #expect(noaa.batches.map { Int($0.span.duration / 3600) }.first == 12)
    }

    @Test func nearTermComesFirstAndLongRangeFollows() async {
        let clock = ManualSourceClock(now: t0)
        let noaa = FakeBatch(noaaDescriptor, clock: clock, recipe: clearRecipe)
        let env = makeEnv([noaa], clock: clock, configuration: ConditionsConfiguration())
        let place = makePlace()
        // Three days out: the long horizon is needed, but 12 h goes first.
        let events = await collect(env.service.reports(for: [ConditionsRequest(place: place, day: localDay(of: place).adding(days: 3))]))
        #expect(noaa.batches.map { Int($0.span.duration / 3600) } == [12, 240])
        #expect(events.map(\.tier).contains(.nearTerm) || events.count >= 2)
        #expect(events.last?.tier == .complete)
    }

    @Test func visibleRequestsGoFirstInTheBatch() async {
        let clock = ManualSourceClock(now: t0)
        let noaa = FakeBatch(noaaDescriptor, clock: clock, recipe: clearRecipe)
        let env = makeEnv([noaa], clock: clock, configuration: ConditionsConfiguration())
        let places = areaPlaces(3)
        let day = localDay(of: places[0])
        let requests = [ConditionsRequest(place: places[0], day: day, priority: .background),
                        ConditionsRequest(place: places[1], day: day, priority: .onScreen),
                        ConditionsRequest(place: places[2], day: day, priority: .activeTrip)]
        _ = await collect(env.service.reports(for: requests))
        let order = noaa.batches[0].coordinates
        #expect(order == [places[1].coordinate, places[2].coordinate, places[0].coordinate])
    }

    @Test func aSerialSourceServesTheMostUrgentPlaceFirst() async {
        let clock = ManualSourceClock(now: t0)
        let serial = makeDescriptor("test.serial", name: "Serial", kinds: [.forecast], maxConcurrent: 1)
        let met = FakeForecast(serial, clock: clock, recipe: metRecipe)
        let env = makeEnv([met], clock: clock)
        let places = areaPlaces(4)
        let day = localDay(of: places[0])
        let priorities: [ConditionsPriority] = [.background, .pinnedTrip, .onScreen, .activeTrip]
        _ = await collect(env.service.reports(for: zip(places, priorities).map { ConditionsRequest(place: $0, day: day, priority: $1) }))
        #expect(met.calls.map(\.coordinate) == [places[2], places[3], places[1], places[0]].map(\.coordinate))
    }

    @Test func endingTheStreamCancelsTheBatchCall() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let noaa = FakeBatch(noaaDescriptor, clock: clock, recipe: clearRecipe, gate: gate)
        let env = makeEnv([noaa], clock: clock, configuration: ConditionsConfiguration())
        let place = makePlace()
        let day = localDay(of: place)
        let consumer = Task { for await _ in env.service.reports(for: [ConditionsRequest(place: place, day: day)]) {} }
        #expect(await eventually { noaa.batchCount == 1 })
        consumer.cancel()
        #expect(await eventually { noaa.cancelledCount == 1 })
        gate.open()
        await consumer.value
    }

    @Test func endingTheStreamCancelsASingleRequest() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, gate: gate)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        let consumer = Task { for await _ in env.service.reports(for: [ConditionsRequest(place: place, day: day)]) {} }
        #expect(await eventually { met.callCount == 1 })
        consumer.cancel()
        #expect(await eventually { met.cancelledCount == 1 })
        await consumer.value
    }

    @Test func oneConsumerLeavingDoesNotCancelAJoinedRequest() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, gate: gate)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        let a = Task { for await _ in env.service.reports(for: [ConditionsRequest(place: place, day: day)]) {} }
        let b = Task { await collect(env.service.reports(for: [ConditionsRequest(place: place, day: day)])) }
        #expect(await eventually { met.callCount == 1 })
        a.cancel()
        await a.value
        gate.open()
        let events = await b.value
        #expect(met.callCount == 1)
        #expect(met.cancelledCount == 0)
        #expect(events.last?.tier == .complete)
    }

    @Test func identicalInFlightRequestsAreJoined() async {
        let clock = ManualSourceClock(now: t0)
        let gate = HoldGate()
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, gate: gate)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        async let a = env.service.report(for: place, day: day, waitFor: .complete)
        async let b = env.service.report(for: place, day: day, waitFor: .complete)
        #expect(await eventually { met.callCount >= 1 })
        gate.open()
        let (ra, rb) = await (a, b)
        #expect(met.callCount == 1)
        #expect(ra.forecast.value == rb.forecast.value)
    }

    @Test func twoDaysOfOnePlaceShareOneDownload() async {
        let clock = ManualSourceClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe)
        let env = makeEnv([met], clock: clock)
        let place = makePlace()
        let day = localDay(of: place)
        _ = await collect(env.service.reports(for: [ConditionsRequest(place: place, day: day), ConditionsRequest(place: place, day: day.adding(days: 1))]))
        #expect(met.callCount == 1)
    }
}

@Suite("Horizon")
struct HorizonTests {
    @Test func aHorizonIsFetchedOnceAndThenCached() async {
        let clock = ManualSourceClock(now: t0)
        let terrain = FakeTerrain(clock: clock)
        let env = makeEnv([terrain], clock: clock)
        let place = makePlace()
        let a = await env.service.horizon(for: place)
        let b = await env.service.horizon(for: place)
        #expect(a.isFresh && b.isFresh)
        #expect(terrain.fetches.value == 1)
        // A 30-day TTL: still cached a week later, fetched again after a month.
        clock.advance(by: .seconds(7 * 86_400))
        _ = await env.service.horizon(for: place)
        #expect(terrain.fetches.value == 1)
        clock.advance(by: .seconds(30 * 86_400))
        _ = await env.service.horizon(for: place)
        #expect(terrain.fetches.value == 2)
    }

    @Test func aPlacesOwnHorizonIsUsedWithoutAFetch() async {
        let clock = ManualSourceClock(now: t0)
        let terrain = FakeTerrain(clock: clock)
        let env = makeEnv([terrain], clock: clock)
        var place = makePlace()
        place.horizon = HorizonProfile(elevationsDegrees: Array(repeating: 3, count: 72))
        let h = await env.service.horizon(for: place)
        #expect(h.value?.elevationsDegrees.first == 3)
        #expect(terrain.fetches.value == 0)
    }

    @Test func noTerrainSourceIsAGapNotAFlatHorizon() async {
        let env = makeEnv([])
        let h = await env.service.horizon(for: makePlace())
        #expect(h.value == nil)
        #expect(h.reasons == [.notProvidedBySource])
    }
}
