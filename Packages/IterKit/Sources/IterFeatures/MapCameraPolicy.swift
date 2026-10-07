import Foundation
import IterCore

/// When a map moves itself, and when it must leave the camera alone. Pure and generic (coordinates in, regions out):
/// Explore uses it now and the trip builder's route map can reuse it.
///
/// Rules:
/// - An automatic fit never zooms out past `maxAutomaticSpan` degrees (a continent, never the world). A set wider than
///   that is fitted by its densest cluster: the group of points that fit one capped window together, most points first,
///   earliest point on a tie. Points outside the cluster stay on the map; the user can zoom out to see them.
/// - Once the user moves or zooms the map after a fit, content changes do not refit (`regionAfterContentChange` is nil)
///   until a fit is applied again.
/// - Selecting a spot zooms to a `selectionRadiusMiles` radius around it, or only pans when the map is already closer
///   than that (`selectionRegion`). Like every request of our own, it is programmatic, never a user move.
/// - The last settled camera is saved per screen, so the next visit starts where the user left off.
/// - Antimeridian wrap is not handled (spots spanning ±180° would be fitted by their raw longitudes).
public struct MapCameraPolicy: Codable, Equatable, Sendable {
    /// The most an automatic fit may show, in degrees of latitude and of longitude (about a continent).
    public static let maxAutomaticSpan = 40.0
    /// The least an automatic fit may show, so one pin does not zoom to street level.
    public static let minimumSpan = 0.5
    /// Padding around fitted points, as a fraction of their extent.
    public static let fitPadding = 0.25
    /// A settled camera counts as "the fit" when its centre is within this fraction of its span of the fit's centre
    /// and the zoom matches within `zoomTolerance`.
    public static let centerTolerance = 0.2
    /// Allowed relative zoom drift (MapKit adjusts a requested region to the pane's aspect ratio).
    public static let zoomTolerance = 0.25
    /// How close to an edge a point may sit before `pan` moves the camera, as a fraction of the span.
    public static let defaultPanMargin = 0.15

    /// The radius shown around a spot when it is selected, in statute miles. The one value every screen uses.
    public static let selectionRadiusMiles = 25.0
    /// Metres in a statute mile.
    public static let metersPerMile = 1609.344
    /// The span a selection shows on the map's shorter side: twice the radius (80,467.2 m, 50 mi).
    public static let selectionSpanMeters = selectionRadiusMiles * 2 * metersPerMile
    private static let metersPerDegreeLatitude = 111_320.0

    /// The region of the last automatic fit (or pan that kept it current).
    public private(set) var lastFitRegion: GeoRegion?
    /// True once the settled camera differs from the last fit.
    public private(set) var userMovedSinceFit = false
    /// The last settled camera, whoever moved it.
    public private(set) var savedRegion: GeoRegion?

    /// True when `savedRegion` is a camera the user chose (a settle flagged `byUser`). A wide saved camera that is not
    /// user-chosen is never restored.
    public private(set) var savedByUser = false

    /// Bumped when stored state may be corrupt; policies saved under another version are discarded on load.
    /// (Version 2: earlier builds saved MapKit's automatic world camera as the user's own.
    /// Version 3: MapKit's own layout settles were still saved as user moves, leaving world-wide cameras.)
    public static let currentVersion = 3
    public private(set) var version = MapCameraPolicy.currentVersion
    /// True from a programmatic camera change until the camera next settles where we asked. Not persisted.
    public private(set) var programmaticSettlePending = false
    /// The camera we last asked the map for (fit, restore or pan). Not persisted.
    public private(set) var intendedRegion: GeoRegion?
    /// Re-applications of `intendedRegion` since the last request of our own. Not persisted.
    private var reapplyAttempts = 0
    /// How many times a settle that missed our region is answered by asking again.
    public static let maxReapplyAttempts = 3

