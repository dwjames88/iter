import Foundation
import CoreGraphics
import MapKit
import IterCore
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Spot imagery from MapKit: Look Around first (when Apple has it here), then a satellite snapshot.
/// Memory cache, then disk, then MapKit; identical concurrent requests share one job.
public final class MapKitSpotImagery: SpotImageryProviding {
    /// A render or test copy (`RenderCopy`) keeps its disk cache in a throwaway folder, not the user's Caches.
    public static let shared = MapKitSpotImagery(directory: RenderCopy.isCurrent ? RenderCopy.scratchDirectory("SpotImagery") : nil)

    private let disk: SpotImageDiskCache
    private let memory: SpotImageMemoryCache
    private let jobs = SpotImageJobs()

    public init(directory: URL? = nil, memory: SpotImageMemoryCache = .init()) {
        self.disk = SpotImageDiskCache(directory: directory ?? SpotImageDiskCache.defaultDirectory())
        self.memory = memory
    }

    public func cachedImages(for request: SpotImageRequest) -> [SpotImage]? {
        memory.images(for: request)
    }

    public func images(for request: SpotImageRequest) async -> [SpotImage] {
        if let cached = memory.images(for: request) { return cached }
        let waiter = await jobs.join(request) { [self] in
            let result = await resolve(request)
            // An empty result usually means offline; do not remember it, so the next ask retries. A cancelled job
            // (nobody is waiting any more) may have stopped half way, so what it has is not the answer either.
            if !result.isEmpty, !Task.isCancelled { memory.store(result, for: request) }
            return result
        }
        // Stepping quickly through places leaves each one's view behind; when the last view asking for a job goes, the
        // job stops before its next MapKit step instead of snapshotting a place nobody is looking at.
        let result = await withTaskCancellationHandler {
            await waiter.task.value
        } onCancel: {
            Task { [jobs] in await jobs.abandon(request, waiter: waiter.id) }
        }
        await jobs.release(request, waiter: waiter.id)
        return result
    }

    public func hasLookAround(spotID: String, coordinate: Coordinate) async -> Bool {
        if let known = disk.readAvailability(spotID: spotID, coordinate: coordinate) { return known }
        switch await Self.lookAroundScene(at: coordinate) {
        case .available:
            disk.writeAvailability(true, spotID: spotID, coordinate: coordinate); return true
        case .none:
            disk.writeAvailability(false, spotID: spotID, coordinate: coordinate); return false
        case .failed:
            return false   // not remembered: an error is not an answer
        }
    }

