import Foundation
import CoreGraphics
import Synchronization
import Testing
import IterCore
import IterAstro
import IterLight
import IterData
import IterServices
@testable import IterFeatures

private final class CountingWeather: WeatherProviding, @unchecked Sendable {
    let source: ForecastSource = .appleWeather
    private let state = Mutex<(calls: [String], failing: Bool, fetchedAt: Date)>(([], false, Date(timeIntervalSince1970: 1_800_000_000)))
    var calls: [String] { state.withLock { $0.calls } }
    func setFailing(_ failing: Bool) { state.withLock { $0.failing = failing } }
    func setFetchedAt(_ date: Date) { state.withLock { $0.fetchedAt = date } }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        let (failing, at) = state.withLock { s -> (Bool, Date) in s.calls.append(coordinate.cacheKey); return (s.failing, s.fetchedAt) }
        if failing { throw WeatherError.failed("offline") }
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: at, source: .appleWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private final class FlakyDrives: DriveTimeProviding, @unchecked Sendable {
    private let state = Mutex<(calls: Int, failing: Bool)>((0, false))
    var calls: Int { state.withLock { $0.calls } }
    func setFailing(_ failing: Bool) { state.withLock { $0.failing = failing } }
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        let failing = state.withLock { s -> Bool in s.calls += 1; return s.failing }
        if failing { throw WeatherError.failed("no route") }
        return DriveLeg(from: a, to: b, seconds: 3600, meters: 80_000, isEstimate: false, path: [a, Coordinate(latitude: a.latitude, longitude: b.longitude), b])
    }
}

private final class FakeImagery: SpotImageryProviding, @unchecked Sendable {
    private let state = Mutex<(requests: [SpotImageRequest], empty: Bool)>(([], false))
    var requests: [SpotImageRequest] { state.withLock { $0.requests } }
    func cachedImages(for request: SpotImageRequest) -> [SpotImage]? { nil }
    func hasLookAround(spotID: String, coordinate: Coordinate) async -> Bool { false }
    func images(for request: SpotImageRequest) async -> [SpotImage] {
        state.withLock { $0.requests.append(request) }
        let size = 4
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage() else { return [] }
        return [SpotImage(key: request.key(.satellite), image: image)]
    }
}

private final class Clock: @unchecked Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_100))
    var now: Date { value.withLock { $0 } }
    func advance(hours: Double) { value.withLock { $0 = $0.addingTimeInterval(hours * 3600) } }
}

@MainActor
private struct Harness {
    let store: IterStore
    let weather = CountingWeather()
    let drives = FlakyDrives()
    let imagery = FakeImagery()
    let clock = Clock()
    let forecasts: ForecastCenter
    let offlineDrives: OfflineDriveTimes
    let scheduler = TripScheduler(engine: LightEngine(ephemeris: Astronomy()))
    let directory = FileManager.default.temporaryDirectory.appending(path: "iter-offline-\(UUID().uuidString)", directoryHint: .isDirectory)
    let downloader: PinnedTripDownloader

    init(usingDisk: Bool = true) {
        store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        forecasts = ForecastCenter(provider: weather)
        offlineDrives = OfflineDriveTimes(wrapping: drives)
        let clock = self.clock
        downloader = PinnedTripDownloader(store: store, forecasts: forecasts, scheduler: scheduler, drives: offlineDrives,
                                          packs: usingDisk ? OfflinePackStore(root: directory) : nil, now: { clock.now })
        downloader.imagery = imagery
    }

    var packs: OfflinePackStore { OfflinePackStore(root: directory) }

    func makeTrip() -> TripRecord {
        let trip = store.createTrip(name: "Utah", startDay: LocalDay(year: 2026, month: 10, day: 7), dayCount: 2)
        store.addStop(CuratedSpots.spot(id: "mesa-arch")!, to: trip, day: 0, session: .goldenMorning)
        store.addStop(CuratedSpots.spot(id: "delicate-arch")!, to: trip, day: 0, session: .goldenEvening)
        store.addStop(CuratedSpots.spot(id: "horseshoe-bend")!, to: trip, day: 1, session: .goldenEvening)
        return trip
    }

