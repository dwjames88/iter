import Foundation
import IterModel
import IterSources
import IterStore
import IterDiscovery

/// The sample discovery providers: the curated catalogue answers as a gazetteer, a place search and a geocoder, so Find
/// runs offline and deterministically. Every descriptor is named "Sample ..." so the source chips say so. There is no
/// boundary provider (a park gets a box, as when no outline exists) and no language model (Find shows its Basic search label).
public enum SampleDiscovery {
    public static let gazetteerID: SourceID = "iter.sample.gazetteer"
    public static let placeSearchID: SourceID = "iter.sample.search"
    public static let geocoderID: SourceID = "iter.sample.geocoder"
    static let licence = LicenceTag(key: SampleConditions.licenceKey, mayStore: true)

    static func descriptor(_ id: SourceID, _ name: String, _ kind: DataKind) -> SourceDescriptor {
        SourceDescriptor(id: id, name: name, operatorName: "Built into Iter; curated catalogue", tier: .device,
                         origin: SourceOrigin(tier: .device, producer: "Iter curated catalogue", computedOnDevice: true),
                         kinds: [kind], coverage: .global,
                         policy: RequestPolicy(spacing: .zero, maxConcurrent: 8, timeout: .seconds(5), maxRetries: 0, conditional: false),
                         cacheTTL: .seconds(3600), licence: licence, ranks: [kind: 1])
    }

    /// A catalogue place as a candidate that names `source`.
    static func candidate(_ p: Place, source: SourceID, now: Date) -> PlaceCandidate {
        PlaceCandidate(
            name: p.name, coordinate: p.coordinate, elevationMeters: p.elevationMeters, featureKinds: featureKinds(of: p), source: source,
            externalID: p.curatedID, citations: [Citation(source: source, title: "Sample data: Iter curated catalogue", retrievedAt: now, licence: licence)],
            mentionCount: max(1, p.popularity / 25), snippet: p.blurb.isEmpty ? nil : p.blurb)
    }

    /// What kind of feature a catalogue place is, from its category and tags.
    static func featureKinds(of p: Place) -> [FeatureKind] {
        var out: [FeatureKind] = []
        func add(_ k: FeatureKind) { if !out.contains(k) { out.append(k) } }
        let tags = Set(p.tags)
        if p.category == .waterfall || tags.contains("waterfall") { add(.waterfall) }
        if tags.contains("arch") { add(.arch) }
        if tags.contains("canyon") { add(.canyon) }
        if tags.contains("lake") || tags.contains("alpine-lake") { add(.lake) }
        if tags.contains("bridge") { add(.bridge) }
        if tags.contains("volcano") { add(.peak) }
        if p.category == .coast { add(.beach) }
        if tags.contains("overlook") || tags.contains("viewpoint") || out.isEmpty { add(.viewpoint) }
        return out
    }