    /// What a settle means for the caller.
    public enum SettleOutcome: Equatable, Sendable {
        /// Recorded; the caller should persist the policy.
        case saved
        /// Not ours to record (a layout settle, or MapKit missed our region and we gave up asking).
        case ignored
        /// MapKit settled somewhere other than the camera we asked for (its default camera before the pane had a size,
        /// say): send this region to the map again. Nothing was saved.
        case reapply(GeoRegion)
    }

    private enum CodingKeys: String, CodingKey { case version, lastFitRegion, userMovedSinceFit, savedRegion, savedByUser }

    public init() {}

    /// Equal when the persisted state is equal (in-flight bookkeeping is not part of a policy's identity).
    public static func == (a: MapCameraPolicy, b: MapCameraPolicy) -> Bool {
        a.version == b.version && a.lastFitRegion == b.lastFitRegion && a.userMovedSinceFit == b.userMovedSinceFit
            && a.savedRegion == b.savedRegion && a.savedByUser == b.savedByUser
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        lastFitRegion = try c.decodeIfPresent(GeoRegion.self, forKey: .lastFitRegion)
        userMovedSinceFit = try c.decodeIfPresent(Bool.self, forKey: .userMovedSinceFit) ?? false
        savedRegion = try c.decodeIfPresent(GeoRegion.self, forKey: .savedRegion)
        savedByUser = try c.decodeIfPresent(Bool.self, forKey: .savedByUser) ?? false
    }

    // MARK: Pure rules

    /// The region that shows `coordinates`, padded, no smaller than `minimumSpan` and no larger than
    /// `maxAutomaticSpan` (see the type's rules for wider sets).
    public static func fit(_ coordinates: [Coordinate]) -> GeoRegion? {
        guard !coordinates.isEmpty else { return nil }
        let usable = maxAutomaticSpan / (1 + fitPadding)
        let region = GeoRegion.enclosing(coordinates, padding: fitPadding, minimumDelta: minimumSpan)
        if let region, region.latitudeDelta <= maxAutomaticSpan, region.longitudeDelta <= maxAutomaticSpan { return region }
        return GeoRegion.enclosing(densestCluster(coordinates, window: usable), padding: fitPadding, minimumDelta: minimumSpan)
    }

    /// The points that fit one `window`-degree box together, as many as possible.
    static func densestCluster(_ coordinates: [Coordinate], window: Double) -> [Coordinate] {
        var best: [Coordinate] = []
        for anchor in coordinates {
            let members = coordinates.filter {
                abs($0.latitude - anchor.latitude) <= window / 2 && abs($0.longitude - anchor.longitude) <= window / 2
            }
            if members.count > best.count { best = members }
        }
        return best
    }

    /// Moves the centre just enough to bring `coordinate` inside the inner margin; the span never changes.
    /// `margins` are fractions of the span kept clear at each edge (a larger bottom keeps a pin above a card).
    public static func pan(_ current: GeoRegion, toInclude coordinate: Coordinate,
                           margins: Margins = Margins()) -> GeoRegion {
        var center = current.center
        let latHalf = current.latitudeDelta / 2
        let lonHalf = current.longitudeDelta / 2
        let top = center.latitude + latHalf - current.latitudeDelta * margins.top
        let bottom = center.latitude - latHalf + current.latitudeDelta * margins.bottom
        if coordinate.latitude > top { center.latitude += coordinate.latitude - top }
        else if coordinate.latitude < bottom { center.latitude -= bottom - coordinate.latitude }
        let leading = center.longitude - lonHalf + current.longitudeDelta * margins.leading
        let trailing = center.longitude + lonHalf - current.longitudeDelta * margins.trailing
        if coordinate.longitude < leading { center.longitude -= leading - coordinate.longitude }
        else if coordinate.longitude > trailing { center.longitude += coordinate.longitude - trailing }
        center.latitude = min(85, max(-85, center.latitude))
        return GeoRegion(center: center, latitudeDelta: current.latitudeDelta, longitudeDelta: current.longitudeDelta)
    }

    /// The visible region's shorter side in metres (longitude shrinks with latitude).
    static func shorterSideMeters(_ region: GeoRegion) -> Double {
        let height = region.latitudeDelta * metersPerDegreeLatitude
        let width = region.longitudeDelta * metersPerDegreeLatitude * cos(region.center.latitude * .pi / 180)
        return min(height, width)
    }