    /// A second downloader over the same directory, with a provider that always fails: a fresh launch with no network.
    func offlineLaunch() -> (PinnedTripDownloader, ForecastCenter, OfflineDriveTimes, FlakyDrives, CountingWeather) {
        let down = CountingWeather(); down.setFailing(true)
        let drives = FlakyDrives(); drives.setFailing(true)
        let center = ForecastCenter(provider: down)
        let od = OfflineDriveTimes(wrapping: drives)
        let clock = self.clock
        let d = PinnedTripDownloader(store: store, forecasts: center, scheduler: scheduler, drives: od,
                                     packs: OfflinePackStore(root: directory), now: { clock.now })
        return (d, center, od, drives, down)
    }
}

@MainActor
@Suite struct PinnedTripDownloaderTests {
    @Test func pinDownloadsEverythingAndBecomesReady() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        let task = h.downloader.pin(trip)
        #expect(trip.isPinned)
        guard case .downloading = h.downloader.status(for: trip.id) else { Issue.record("expected downloading"); return }
        await task.value
        #expect(h.downloader.status(for: trip.id) == .ready(savedAt: h.clock.now))

        let pack = try #require(h.packs.read(trip.id))
        #expect(pack.forecasts.count == 3)
        #expect(Set(pack.forecasts.keys) == Set(trip.plan.stops.map(\.spot.coordinate.cacheKey)))
        #expect(pack.legs.count == h.drives.calls)
        #expect(pack.legs.count >= 2)
        #expect(pack.legs.allSatisfy { !$0.isEstimate && $0.path.count == 3 })
        #expect(pack.images.count == 3 && pack.imageKeys.count == 3)
        #expect(pack.spots.count == 3)
        #expect(pack.failures.isEmpty)
        for name in pack.imageKeys { #expect(h.packs.readImage(trip.id, fileName: name) != nil) }
        #expect(h.imagery.requests.count == 3)
        #expect(h.weather.calls.count == 3)
    }