    /// Puts an offline pack's PNG back into the disk cache (if Caches was purged) and marks Look Around as available.
    public func restore(_ png: Data, for key: SpotImageKey) {
        let url = disk.directory.appendingPathComponent(key.fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: disk.directory, withIntermediateDirectories: true)
            try? png.write(to: url, options: .atomic)
        }
        if key.source == .lookAround {
            disk.writeAvailability(true, spotID: key.spotID,
                                   coordinate: Coordinate(latitude: Double(key.latitudeE5) / 100_000, longitude: Double(key.longitudeE5) / 100_000))
        }
    }

    // MARK: Resolving

    private func resolve(_ request: SpotImageRequest) async -> [SpotImage] {
        var out: [SpotImage] = []
        let size = Self.pixelSize(request)

        if await hasLookAround(spotID: request.spotID, coordinate: request.coordinate) {
            if Task.isCancelled { return out }
            let key = request.key(.lookAround)
            if let image = disk.read(key) {
                out.append(SpotImage(key: key, image: image))
            } else if let raw = await Self.lookAroundSnapshot(at: request.coordinate, pixelSize: size),
                      let image = Self.render(raw, to: size, markerAt: nil) {
                disk.write(image, for: key)
                out.append(SpotImage(key: key, image: image))
            }
        }

        if Task.isCancelled { return out }
        let key = request.key(.satellite)
        if let image = disk.read(key) {
            out.append(SpotImage(key: key, image: image))
        } else if let snap = await Self.satelliteSnapshot(at: request.coordinate, pixelSize: size),
                  let image = Self.render(snap.image, to: size, markerAt: snap.marker) {
            disk.write(image, for: key)
            out.append(SpotImage(key: key, image: image))
        }
        return out
    }

    private static func pixelSize(_ r: SpotImageRequest) -> CGSize {
        let k = r.key(.satellite)
        return CGSize(width: k.pixelWidth, height: k.pixelHeight)
    }

    // MARK: MapKit

    enum SceneResult: Sendable { case available, none, failed }

    /// MapKit's scene and snapshot getters complete on the main actor; the work itself is done by MapKit off-thread.
    @MainActor static func lookAroundScene(at coordinate: Coordinate) async -> SceneResult {
        let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        do {
            return try await request.scene == nil ? .none : .available
        } catch {
            if (error as? MKError)?.code == .placemarkNotFound { return .none }
            return .failed
        }
    }

    @MainActor static func lookAroundSnapshot(at coordinate: Coordinate, pixelSize: CGSize) async -> CGImage? {
        let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard let scene = try? await request.scene else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = pixelSize
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        guard let snapshot = try? await snapshotter.snapshot else { return nil }
        return cgImage(from: snapshot.image)
    }

    /// A hybrid (satellite plus labels) snapshot about 1.2 km wide, plus where the spot falls in it (top-left origin, pixels).
    @MainActor static func satelliteSnapshot(at coordinate: Coordinate, pixelSize: CGSize) async -> (image: CGImage, marker: CGPoint?)? {
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let aspect = pixelSize.height / max(pixelSize.width, 1)
        let widthMeters = 1_200.0
        let region = MKCoordinateRegion(center: center, latitudinalMeters: widthMeters * aspect, longitudinalMeters: widthMeters)
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = pixelSize
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start(), let cg = cgImage(from: snapshot.image) else { return nil }
        let pointSize = snapshot.image.size
        var marker: CGPoint?
        if pointSize.width > 0, pointSize.height > 0 {
            let p = snapshot.point(for: center)
            #if canImport(AppKit)
            // NSImage points have a bottom-left origin in AppKit drawing, but MKMapSnapshot returns image-space points with the top-left origin on iOS and flipped on macOS.
            let y = pointSize.height - p.y
            #else
            let y = p.y
            #endif
            marker = CGPoint(x: p.x / pointSize.width * CGFloat(cg.width), y: y / pointSize.height * CGFloat(cg.height))
        }
        return (cg, marker)
    }

    private static func cgImage(from image: PlatformImage) -> CGImage? {
        #if canImport(AppKit)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    // MARK: Drawing

    /// Aspect-fills `image` into exactly `size` pixels (so files match their key) and optionally draws the spot marker
    /// at `markerAt` (pixels, top-left origin): a white dot with a dark hairline.
    static func render(_ image: CGImage, to size: CGSize, markerAt: CGPoint?) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let fill = max(CGFloat(w) / iw, CGFloat(h) / ih)
        let dw = iw * fill, dh = ih * fill
        let dx = (CGFloat(w) - dw) / 2, dy = (CGFloat(h) - dh) / 2
        ctx.draw(image, in: CGRect(x: dx, y: dy, width: dw, height: dh))
        if let m = markerAt {
            // Map the marker through the same fill transform; the context origin is bottom-left.
            let x = dx + m.x * fill
            let y = CGFloat(h) - (dy + (m.y * fill))
            let r = max(4, CGFloat(min(w, h)) * 0.018)
            ctx.setShadow(offset: .zero, blur: r * 0.8, color: CGColor(gray: 0, alpha: 0.35))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 0.85))
            ctx.setLineWidth(max(1, r * 0.22))
            ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        return ctx.makeImage()
    }
}

#if canImport(AppKit)
private typealias PlatformImage = NSImage
#else
private typealias PlatformImage = UIImage
#endif

/// In-flight work, keyed by request, so two views asking at once run one MapKit job. Each asker is a waiter; the job is
/// cancelled when every waiter has been cancelled.
actor SpotImageJobs {
    struct Waiter: Sendable {
        let id: Int
        let task: Task<[SpotImage], Never>
    }

    private struct Entry {
        var task: Task<[SpotImage], Never>
        /// Waiter id to whether that waiter has been cancelled.
        var waiters: [Int: Bool]
    }

    private var entries: [SpotImageRequest: Entry] = [:]
    private var nextID = 0

    /// Joins the job for `request`, starting it when none is running.
    func join(_ request: SpotImageRequest, start: @escaping @Sendable () async -> [SpotImage]) -> Waiter {
        nextID += 1
        let id = nextID
        // A job whose waiters all left is winding down and will hand back a partial result: start a fresh one.
        if var entry = entries[request], !entry.task.isCancelled {
            entry.waiters[id] = false
            entries[request] = entry
            return Waiter(id: id, task: entry.task)
        }
        let task = Task { await start() }
        entries[request] = Entry(task: task, waiters: [id: false])
        return Waiter(id: id, task: task)
    }

    /// A waiter was cancelled. The job stops when no live waiter is left.
    func abandon(_ request: SpotImageRequest, waiter: Int) {
        guard var entry = entries[request], entry.waiters[waiter] != nil else { return }
        entry.waiters[waiter] = true
        entries[request] = entry
        if entry.waiters.values.allSatisfy({ $0 }) { entry.task.cancel() }
    }

    /// A waiter has its answer (or was cancelled and the job ended). The last one out clears the entry.
    func release(_ request: SpotImageRequest, waiter: Int) {
        guard var entry = entries[request] else { return }
        entry.waiters[waiter] = nil
        if entry.waiters.isEmpty { entries[request] = nil } else { entries[request] = entry }
    }

    /// Jobs still registered (tests).
    var count: Int { entries.count }
}
