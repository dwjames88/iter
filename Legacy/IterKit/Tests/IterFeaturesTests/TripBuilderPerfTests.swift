import Foundation
import Testing
import IterCore
import IterLight
import IterData
import IterServices
@testable import IterFeatures

/// A provider that remembers what it fetched and answers `cachedLeg` from it, like `MapKitDriveTimes`.
final class MemoDrives: DriveTimeProviding {
    private struct Key: Hashable { var from: String; var to: String }
    private let store = Box()
    private let minutes: Double

    init(minutes: Double = 60) { self.minutes = minutes }

    private final class Box: @unchecked Sendable {   // test double: a lock around a dictionary and a counter
        let lock = NSLock()
        var legs: [Key: DriveLeg] = [:]
        var fetched: [(Coordinate, Coordinate)] = []
    }

    var fetchedPairs: [(Coordinate, Coordinate)] { store.lock.withLock { store.fetched } }

    func warm(_ pairs: [(Coordinate, Coordinate)]) {
        for (a, b) in pairs { store.lock.withLock { store.legs[Key(from: a.cacheKey, to: b.cacheKey)] = leg(a, b) } }
    }

    private func leg(_ a: Coordinate, _ b: Coordinate) -> DriveLeg {
        DriveLeg(from: a, to: b, seconds: minutes * 60, meters: 80_000, isEstimate: false, path: [a, b])
    }

    func cachedLeg(from a: Coordinate, to b: Coordinate) -> DriveLeg? {
        store.lock.withLock { store.legs[Key(from: a.cacheKey, to: b.cacheKey)] }
    }

    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        if let hit = cachedLeg(from: a, to: b) { return hit }
        let made = leg(a, b)
        store.lock.withLock {
            store.fetched.append((a, b))
            store.legs[Key(from: a.cacheKey, to: b.cacheKey)] = made
        }
        return made
    }
}

/// Fails with `error` while it is set; otherwise answers. Counts every call.
actor ControlledDrives: DriveTimeProviding {
    private(set) var calls = 0
    private var error: (any Error)?

    init(failing error: (any Error)?) { self.error = error }
    func set(error: (any Error)?) { self.error = error }

    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        calls += 1
        if let error { throw error }
        return DriveLeg(from: a, to: b, seconds: 3600, meters: 80_000, isEstimate: false, path: [a, b])
    }
}

/// Holds every call until `open()`, so a test can change the trip while a fetch is in flight.
actor GatedDrives: DriveTimeProviding {
    private(set) var calls = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        calls += 1
        if !isOpen { await withCheckedContinuation { waiting.append($0) } }
        return DriveLeg(from: a, to: b, seconds: 3600, meters: 80_000, isEstimate: false, path: [a, b])
    }
}

/// A clock a test can advance.
@MainActor final class TestClock {
    var date = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TripHarness.denver)
}

/// Pins the trip builder's work: how often it recomputes, how many days of light it computes, how many drives it asks for.
@MainActor
@Suite struct TripBuilderPerfTests {
    /// A model on the sample trip (4 days, 6 stops) with legs held back until the burst, so the counts are deterministic.
    private func sampleModel(drives: any DriveTimeProviding = FakeDrives(), clock: TestClock = TestClock()) -> (TripHarness, TripBuilderModel, TestClock) {
        let h = TripHarness()
        let trip = h.store.seedSampleTrip(startDay: TripHarness.start)
        let model = h.model(for: trip, drives: drives, legCoalescing: .seconds(30), now: { clock.date })
        return (h, model, clock)
    }

    @Test func aLegBurstRecomputesOnceAndComputesNoLight() async {
        let (_, model, _) = sampleModel()
        let initialRecomputes = model.recomputeCount
        let initialLights = model.dayLightCount
        #expect(initialRecomputes == 1)
        #expect(initialLights == model.plan!.stops.count, "one day of light per stop at the first refresh")
        await model.waitForLegs()
        #expect(model.legs.count == 5)
        #expect(model.recomputeCount == initialRecomputes + 1, "all five legs land in one recompute")
        #expect(model.dayLightCount == initialLights, "legs do not change the light")
    }

    @Test func knownLegsAreTakenBeforeTheFirstRecompute() async {
        let h = TripHarness()
        let trip = h.store.seedSampleTrip(startDay: TripHarness.start)
        let drives = MemoDrives()
        let warmup = h.model(for: trip, drives: drives)
        await warmup.waitForLegs()
        let fetchedOnce = drives.fetchedPairs.count
        #expect(fetchedOnce > 0)

        let again = h.model(for: trip, drives: drives, legCoalescing: .seconds(30))
        #expect(again.legs.count == warmup.legs.count, "legs are in place synchronously")
        #expect(!again.isLoadingLegs)
        #expect(again.recomputeCount == 1)
        #expect(drives.fetchedPairs.count == fetchedOnce, "nothing is fetched twice")
    }

