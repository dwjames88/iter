import Foundation
import IterModel
import IterSources

/// How the search area was found.
public enum AreaBasis: Sendable, Hashable {
    /// Around the device location.
    case currentLocation(radiusKm: Double)
    /// The map region the user was looking at.
    case visibleMap
    /// A real outline from a boundary source (a park).
    case boundary(name: String, externalID: String?)
    /// A box around a geocoded point: `reason` says why that size ("town", "near phrasing", "point of interest", "drive time").
    case box(radiusKm: Double, reason: String)
    /// The geocoder's own region for a large place with no outline.
    case geocodedRegion
    /// A park, forest, monument or similar whose outline was asked for and not found: the geocoder's region, or a box
    /// of `radiusKm`. Shown as "area box, no outline found".
    case parkBox(radiusKm: Double?)

    /// Plain words for the UI.
    public var label: String {
        switch self {
        case .currentLocation(let r): "around you, \(Int(r)) km"
        case .visibleMap: "the visible map"
        case .boundary(let name, _): "outline of \(name)"
        case .box(let r, let reason): "\(Int(r)) km box (\(reason))"
        case .geocodedRegion: "the place's own region (no outline)"
        case .parkBox: "area box, no outline found"
        }
    }
}

/// The area a run searches, with how it was found and what to cite for it.
public struct ResolvedArea: Sendable, Hashable {
    public var area: DiscoveryArea
    public var basis: AreaBasis
    /// The centre reachability is measured from when the user's own location is not used.
    public var centre: Coordinate
    /// The boundary's citation, when an outline was used.
    public var boundaryCitation: Citation?
    /// What the geocoder returned for the name, when one was used.
    public var geocodedName: String?

    public init(area: DiscoveryArea, basis: AreaBasis, centre: Coordinate, boundaryCitation: Citation? = nil, geocodedName: String? = nil) {
        self.area = area
        self.basis = basis
        self.centre = centre
        self.boundaryCitation = boundaryCitation
        self.geocodedName = geocodedName
    }

    public var hasRealBoundary: Bool { area.boundary?.isEmpty == false }
}

/// Why no area could be resolved: a state the UI shows, never a crash.
public enum AreaFailure: Error, Sendable, Hashable, CustomStringConvertible {
    /// "Near me" without a location.
    case needsLocation
    /// "This area" without a map region.
    case needsMapRegion
    /// A named area mode with no name.
    case noAreaText
    /// No geocoder is available.
    case noGeocoder
    /// The geocoders found nothing for this name.
    case notFound(String)
    /// Every geocoder failed.
    case geocoderFailed(NoDataReason)

    public var description: String {
        switch self {
        case .needsLocation: "Iter needs your location to search near you."
        case .needsMapRegion: "Move the map to the area you want to search."
        case .noAreaText: "Say where to look, for example \"waterfalls in Yosemite\"."
        case .noGeocoder: "No place lookup is available right now."
        case .notFound(let name): "Could not find \"\(name)\"."
        case .geocoderFailed(let reason): "Place lookup failed (\(SourceStatus.describe(reason)))."
        }
    }
}

/// Turns a `QueryPlan` into a `ResolvedArea` using only provider answers: the device location, the map region, a geocoder
/// and boundary sources. No coordinate ever comes from the plan.
struct AreaResolver: Sendable {
    var providers: DiscoveryProviders
    var configuration: DiscoveryConfiguration
    /// Statuses for the geocoder and boundary lookups, reported as they finish.
    var report: @Sendable (SourceStatus) -> Void = { _ in }
    /// The run's clock reading, stamped on a geocoder-supplied outline's citation.
    var now: Date = .distantPast

    // Straight-line radius for a drive time: about 1 km per minute (70 km/h), capped.
    static let kmPerDriveMinute = 1.0
    static let maximumRadiusKm = 250.0
    static let townRadiusKm = 30.0
    static let nearPhrasingRadiusKm = 40.0
    static let pointOfInterestRadiusKm = 10.0
    static let defaultNearMeRadiusKm = 25.0
    /// A named park, forest or monument with no outline and no geocoder region.
    static let parkFallbackRadiusKm = 50.0
    /// A geocoder region at least this big (degrees) counts as "a large place".
    static let largeRegionDegrees = 0.3

    static func radiusKm(forDriveMinutes minutes: Int) -> Double {
        min(maximumRadiusKm, max(1, Double(minutes) * kmPerDriveMinute))
    }

