import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Observation
import OSLog
import IterCore
import IterLight
import IterData
import IterServices

/// Keeps pinned trips ready offline: forecasts for every stop, the real drive legs (with route lines), and the place-card
/// images, saved as one pack per trip. The base map is not included (MapKit has no public tile download).
///
/// Offline reads: `loadPacks()` seeds `ForecastCenter` (last good forecasts) and `OfflineDriveTimes` (legs), and puts the
/// pack's PNGs back into the imagery disk cache, so a pinned trip opens complete with no network.
@MainActor
@Observable
public final class PinnedTripDownloader {
    /// Forecasts older than this are refreshed while online.
    public static let refreshAge: TimeInterval = 3 * 3600
    /// A pack whose oldest forecast is older than this is stale.
    public static let staleAge: TimeInterval = 12 * 3600

    private struct Meta {
        var savedAt: Date
        var tripUpdatedAt: Date
        var oldestForecast: Date?
        var hasFailures: Bool
    }

    private let store: IterStore
    private let forecasts: ForecastCenter
    private let scheduler: TripScheduler
    private let drives: OfflineDriveTimes
    private let packs: OfflinePackStore?
    private let now: () -> Date
    private let log = Logger(subsystem: "com.dwjames.iter", category: "offline")

    /// Source of place-card images; nil downloads none (tests, or before the app attaches it).
    @ObservationIgnored public var imagery: (any SpotImageryProviding)?
    /// Writes a saved PNG back into the imagery's disk cache at launch.
    @ObservationIgnored public var restoreImage: ((Data, SpotImageKey) -> Void)?
    /// The size the place card requests, in points, and the display scale.
    @ObservationIgnored public var imagePointSize = CGSize(width: 360, height: 200)
    @ObservationIgnored public var imageScale: CGFloat = 2

    private var transient: [UUID: OfflinePackStatus] = [:]
    private var meta: [UUID: Meta] = [:]
    @ObservationIgnored private var tasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var progress: [UUID: (done: Int, total: Int)] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(store: IterStore, forecasts: ForecastCenter, scheduler: TripScheduler, drives: OfflineDriveTimes,
                packs: OfflinePackStore?, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.forecasts = forecasts
        self.scheduler = scheduler
        self.drives = drives
        self.packs = packs
        self.now = now
    }

    // MARK: Status

    /// The offline state of a trip. Trips that are not pinned always read `.none` (their pack, if kept, is invisible).
    public func status(for tripID: UUID) -> OfflinePackStatus {
        guard let trip = store.trip(id: tripID), trip.isPinned else { return .none }
        if let state = transient[tripID] { return state }
        guard let m = meta[tripID] else { return .none }
        if let reason = staleReason(m, trip: trip) { return .stale(savedAt: m.savedAt, reason: reason) }
        return .ready(savedAt: m.savedAt)
    }

    private func staleReason(_ m: Meta, trip: TripRecord) -> StaleReason? {
        if trip.updatedAt > m.tripUpdatedAt { return .tripChanged }
        if let oldest = m.oldestForecast, now().timeIntervalSince(oldest) > Self.staleAge { return .forecastOld }
        if m.hasFailures { return .incomplete }
        return nil
    }

    // MARK: Pin / unpin

    /// Pins the trip and starts downloading it.
    @discardableResult
    public func pin(_ trip: TripRecord) -> Task<Void, Never> {
        store.setPinned(trip, true)
        return download(trip.id)
    }

    /// Unpins the trip. Its pack stays on disk until `cleanUp()`.
    public func unpin(_ trip: TripRecord) {
        store.setPinned(trip, false)
        if let running = tasks.removeValue(forKey: trip.id) { running.task.cancel() }
        transient[trip.id] = nil
    }

    // MARK: Download