    /// The camera for selecting a spot, given the map as it is (`current`, nil when unknown).
    /// - Wider than `selectionSpanMeters` on the shorter side (or unknown): centred on the spot, the shorter side
    ///   exactly that span so the whole radius is visible, the other side in the map's own proportions.
    /// - Already closer: centred on the spot at the current span (a pan only).
    public static func selectionRegion(current: GeoRegion?, spot: Coordinate) -> GeoRegion {
        let center = Coordinate(latitude: min(85, max(-85, spot.latitude)), longitude: spot.longitude)
        if let current, shorterSideMeters(current) < selectionSpanMeters {
            return GeoRegion(center: center, latitudeDelta: current.latitudeDelta, longitudeDelta: current.longitudeDelta)
        }
        let cosLat = max(0.01, cos(center.latitude * .pi / 180))
        let spanLatitude = selectionSpanMeters / metersPerDegreeLatitude
        let spanLongitude = spanLatitude / cosLat
        guard let current else { return GeoRegion(center: center, latitudeDelta: spanLatitude, longitudeDelta: spanLongitude) }
        let height = current.latitudeDelta * metersPerDegreeLatitude
        let width = current.longitudeDelta * metersPerDegreeLatitude * cos(current.center.latitude * .pi / 180)
        let aspect = height > 0 ? max(1, width / height) : 1       // width over height, as shown
        let inverse = width > 0 ? max(1, height / width) : 1       // height over width, as shown
        return height <= width
            ? GeoRegion(center: center, latitudeDelta: spanLatitude, longitudeDelta: spanLongitude * aspect)
            : GeoRegion(center: center, latitudeDelta: spanLatitude * inverse, longitudeDelta: spanLongitude)
    }

    public struct Margins: Equatable, Sendable {
        public var top: Double, leading: Double, bottom: Double, trailing: Double
        public init(top: Double = MapCameraPolicy.defaultPanMargin, leading: Double = MapCameraPolicy.defaultPanMargin,
                    bottom: Double = MapCameraPolicy.defaultPanMargin, trailing: Double = MapCameraPolicy.defaultPanMargin) {
            self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
        }
    }

    // MARK: State

    /// Records that `region` was sent to the map as an automatic fit; the user has not moved it yet.
    public mutating func didApplyFit(_ region: GeoRegion) {
        lastFitRegion = region
        userMovedSinceFit = false
        savedByUser = false
        beginRequest(region)
    }

    /// Records that the saved camera was sent to the map again (a restore): its settle is ours, not the user's.
    public mutating func didRestoreSavedCamera() {
        if let savedRegion { beginRequest(savedRegion) } else { programmaticSettlePending = true }
    }

    /// Records a programmatic pan (it does not zoom). While the user has not taken over, the pan counts as the fit,
    /// so the settle that follows is not mistaken for a user move.
    public mutating func didApplyPan(_ region: GeoRegion) {
        if !userMovedSinceFit { lastFitRegion = region }
        beginRequest(region)
    }

    /// Records that a selection camera (`selectionRegion`) was sent to the map. It is programmatic, so its settle is
    /// not a user move; while the user has not taken over it counts as the fit.
    public mutating func didApplySelection(_ region: GeoRegion) { didApplyPan(region) }

    private mutating func beginRequest(_ region: GeoRegion) {
        intendedRegion = region
        programmaticSettlePending = true
        reapplyAttempts = 0
    }