    /// A box of `radiusKm` around `centre`.
    static func box(around centre: Coordinate, radiusKm: Double) -> GeoRegion {
        let latDelta = 2 * radiusKm / 111.0
        let cosLat = max(0.2, cos(centre.latitude * .pi / 180))
        return GeoRegion(center: centre, latitudeDelta: latDelta, longitudeDelta: 2 * radiusKm / (111.0 * cosLat))
    }

    static let areaWords: [String] = [
        "national park", "national forest", "national monument", "national recreation area", "recreation area", "wilderness",
        "state park", "park", "forest", "monument", "preserve", "reserve", "refuge", "seashore", "lakeshore", "national", "nature",
        "conservation", "protected", "state beach", "national scenic",
    ]
    static let pointOfInterestWords: [String] = [
        "point", "overlook", "viewpoint", "arch", "falls", "fall", "lake", "peak", "mount", "mt", "trailhead", "bridge", "lighthouse",
        "castle", "beach", "pass", "dome", "rock", "spire", "tunnel",
    ]

    static func looksLikeArea(_ name: String) -> Bool {
        let lower = " " + DiscoveryNames.tokens(name).joined(separator: " ") + " "
        return areaWords.contains { lower.contains(" " + $0 + " ") }
    }

    static func looksLikePointOfInterest(_ name: String) -> Bool {
        let tokens = Set(DiscoveryNames.tokens(name))
        return pointOfInterestWords.contains { tokens.contains($0) }
    }