    /// The catalogue as the sample "map": the spots `area` contains.
    static func spots(in area: DiscoveryArea) -> [Place] { CuratedSpots.all.filter { area.contains($0.coordinate) } }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
    }

    // MARK: Gazetteer

    public struct Gazetteer: GazetteerProvider {
        public var now: @Sendable () -> Date
        public var descriptor: SourceDescriptor { SampleDiscovery.descriptor(SampleDiscovery.gazetteerID, "Sample places (curated catalogue)", .gazetteer) }
        public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

        public func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
            let t = now()
            return SampleDiscovery.spots(in: area)
                .map { SampleDiscovery.candidate($0, source: SampleDiscovery.gazetteerID, now: t) }
                .filter { features.isEmpty || !features.isDisjoint(with: $0.featureKinds) }
                .prefix(max(0, limit)).map { $0 }
        }
    }

    // MARK: Place search

    public struct PlaceSearch: PlaceSearchProvider {
        public var now: @Sendable () -> Date
        public var descriptor: SourceDescriptor { SampleDiscovery.descriptor(SampleDiscovery.placeSearchID, "Sample place search", .places) }
        public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

        public func search(_ text: String, near region: GeoRegion) async throws -> [PlaceCandidate] {
            let t = now()
            let terms = SampleDiscovery.words(text)
            return CuratedSpots.all.filter { region.contains($0.coordinate) }.filter { p in
                let haystack = ([p.name, p.locality] + p.tags).joined(separator: " ").lowercased()
                return terms.contains { haystack.contains($0) }
            }.map { SampleDiscovery.candidate($0, source: SampleDiscovery.placeSearchID, now: t) }
        }
    }

    // MARK: Geocoder

    public struct SampleGeocoder: Geocoder {
        public var descriptor: SourceDescriptor { SampleDiscovery.descriptor(SampleDiscovery.geocoderID, "Sample place lookup", .geocode) }
        public init() {}

        /// Named areas the sample knows: each locality of the catalogue, centred on its spots, in a box about 60 km wide.
        static let areas: [GeocodeResult] = {
            var byLocality: [String: [Place]] = [:]
            for p in CuratedSpots.all { byLocality[p.locality, default: []].append(p) }
            return byLocality.map { locality, spots in
                let lat = spots.map(\.coordinate.latitude).reduce(0, +) / Double(spots.count)
                let lon = spots.map(\.coordinate.longitude).reduce(0, +) / Double(spots.count)
                let name = locality.components(separatedBy: ",").first ?? locality
                return GeocodeResult(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), formattedAddress: locality,
                                     countryCode: "US", timeZoneIdentifier: spots[0].timeZoneIdentifier,
                                     region: GeoRegion(center: Coordinate(latitude: lat, longitude: lon), latitudeDelta: 0.6, longitudeDelta: 0.6))
            }.sorted { $0.name < $1.name }
        }()

        public func geocode(_ text: String, near region: GeoRegion?) async throws -> [GeocodeResult] {
            let lower = text.lowercased()
            let hits = Self.areas.filter { lower.contains($0.name.lowercased()) }
            // A spot's own name resolves to the spot.
            let spots = CuratedSpots.all.filter { lower.contains($0.name.lowercased()) }.map {
                GeocodeResult(name: $0.name, coordinate: $0.coordinate, formattedAddress: $0.locality, countryCode: "US", timeZoneIdentifier: $0.timeZoneIdentifier)
            }
            return (hits + spots).sorted { $0.name.count > $1.name.count }
        }

        public func reverse(_ coordinate: Coordinate) async throws -> GeocodeResult {
            guard let nearest = CuratedSpots.all.min(by: { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) }),
                  nearest.coordinate.distance(to: coordinate) < 60_000 else { throw SourceError.noSource }
            return GeocodeResult(name: nearest.locality, coordinate: coordinate, formattedAddress: nearest.locality, countryCode: "US",
                                 timeZoneIdentifier: nearest.timeZoneIdentifier)
        }

        public func boundary(of name: String, near coordinate: Coordinate?) async throws -> GeoPolygon? { nil }
    }

    /// The providers for a Find run over the sample catalogue.
    public static func providers(now: @escaping @Sendable () -> Date) -> DiscoveryProviders {
        DiscoveryProviders(geocoders: [SampleGeocoder()], gazetteers: [Gazetteer(now: now)], placeSearch: [PlaceSearch(now: now)])
    }

    public static var descriptors: [SourceDescriptor] {
        [Gazetteer().descriptor, PlaceSearch().descriptor, SampleGeocoder().descriptor]
    }
}

/// Straight-line routing for the sample composition: the straight-line distance times 1.3 at 70 km/h, stamped as an
/// estimate in the route and in the descriptor name.
public struct SampleRouting: RoutingProvider {
    public static let sourceID: SourceID = "iter.sample.routing"
    public var descriptor: SourceDescriptor {
        SourceDescriptor(id: Self.sourceID, name: "Sample routing (straight line estimate)", operatorName: "Built into Iter", tier: .device,
                         origin: SourceOrigin(tier: .device, producer: "Iter straight-line estimate", computedOnDevice: true),
                         kinds: [.routing, .eta], coverage: .global,
                         policy: RequestPolicy(spacing: .zero, maxConcurrent: 8, timeout: .seconds(5), maxRetries: 0, conditional: false),
                         cacheTTL: .seconds(600), licence: LicenceTag(key: SampleConditions.licenceKey, mayStore: true),
                         ranks: [.routing: 1, .eta: 1])
    }
    public init() {}

    public func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        Route(leg: .estimate(from: from, to: to), departing: departing)
    }

    public func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        let leg = Leg.estimate(from: from, to: to)
        return ETA(seconds: leg.seconds, arrival: departing.addingTimeInterval(leg.seconds), departing: departing)
    }
}