    @Test func packRoundTripsThroughDisk() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        await h.downloader.pin(trip).value
        let pack = try #require(h.packs.read(trip.id))
        let copy = OfflinePackStore(root: h.directory.appending(path: "copy"))
        try copy.write(pack, images: [:])
        #expect(copy.read(trip.id) == pack)
    }

    @Test func loadPacksSeedsForecastsAndLegsForAnOfflineLaunch() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        await h.downloader.pin(trip).value
        let pack = try #require(h.packs.read(trip.id))
        let leg = try #require(pack.legs.first)

        let (offline, center, drives, wrappedDrives, weather) = h.offlineLaunch()
        offline.restoreImage = { _, _ in }
        offline.loadPacks()
        for stop in trip.plan.stops {
            #expect(center.state(for: stop.spot.coordinate).forecast != nil)
        }
        let got = try await drives.drive(from: leg.from, to: leg.to)
        #expect(got == leg)
        #expect(wrappedDrives.calls == 0)
        #expect(offline.status(for: trip.id) == .ready(savedAt: pack.savedAt))
        // A screen asking for the forecast still tries the network once, and keeps the saved one when it fails.
        let coordinate = trip.plan.stops[0].spot.coordinate
        center.request(coordinate)
        _ = await center.load(coordinate)
        #expect(weather.calls.count >= 1)
        #expect(center.state(for: coordinate).forecast != nil)
    }

    @Test func loadPacksRestoresImagesIntoTheCache() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        await h.downloader.pin(trip).value
        let (offline, _, _, _, _) = h.offlineLaunch()
        let restored = Mutex<[String]>([])
        offline.restoreImage = { data, key in restored.withLock { $0.append(key.fileName) }; #expect(!data.isEmpty) }
        offline.loadPacks()
        #expect(restored.withLock { $0.count } == 3)
    }

    @Test func editingAStopMakesThePackStale() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        await h.downloader.pin(trip).value
        h.store.addStop(CuratedSpots.spot(id: "mesa-arch")!, to: trip, day: 1, session: .goldenMorning)
        guard case .stale(_, let reason) = h.downloader.status(for: trip.id) else { Issue.record("expected stale"); return }
        #expect(reason == .tripChanged)
    }

    @Test func oldForecastsMakeThePackStale() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        h.weather.setFetchedAt(h.clock.now)
        await h.downloader.pin(trip).value
        #expect(h.downloader.status(for: trip.id) == .ready(savedAt: h.clock.now))
        h.clock.advance(hours: 13)
        guard case .stale(_, let reason) = h.downloader.status(for: trip.id) else { Issue.record("expected stale"); return }
        #expect(reason == .forecastOld)
    }

    @Test func aFailedLegMakesThePackIncompleteAndIsNotStoredAsAnEstimate() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        h.drives.setFailing(true)
        await h.downloader.pin(trip).value
        guard case .stale(_, let reason) = h.downloader.status(for: trip.id) else { Issue.record("expected stale"); return }
        #expect(reason == .incomplete)
        let pack = try #require(h.packs.read(trip.id))
        #expect(pack.legs.isEmpty)
        #expect(!pack.failures.isEmpty)
    }

    @Test func failedItemsKeepTheirOlderData() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        await h.downloader.pin(trip).value
        let first = try #require(h.packs.read(trip.id))
        h.weather.setFailing(true); h.drives.setFailing(true)
        await h.downloader.download(trip.id).value
        let second = try #require(h.packs.read(trip.id))
        #expect(second.legs == first.legs)
        #expect(second.forecasts == first.forecasts)
        #expect(second.failures.count == 3 + first.legs.count)
        guard case .stale(_, .incomplete) = h.downloader.status(for: trip.id) else { Issue.record("expected incomplete"); return }
    }

    @Test func unpinKeepsThePackUntilCleanUp() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        await h.downloader.pin(trip).value
        h.downloader.unpin(trip)
        #expect(!trip.isPinned)
        #expect(h.downloader.status(for: trip.id) == .none)
        #expect(h.packs.read(trip.id) != nil)
        h.downloader.cleanUp()
        #expect(h.packs.read(trip.id) == nil)
        #expect(h.packs.packIDs().isEmpty)
    }

    @Test func cleanUpRemovesThePackOfADeletedTrip() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        let id = trip.id
        await h.downloader.pin(trip).value
        h.store.deleteTrip(trip)
        h.downloader.cleanUp()
        #expect(h.packs.read(id) == nil)
        #expect(h.packs.packIDs().isEmpty)
    }

    @Test func aDownloadAsksTheProviderOncePerCoordinate() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        // Two stops at the same place must share one request.
        h.store.addStop(CuratedSpots.spot(id: "mesa-arch")!, to: trip, day: 1, session: .goldenMorning)
        await h.downloader.pin(trip).value
        #expect(h.weather.calls.count == 3)
        #expect(Set(h.weather.calls).count == 3)
        await h.downloader.download(trip.id).value
        #expect(h.weather.calls.count == 6)   // a re-download goes to the provider again, once per coordinate
    }

    @Test func refreshStaleRedownloadsOnlyWhatNeedsIt() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        h.weather.setFetchedAt(h.clock.now)
        await h.downloader.pin(trip).value
        await h.downloader.refreshStale()
        #expect(h.weather.calls.count == 3)           // ready and fresh: nothing to do
        h.clock.advance(hours: 4)
        await h.downloader.refreshStale()
        #expect(h.weather.calls.count == 6)           // forecasts older than 3 h are refreshed
    }

    @Test func callingDownloadAgainCancelsTheEarlierRun() async throws {
        let h = Harness()
        let trip = h.makeTrip()
        let first = h.downloader.download(trip.id)
        let second = h.downloader.download(trip.id)
        await first.value
        await second.value
        #expect(h.downloader.status(for: trip.id) == .none)   // not pinned: no badge
        trip.isPinned = true
        guard case .ready = h.downloader.status(for: trip.id) else { Issue.record("expected ready"); return }
    }
}