    func resolve(plan: QueryPlan, request: DiscoveryRequest, nearPhrasing: Bool) async -> Result<ResolvedArea, AreaFailure> {
        let driveRadius = plan.maxDriveMinutes.map(Self.radiusKm(forDriveMinutes:))
        switch plan.areaMode {
        case .nearMe:
            guard let here = request.currentLocation else { return .failure(.needsLocation) }
            let km = driveRadius ?? Self.defaultNearMeRadiusKm
            let area = DiscoveryArea(name: nil, region: Self.box(around: here, radiusKm: km))
            return .success(ResolvedArea(area: area, basis: .currentLocation(radiusKm: km), centre: here))
        case .mapArea:
            guard let region = request.mapRegion else { return .failure(.needsMapRegion) }
            return .success(ResolvedArea(area: DiscoveryArea(name: nil, region: region), basis: .visibleMap, centre: region.center))
        case .named:
            guard let text = plan.areaText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return .failure(.noAreaText)
            }
            return await resolveNamed(text, plan: plan, request: request, driveRadius: driveRadius, nearPhrasing: nearPhrasing)
        }
    }

    private func resolveNamed(_ text: String, plan: QueryPlan, request: DiscoveryRequest, driveRadius: Double?,
                              nearPhrasing: Bool) async -> Result<ResolvedArea, AreaFailure> {
        guard !providers.geocoders.isEmpty else { return .failure(.noGeocoder) }
        // 1. Geocode inside the map region, first geocoder that answers wins.
        var hit: GeocodeResult?
        var geocoder: (any Geocoder)?
        var lastReason: NoDataReason?
        for g in providers.geocoders {
            guard !Task.isCancelled else { return .failure(.geocoderFailed(.offline(lastGood: nil))) }
            let d = g.descriptor
            report(SourceStatus(source: d.id, name: d.name, role: .geocoder, state: .searching))
            do {
                let results = try await withDeadline(configuration.timeout(for: d)) { try await g.geocode(text, near: request.mapRegion) }
                if let first = results.first {
                    hit = first
                    geocoder = g
                    report(SourceStatus(source: d.id, name: d.name, role: .geocoder, state: .found(results.count)))
                    break
                }
                report(SourceStatus(source: d.id, name: d.name, role: .geocoder, state: .empty))
            } catch is DeadlineExceeded {
                lastReason = .offline(lastGood: nil)
                report(SourceStatus(source: d.id, name: d.name, role: .geocoder, state: .timedOut))
            } catch {
                let e = SourceError.wrap(error)
                if e == .cancelled { return .failure(.geocoderFailed(.offline(lastGood: nil))) }
                lastReason = e.noDataReason(source: d.id)
                report(SourceStatus(source: d.id, name: d.name, role: .geocoder, state: .failed(lastReason!)))
            }
        }
        guard let hit, let geocoder else {
            if let lastReason { return .failure(.geocoderFailed(lastReason)) }
            return .failure(.notFound(text))
        }

        let bigRegion = hit.region.map { $0.latitudeDelta >= Self.largeRegionDegrees || $0.longitudeDelta >= Self.largeRegionDegrees } ?? false
        // 2. A real outline when the name looks like an area, or the geocoder says the place is large.
        if Self.looksLikeArea(text) || Self.looksLikeArea(hit.name) || bigRegion {
            if let outlined = await outline(for: text, hit: hit, geocoder: geocoder) { return .success(outlined) }
        }

        // 3. Otherwise a box sized by the type of place.
        let centre = hit.coordinate
        let namedArea = Self.looksLikeArea(text) || Self.looksLikeArea(hit.name)
        if namedArea, driveRadius == nil {
            // A park we could not outline: say so, and size it like a park rather than a town.
            let region = hit.region ?? Self.box(around: centre, radiusKm: Self.parkFallbackRadiusKm)
            let basis = AreaBasis.parkBox(radiusKm: hit.region == nil ? Self.parkFallbackRadiusKm : nil)
            return .success(ResolvedArea(area: DiscoveryArea(name: text, region: region), basis: basis, centre: centre, geocodedName: hit.name))
        }
        let radius: Double
        let reason: String
        if let driveRadius {
            radius = driveRadius; reason = "drive time"
        } else if nearPhrasing {
            radius = Self.nearPhrasingRadiusKm; reason = "near phrasing"
        } else if Self.looksLikePointOfInterest(text) {
            radius = Self.pointOfInterestRadiusKm; reason = "point of interest"
        } else {
            radius = Self.townRadiusKm; reason = "town"
        }
        var region = Self.box(around: centre, radiusKm: radius)
        var basis = AreaBasis.box(radiusKm: radius, reason: reason)
        if bigRegion, driveRadius == nil, let big = hit.region, big.latitudeDelta > region.latitudeDelta || big.longitudeDelta > region.longitudeDelta {
            region = big
            basis = .geocodedRegion
        }
        let area = DiscoveryArea(name: text, region: region)
        return .success(ResolvedArea(area: area, basis: basis, centre: centre, geocodedName: hit.name))
    }

    /// Asks each boundary source (then the geocoder's own outline) for a real polygon near the geocoded point.
    private func outline(for name: String, hit: GeocodeResult, geocoder: any Geocoder) async -> ResolvedArea? {
        for b in providers.boundaries {
            guard !Task.isCancelled else { return nil }
            let d = b.descriptor
            report(SourceStatus(source: d.id, name: d.name, role: .boundary, state: .searching))
            do {
                let found = try await withDeadline(configuration.timeout(for: d)) { try await b.boundary(named: name, near: hit.coordinate) }
                if let found, Self.plausible(found.polygon, near: hit.coordinate) {
                    report(SourceStatus(source: d.id, name: d.name, role: .boundary, state: .found(1)))
                    let region = found.polygon.boundingRegion
                    return ResolvedArea(area: DiscoveryArea(name: name, region: region, boundary: found.polygon),
                                        basis: .boundary(name: found.name, externalID: found.externalID),
                                        centre: region.center, boundaryCitation: found.citation, geocodedName: hit.name)
                }
                report(SourceStatus(source: d.id, name: d.name, role: .boundary, state: .empty))
            } catch is DeadlineExceeded {
                report(SourceStatus(source: d.id, name: d.name, role: .boundary, state: .timedOut))
            } catch {
                let e = SourceError.wrap(error)
                if e == .cancelled { return nil }
                report(SourceStatus(source: d.id, name: d.name, role: .boundary, state: .failed(e.noDataReason(source: d.id))))
            }
        }
        // The geocoder may know an outline too.
        let gd = geocoder.descriptor
        if let polygon = try? await withDeadline(configuration.timeout(for: gd), { try await geocoder.boundary(of: name, near: hit.coordinate) }),
           Self.plausible(polygon, near: hit.coordinate) {
            let region = polygon.boundingRegion
            let citation = Citation(source: gd.id, title: "\(gd.name): \(name)", retrievedAt: now, licence: gd.licence)
            return ResolvedArea(area: DiscoveryArea(name: name, region: region, boundary: polygon), basis: .boundary(name: name, externalID: nil),
                                centre: region.center, boundaryCitation: citation, geocodedName: hit.name)
        }
        return nil
    }

    /// A returned outline is only used when it is not empty and lies around the geocoded point.
    static func plausible(_ polygon: GeoPolygon, near point: Coordinate) -> Bool {
        guard !polygon.isEmpty else { return false }
        if polygon.contains(point) { return true }
        return polygon.boundingRegion.center.distance(to: point) <= 200_000
    }
}