    /// Downloads (or refreshes) the trip's pack. A call for a trip already downloading cancels the earlier run.
    @discardableResult
    public func download(_ tripID: UUID) -> Task<Void, Never> {
        tasks[tripID]?.task.cancel()
        let token = UUID()
        transient[tripID] = .downloading(done: 0, total: 0)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(tripID, token: token)
        }
        tasks[tripID] = (token, task)
        return task
    }

    private func isCurrent(_ id: UUID, _ token: UUID) -> Bool { tasks[id]?.token == token && !Task.isCancelled }

    private func tick(_ id: UUID, _ token: UUID) {
        guard tasks[id]?.token == token, var p = progress[id] else { return }
        p.done += 1
        progress[id] = p
        transient[id] = .downloading(done: p.done, total: p.total)
    }

    private enum ForecastOutcome: Sendable {
        case fetched(Forecast)
        case failed
        case unavailable
    }

    private struct ImageOutcome: Sendable {
        var request: SpotImageRequest
        var images: [(info: OfflinePack.Image, data: Data?)]
    }

    private func performDownload(_ tripID: UUID, token: UUID) async {
        let clock = ContinuousClock()
        let started = clock.now
        guard let trip = store.trip(id: tripID) else {
            finishRun(tripID, token, status: nil)
            return
        }
        let plan = trip.plan
        let tripUpdatedAt = trip.updatedAt
        let previous = packs?.read(tripID)

        // What to fetch, each once.
        var seenCoordinates = Set<String>()
        let coordinates = plan.stops.map(\.spot.coordinate).filter { seenCoordinates.insert($0.cacheKey).inserted }
        var spots: [Spot] = []
        var seenSpots = Set<String>()
        for stop in plan.stops where seenSpots.insert(stop.spot.id).inserted { spots.append(stop.spot) }
        let stopCoordinates = Dictionary(plan.stops.map { ($0.id, $0.spot.coordinate) }, uniquingKeysWith: { first, _ in first })
        var seenPairs = Set<String>()
        var pairs: [(Coordinate, Coordinate)] = []
        for key in scheduler.legPairsNeeded(for: plan) {
            guard let a = stopCoordinates[key.from], let b = stopCoordinates[key.to], a.cacheKey != b.cacheKey,
                  seenPairs.insert("\(a.cacheKey)>\(b.cacheKey)").inserted else { continue }
            pairs.append((a, b))
        }
        let requests: [SpotImageRequest] = imagery == nil ? [] : spots.map {
            SpotImageRequest(spotID: $0.id, coordinate: $0.coordinate, pointSize: imagePointSize, scale: imageScale)
        }
        let total = coordinates.count + pairs.count + requests.count
        progress[tripID] = (0, total)
        transient[tripID] = .downloading(done: 0, total: total)

        var failures: [String] = []

        // Forecasts (through ForecastCenter: its cache and the daily call cap apply), a few at a time.
        var newForecasts: [String: Forecast] = [:]
        let center = forecasts
        await limited(coordinates, limit: 3, work: { coordinate -> (String, ForecastOutcome) in
            let state = await center.refresh(coordinate)
            if center.didFail(coordinate) { return (coordinate.cacheKey, .failed) }
            if case .loaded(let forecast) = state { return (coordinate.cacheKey, .fetched(forecast)) }
            return (coordinate.cacheKey, .unavailable)
        }, result: { key, outcome in
            switch outcome {
            case .fetched(let forecast): newForecasts[key] = forecast
            case .failed: failures.append("forecast \(key)")
            case .unavailable: break
            }
            tick(tripID, token)
        })
        guard isCurrent(tripID, token) else { return finishRun(tripID, token, status: nil) }

        // Drive legs: the real route, one at a time (MapKit throttles). A failure is recorded, never replaced by an estimate.
        var newLegs: [DriveLeg] = []
        for (a, b) in pairs {
            guard isCurrent(tripID, token) else { return finishRun(tripID, token, status: nil) }
            do {
                let leg = try await drives.wrapped.drive(from: a, to: b)
                if leg.isEstimate { failures.append("leg \(a.cacheKey) to \(b.cacheKey)") } else { newLegs.append(leg) }
            } catch is CancellationError {
                return finishRun(tripID, token, status: nil)
            } catch {
                failures.append("leg \(a.cacheKey) to \(b.cacheKey)")
            }
            tick(tripID, token)
        }

        // Images at the sizes the place card asks for.
        var newImages: [ImageOutcome] = []
        if let imagery {
            let encode = packs != nil
            await limited(requests, limit: 2, work: { request -> ImageOutcome in
                let found = await imagery.images(for: request)
                var entries: [(info: OfflinePack.Image, data: Data?)] = []
                for image in found {
                    let info = OfflinePack.Image(fileName: image.key.fileName, spotID: request.spotID, source: image.source,
                                                 coordinate: request.coordinate, pointWidth: request.pointSize.width,
                                                 pointHeight: request.pointSize.height, scale: Double(request.scale))
                    // PNG encoding is CPU work (tens of milliseconds per card image): off the main actor.
                    entries.append((info, encode ? await Self.png(image.image) : nil))
                }
                return ImageOutcome(request: request, images: entries)
            }, result: { outcome in
                if outcome.images.isEmpty { failures.append("images \(outcome.request.spotID)") }
                newImages.append(outcome)
                tick(tripID, token)
            })
        }
        guard isCurrent(tripID, token) else { return finishRun(tripID, token, status: nil) }

        // Merge with the previous pack so a failed item keeps its older data instead of losing it.
        var mergedForecasts = (previous?.forecasts ?? [:]).filter { seenCoordinates.contains($0.key) }
        mergedForecasts.merge(newForecasts) { _, new in new }
        let pairKeys = Set(pairs.map { "\($0.0.cacheKey)>\($0.1.cacheKey)" })
        var legsByPair: [String: DriveLeg] = [:]
        for leg in previous?.legs ?? [] where pairKeys.contains("\(leg.from.cacheKey)>\(leg.to.cacheKey)") {
            legsByPair["\(leg.from.cacheKey)>\(leg.to.cacheKey)"] = leg
        }
        for leg in newLegs { legsByPair["\(leg.from.cacheKey)>\(leg.to.cacheKey)"] = leg }
        let orderedLegs = pairs.compactMap { legsByPair["\($0.0.cacheKey)>\($0.1.cacheKey)"] }

        var imageInfos: [String: OfflinePack.Image] = [:]
        var imageData: [String: Data] = [:]
        let wanted = Set(requests.flatMap { r in SpotImageSource.allCases.map { r.key($0).fileName } })
        for info in previous?.images ?? [] where wanted.contains(info.fileName) { imageInfos[info.fileName] = info }
        for outcome in newImages {
            for entry in outcome.images {
                imageInfos[entry.info.fileName] = entry.info
                if let data = entry.data { imageData[entry.info.fileName] = data }
            }
        }
        // Keep only images that exist on disk (previous ones) or were just encoded.
        if let packs {
            imageInfos = imageInfos.filter { imageData[$0.key] != nil || packs.readImage(tripID, fileName: $0.key) != nil }
        }
        let orderedImages = imageInfos.values.sorted { $0.fileName < $1.fileName }

        let pack = OfflinePack(tripID: tripID, savedAt: now(), tripUpdatedAt: tripUpdatedAt, spots: spots,
                               forecasts: mergedForecasts, legs: orderedLegs, images: orderedImages, failures: failures)
        do {
            if let packs { try await Self.write(pack, images: imageData, to: packs) }
        } catch {
            log.error("offline: could not write pack for \(plan.name, privacy: .public): \(String(describing: error), privacy: .public)")
            return finishRun(tripID, token, status: .failed("Could not save the offline copy."))
        }
        apply(pack, restoreImages: false)
        finishRun(tripID, token, status: nil)

        let elapsed = started.duration(to: clock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        log.notice("offline: downloaded \(plan.name, privacy: .public) (\(plan.stops.count) stops) in \(String(format: "%.1f", seconds), privacy: .public) s, \(failures.count) failures")
    }

    private func finishRun(_ id: UUID, _ token: UUID, status: OfflinePackStatus?) {
        guard tasks[id]?.token == token else { return }   // a newer run owns the state
        tasks[id] = nil
        progress[id] = nil
        transient[id] = status
    }

    /// Runs `work` over `items` with at most `limit` in flight; `result` runs on the main actor as each finishes.
    private func limited<Item: Sendable, Output: Sendable>(_ items: [Item], limit: Int,
                                                         work: @escaping @MainActor @Sendable (Item) async -> Output,
                                                         result: (Output) -> Void) async {
        await withTaskGroup(of: Output.self) { group in
            var next = 0
            while next < min(limit, items.count) {
                let item = items[next]
                group.addTask { await work(item) }
                next += 1
            }
            while let output = await group.next() {
                result(output)
                if next < items.count, !Task.isCancelled {
                    let item = items[next]
                    group.addTask { await work(item) }
                    next += 1
                }
            }
        }
    }

    /// Disk writes (many PNGs, then the JSON) off the main actor.
    @concurrent private static func write(_ pack: OfflinePack, images: [String: Data], to store: OfflinePackStore) async throws {
        try store.write(pack, images: images)
    }

    @concurrent private static func png(_ image: CGImage) async -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Launch

    /// Seeds forecasts, legs and images from the packs of pinned trips, so they open complete with no network.
    public func loadPacks() {
        guard let packs else { return }
        for trip in store.pinnedTrips() {
            guard let pack = packs.read(trip.id) else { continue }
            apply(pack, restoreImages: true)
        }
    }

    private func apply(_ pack: OfflinePack, restoreImages: Bool) {
        for (key, forecast) in pack.forecasts {
            if let coordinate = ForecastCenter.coordinate(fromKey: key) { forecasts.seed(forecast, for: coordinate) }
        }
        drives.seed(pack.legs)
        if restoreImages, let packs, let restore = restoreImage {
            for image in pack.images {
                if let data = packs.readImage(pack.tripID, fileName: image.fileName) { restore(data, image.key) }
            }
        }
        meta[pack.tripID] = Meta(savedAt: pack.savedAt, tripUpdatedAt: pack.tripUpdatedAt,
                                 oldestForecast: pack.oldestForecast, hasFailures: !pack.failures.isEmpty)
    }

    /// Removes the packs of trips that were deleted or are not pinned.
    public func cleanUp() {
        guard let packs else { return }
        let keep = Set(store.pinnedTrips().map(\.id))
        for id in packs.packIDs() where !keep.contains(id) {
            if let running = tasks.removeValue(forKey: id) { running.task.cancel() }
            packs.delete(id)
            meta[id] = nil
            transient[id] = nil
        }
    }

    /// Re-downloads every pinned trip that is missing, stale, failed, or whose forecasts are older than 3 hours.
    /// A failing network leaves the old pack in place (a failed item keeps its previous data) and the trip `.stale`.
    public func refreshStale() async {
        for trip in store.pinnedTrips() {
            let id = trip.id
            let needs: Bool
            switch status(for: id) {
            case .downloading: needs = false
            case .none, .stale, .failed: needs = true
            case .ready:
                if let oldest = meta[id]?.oldestForecast { needs = now().timeIntervalSince(oldest) > Self.refreshAge } else { needs = false }
            }
            if needs { await download(id).value }
        }
    }

    /// Launch work, then an hourly refresh while the app runs. Call once; `stop()` cancels it.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            self?.loadPacks()
            self?.cleanUp()
            await self?.refreshStale()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                if Task.isCancelled { break }
                await self?.refreshStale()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// The app attaches Apple's imagery (and the place-card size) before `start()`.
    public func attach(imagery: MapKitSpotImagery, pointSize: CGSize, scale: CGFloat) {
        self.imagery = imagery
        self.restoreImage = { [imagery] data, key in imagery.restore(data, for: key) }
        self.imagePointSize = pointSize
        self.imageScale = scale
    }
}