    @Test func reorderingAndMovingStopsNeverRefetchesAKnownPair() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let drives = MemoDrives()
        let model = h.model(for: trip, drives: drives)
        await model.waitForLegs()
        let mesa = model.days[0].stops[0].id
        let horseshoe = model.days[1].stops[0].id

        model.nudgeStop(mesa, by: 1)
        await model.waitForLegs()
        model.nudgeStop(mesa, by: -1)
        await model.waitForLegs()
        model.moveStop(horseshoe, toDay: 0)
        await model.waitForLegs()
        model.moveStop(horseshoe, toDay: 1)
        await model.waitForLegs()

        let keys = drives.fetchedPairs.map { "\($0.0.cacheKey)>\($0.1.cacheKey)" }
        #expect(keys.count == Set(keys).count, "one request per coordinate pair, however the stops are shuffled")
        let needed = h.scheduler.legPairsNeeded(for: model.plan!)
        #expect(needed.allSatisfy { model.legs[$0] != nil })
    }

    @Test func changingTheTripStopsTheFetchLoop() async {
        let h = TripHarness()
        let trip = h.store.seedSampleTrip(startDay: TripHarness.start)
        let drives = GatedDrives()
        let model = h.model(for: trip, drives: drives)
        while await drives.calls == 0 { await Task.yield() }
        model.deleteTrip()
        await drives.open()
        await model.waitForLegs()
        for _ in 0..<20 { await Task.yield() }
        #expect(await drives.calls == 1, "only the request already in flight; the rest of the loop is dropped")
        #expect(model.legs.isEmpty)
        #expect(!model.isLoadingLegs)
    }

    @Test func aPassingFailureIsRetriedNotKeptAsAnEstimate() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let drives = ControlledDrives(failing: MapServiceError.throttled)
        let clock = TestClock()
        let model = h.model(for: trip, drives: drives, now: { clock.date })
        await model.waitForLegs()
        let firstCalls = await drives.calls
        #expect(firstCalls > 0)
        #expect(model.legs.isEmpty, "a throttled answer is not stored as the drive")
        #expect(model.days[0].hasEstimatedDrive, "the schedule still shows its straight-line estimate meanwhile")

        // Straight away: still cooling down, so no new request.
        model.refresh()
        await model.waitForLegs()
        #expect(await drives.calls == firstCalls)

        // Later, with the service back: the same refresh asks again and gets real drives.
        await drives.set(error: nil)
        clock.date.addTimeInterval(TripBuilderModel.retryDelay + 1)
        model.refresh()
        await model.waitForLegs()
        #expect(!model.legs.isEmpty)
        #expect(model.legs.values.allSatisfy { !$0.isEstimate })
        #expect(!model.days[0].hasEstimatedDrive)
    }

    @Test func noRouteIsFinalAndNotAskedAgain() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let drives = ControlledDrives(failing: MapServiceError.noRoute)
        let model = h.model(for: trip, drives: drives)
        await model.waitForLegs()
        let calls = await drives.calls
        #expect(model.legs.values.allSatisfy(\.isEstimate) && !model.legs.isEmpty)
        model.refresh()
        await model.waitForLegs()
        #expect(await drives.calls == calls)
    }

    @Test func aForecastForOneStopRecomputesOnlyThatStopsLight() async {
        let (h, model, _) = sampleModel()
        await model.waitForLegs()
        // Let every place settle (no weather configured: each becomes unavailable), then take a baseline.
        for stop in model.plan!.stops { _ = await h.forecasts.load(stop.spot.coordinate) }
        model.refreshIfChanged()
        let baseline = model.dayLightCount
        let content = model.mapContent
        let recomputes = model.recomputeCount

        let first = model.plan!.stops[0]
        let forecast = Forecast(coordinate: first.spot.coordinate, hours: [], days: [], fetchedAt: Date(timeIntervalSince1970: 1_790_000_000), source: .appleWeather)
        h.forecasts.seed(forecast, for: first.spot.coordinate)
        model.refreshIfChanged()
        #expect(model.recomputeCount == recomputes + 1)
        #expect(model.dayLightCount == baseline + 1, "only the stop whose forecast arrived is scored again")
        #expect(model.mapContent == content, "a forecast leaves the map's content equal")
    }

    @Test func nothingRecomputesWhenNothingChanged() async {
        let (h, model, _) = sampleModel()
        await model.waitForLegs()
        for stop in model.plan!.stops { _ = await h.forecasts.load(stop.spot.coordinate) }
        model.refreshIfChanged()
        let recomputes = model.recomputeCount
        let lights = model.dayLightCount
        for _ in 0..<50 { model.refreshIfChanged() }
        #expect(model.recomputeCount == recomputes)
        #expect(model.dayLightCount == lights)
    }

    @Test func mapContentCarriesTheGeometryAndOnlyChangesWithIt() async {
        let (_, model, _) = sampleModel()
        await model.waitForLegs()
        let content = model.mapContent
        #expect(content.pins.map(\.number) == Array(1...6))
        #expect(content.legs.count == 5)
        #expect(content.days.count == model.days.count)
        // A dismissed suggestion, a focus change and the like do not touch it.
        model.setFocusDay(2)
        model.setFocusDay(nil)
        #expect(model.mapContent == content)
        // Moving a stop does.
        let id = model.days[0].stops[0].id
        model.moveStop(id, toDay: 1)
        #expect(model.mapContent != content)
    }

    @Test func aDaySwitchMakesOneCameraRequestAndRefitsOnlyOnce() async {
        let (_, model, _) = sampleModel()
        await model.waitForLegs()
        model.requestInitialCamera()
        let before = model.cameraRequest?.id ?? 0
        let all = model.fitCoordinates

        model.setFocusDay(1)
        #expect(model.cameraRequest?.id == before + 1)
        #expect(model.fitCoordinates != all)
        // The view's onChange(of: fitCoordinates) calls this next; it must not ask again.
        model.contentChanged()
        #expect(model.cameraRequest?.id == before + 1)
        model.setFocusDay(1)
        #expect(model.cameraRequest?.id == before + 1)

        model.setFocusDay(nil)
        #expect(model.cameraRequest?.id == before + 2)
        #expect(model.fitCoordinates == all)
    }

    @Test func theFitIsStableAcrossLegsAndForecasts() async {
        let (h, model, _) = sampleModel()
        model.requestInitialCamera()
        let fit = model.fitCoordinates
        await model.waitForLegs()
        #expect(model.fitCoordinates == fit)
        let first = model.plan!.stops[0]
        h.forecasts.seed(Forecast(coordinate: first.spot.coordinate, hours: [], days: [], fetchedAt: .now, source: .appleWeather), for: first.spot.coordinate)
        model.refreshIfChanged()
        #expect(model.fitCoordinates == fit)
    }

    @Test func selectingAStopMovesTheHighlightNotTheCamera() async {
        let (_, model, _) = sampleModel()
        await model.waitForLegs()
        model.requestInitialCamera()
        model.setFocusDay(0)
        let requests = model.cameraRequestCount
        model.setFocusDay(2, refit: false)
        #expect(model.focusDay == 2)
        #expect(model.cameraRequestCount == requests, "a selection never refits")
        model.contentChanged()
        #expect(model.cameraRequestCount == requests, "and the map's own follow-up call does not either")
        model.setFocusDay(1)
        #expect(model.cameraRequestCount == requests + 1, "choosing a day in the strip still frames it once")
        model.contentChanged()
        model.contentChanged()
        #expect(model.cameraRequestCount == requests + 1, "repeated calls for the same framing are free")
    }

    @Test func aRecomputeThatChangesNothingPublishesNothing() async {
        let (_, model, _) = sampleModel()
        await model.waitForLegs()
        model.refresh()   // the forecast request the first refresh made settles its state
        let published = model.layoutPublishCount
        model.refresh()
        model.refresh()
        #expect(model.layoutPublishCount == published, "the plan list is not invalidated by an identical layout")
    }

    @Test func theDrawnRouteIsThinnedButKeepsItsEnds() {
        let path = (0...2000).map { Coordinate(latitude: 37 + Double($0) * 0.00001, longitude: -111 + sin(Double($0) / 300) * 0.01) }
        let thin = PathSimplifier.simplify(path, tolerance: PathSimplifier.routeTolerance)
        #expect(thin.count < path.count / 10)
        #expect(thin.first == path.first && thin.last == path.last)
        let straight = PathSimplifier.simplify([path[0], path[1], path[2]], tolerance: 0)
        #expect(straight.count == 3, "no tolerance keeps every point")
    }

    @Test func aMissedSettleAfterTheFirstGoodOneIsNotAskedAgain() async throws {
        let (_, model, _) = sampleModel()
        await model.waitForLegs()
        model.requestInitialCamera()
        guard case .fit(let first)? = model.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        model.cameraDidChange(to: first)
        let requests = model.cameraRequestCount
        model.setFocusDay(1)
        #expect(model.cameraRequestCount == requests + 1)
        // MapKit shows the day in a pane shaped unlike the request: the centre is off by more than the policy allows.
        let skewed = GeoRegion(center: Coordinate(latitude: 10, longitude: 10), latitudeDelta: 0.5, longitudeDelta: 0.1)
        model.cameraDidChange(to: skewed)
        #expect(model.cameraRequestCount == requests + 1, "no second request after a miss")
    }
}
