import SwiftUI
import MapKit
import IterAstro
import IterCore
import IterDesign
import IterFeatures

/// Day and night on the map. MapKit has no public time-of-day layer (the macOS 27 and iOS 27 SDKs expose no daylight, lighting or time-of-day setting on MapStyle, MKMapConfiguration or
/// MKMapView), so the night side of
/// the Earth is drawn as a few stacked, very light polygons: the day/night line, civil twilight and nautical twilight,
/// each darkening the one before. Only drawn when the camera is far enough out to see the line.
///
/// To add it to a map (the trip route map, say):
///
///     @State private var daylight = DaylightClock()          // on the view
///     @AppStorage(DaylightClock.storageKey) private var showsDaylight = true
///     if daylight.isShown(isOn: showsDaylight, style: MapStyleChoice(stored: mapStyleRaw)) { DaylightOverlay(daylight.shading) }   // inside Map { ... }
///     .daylightClock(daylight)                               // on the Map, after .mapStyle
struct DaylightOverlay: MapContent {
    let shading: DaylightShading

    init(_ shading: DaylightShading) { self.shading = shading }

    var body: some MapContent {
        ForEach(shading.layers) { layer in
            MapPolygon(coordinates: layer.ring)
                .foregroundStyle(IterColor.skyNight.opacity(layer.opacity))
                .stroke(.clear, lineWidth: 0)
        }
    }
}

/// The night side of the Earth at one moment, ready for MapKit.
struct DaylightShading: Equatable {
    struct Layer: Identifiable, Equatable {
        let id: Int
        let opacity: Double
        let ring: [CLLocationCoordinate2D]
        static func == (a: Layer, b: Layer) -> Bool { a.id == b.id && a.opacity == b.opacity }
    }
    var layers: [Layer] = []

    /// Sun altitude (degrees) and the opacity each band adds: night proper, civil and nautical twilight. The stack
    /// reaches about 40% of the night colour at the darkest, so the map under it stays readable.
    static let bands: [(sunAltitude: Double, opacity: Double)] = [(0, 0.16), (-6, 0.14), (-12, 0.14)]

    init(at date: Date) {
        var id = 0
        for band in Self.bands {
            for polygon in Daylight.nightPolygons(at: date, sunAltitude: band.sunAltitude) {
                layers.append(Layer(id: id, opacity: band.opacity,
                                    ring: polygon.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }))
                id += 1
            }
        }
    }

    init() {}
}

/// What a map needs to show daylight: the current shading (refreshed every five minutes, never per frame) and whether
/// the camera is far enough out for it to be worth drawing. The user's setting is `storageKey`.
@MainActor @Observable
final class DaylightClock {
    /// The `@AppStorage` key for the "Show Daylight" setting (on by default), shared by every map and the style menu.
    nonisolated static let storageKey = "iter.map.daylight"
    /// Camera distance (metres) beyond which the day/night line is drawn: about 2,000 km up.
    nonisolated static let minimumDistance: Double = 2_000_000
    nonisolated static let refreshInterval: Duration = .seconds(300)

    /// Camera distance beyond which MapKit draws satellite and hybrid as a globe, and lights its night side itself (city
    /// lights, from the system clock; no public setting). Standard stays a flat map at any distance (probed, no public API
    /// changes that), so it keeps the overlay.
    nonisolated static let globeDistance: Double = 10_000_000

    private(set) var shading = DaylightShading()
    private(set) var isFarOut = false
    private(set) var isGlobe = false

    /// Whether to draw the overlay now: `isOn` is the host's `@AppStorage(DaylightClock.storageKey)` value. Satellite and
    /// hybrid hand over to MapKit's own night side once the globe appears, so the two never stack.
    func isShown(isOn: Bool, style: MapStyleChoice) -> Bool {
        isOn && isFarOut && !shading.layers.isEmpty && (style == .standard || !isGlobe)
    }

    /// The moment to shade: now, or `-IterDaylightDate <ISO 8601>` for screenshots.
    private var now: Date { AppLaunch.daylightDate ?? Date() }

    func cameraDistanceChanged(_ distance: Double) {
        let globe = distance > Self.globeDistance
        if globe != isGlobe { isGlobe = globe }
        let far = distance > Self.minimumDistance
        guard far != isFarOut else { return }
        isFarOut = far
        if far { refresh() }
    }

    func refresh() {
        guard isFarOut else { return }
        shading = DaylightShading(at: now)
    }

    /// Refreshes every five minutes while the map is on screen.
    func run() async {
        refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.refreshInterval)
            refresh()
        }
    }
}

extension View {
    /// Keeps `clock` informed of the camera distance and refreshing. Apply to the `Map`, after `.mapStyle`.
    func daylightClock(_ clock: DaylightClock) -> some View {
        self
            .onMapCameraChange(frequency: .continuous) { clock.cameraDistanceChanged($0.camera.distance) }
            .task { await clock.run() }
    }
}

extension MapCameraBounds {
    /// Bounds that let the camera zoom all the way out to Apple Maps' globe (MapKit's default limit stops short of it).
    /// Pass to `Map(position:bounds:selection:)`.
    static var globe: MapCameraBounds { MapCameraBounds(maximumDistance: 200_000_000) }
}