    /// The camera came to rest at `region`.
    /// - `byUser`: the user really moved the map (SwiftUI reported `positionedByUser`). Always saved, always a user move.
    /// - Anything else is MapKit's own doing and is never a user move. It is recorded (and saved) only when it is the
    ///   camera we asked for, allowing for the pane's aspect ratio. When we asked and MapKit settled elsewhere, the
    ///   result is `.reapply` (up to `maxReapplyAttempts` times), and nothing is saved.
    @discardableResult
    public mutating func cameraSettled(_ region: GeoRegion, byUser: Bool = false) -> SettleOutcome {
        if byUser {
            savedRegion = region
            savedByUser = true
            programmaticSettlePending = false
            userMovedSinceFit = true
            return .saved
        }
        // With no request of ours in flight, a user who has taken over keeps their camera through layout settles.
        guard programmaticSettlePending || !userMovedSinceFit else { return .ignored }
        guard let intended = intendedRegion else {
            // Nothing asked for: MapKit's default camera. Remember nothing.
            return .ignored
        }
        if Self.matches(region, intended) {
            programmaticSettlePending = false
            savedRegion = region
            if !userMovedSinceFit { lastFitRegion = region }
            return .saved
        }
        guard reapplyAttempts < Self.maxReapplyAttempts else { return .ignored }
        reapplyAttempts += 1
        programmaticSettlePending = true
        return .reapply(intended)
    }

    /// Where a screen should start: the saved camera, else a fit of `coordinates`.
    public func initialRegion(for coordinates: [Coordinate]) -> GeoRegion? {
        savedRegion ?? Self.fit(coordinates)
    }

    /// The new fit after the content changed, or nil when the user has moved the map since the last fit
    /// (the fit is recorded as applied when returned).
    public mutating func regionAfterContentChange(_ coordinates: [Coordinate]) -> GeoRegion? {
        guard !userMovedSinceFit, let region = Self.fit(coordinates) else { return nil }
        didApplyFit(region)
        return region
    }

    /// The new fit after a location fix arrived. Like `regionAfterContentChange`, but a recorded user move is only
    /// believed while the camera really is somewhere else: a settle MapKit made on its own (the pane resizing at
    /// launch, an aspect adjustment) can be mistaken for a user move, and must not block the first Near You fit.
    /// `visible` is the camera as last reported.
    public mutating func regionAfterLocationFix(_ coordinates: [Coordinate], visible: GeoRegion?) -> GeoRegion? {
        guard let region = Self.fit(coordinates) else { return nil }
        if userMovedSinceFit {
            guard let fit = lastFitRegion, let visible, Self.matches(visible, fit) else { return nil }
        }
        didApplyFit(region)
        return region
    }

    /// The settled camera shows what the fit asked for: same centre, and the binding axis at the same zoom (MapKit may
    /// widen the other axis to the pane's shape, but never narrows both).
    static func matches(_ settled: GeoRegion, _ fit: GeoRegion) -> Bool {
        let centerOK = abs(settled.center.latitude - fit.center.latitude) <= settled.latitudeDelta * centerTolerance
            && abs(settled.center.longitude - fit.center.longitude) <= settled.longitudeDelta * centerTolerance
        guard fit.latitudeDelta > 0, fit.longitudeDelta > 0 else { return centerOK }
        let zoom = min(settled.latitudeDelta / fit.latitudeDelta, settled.longitudeDelta / fit.longitudeDelta)
        return centerOK && abs(zoom - 1) <= zoomTolerance
    }

    // MARK: Persistence

    public static func storageKey(_ screen: String) -> String { "IterMapCamera.\(screen)" }

    /// The policy saved for `screen`, or a fresh one.
    public static func load(screen: String, defaults: UserDefaults = .standard) -> MapCameraPolicy {
        guard let data = defaults.data(forKey: storageKey(screen)),
              let policy = try? JSONDecoder().decode(MapCameraPolicy.self, from: data),
              policy.version == currentVersion else { return MapCameraPolicy() }
        return policy.droppingUnchosenWideCamera()
    }

    /// A saved camera wider than an automatic fit may be is only believed when the user chose it.
    func droppingUnchosenWideCamera() -> MapCameraPolicy {
        var policy = self
        if let saved = savedRegion, !savedByUser,
           saved.latitudeDelta > Self.maxAutomaticSpan || saved.longitudeDelta > Self.maxAutomaticSpan {
            policy.savedRegion = nil
        }
        return policy
    }

    public func save(screen: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey(screen))
    }
}
