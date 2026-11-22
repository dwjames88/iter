import Foundation
import MapKit
import IterModel
import IterSources

/// Points of interest in an area through `MKLocalPointsOfInterestRequest`, filtered by the MapKit categories that
/// the requested `FeatureKind`s map to (see `POICategoryMapping`). Kinds with no MapKit category yield [] with no request.
public struct MapKitPOIGazetteer: GazetteerProvider {
    typealias Execute = @Sendable (GeoRegion, [String]) async throws -> [MapItemRecord]

    public let descriptor: SourceDescriptor
    private let clock: any SourceClock
    private let throttle: MapKitThrottle
    private let execute: Execute

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.applePOI) {
        self.init(clock: clock, descriptor: descriptor, execute: Self.runMapKit)
    }

    init(clock: any SourceClock, descriptor: SourceDescriptor = SourceCatalogue.applePOI, execute: @escaping Execute) {
        self.descriptor = descriptor
        self.clock = clock
        self.throttle = MapKitThrottle(policy: descriptor.policy, clock: clock)
        self.execute = execute
    }

    public func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
        guard limit > 0 else { return [] }
        let categories = POICategoryMapping.categories(for: features).map(\.rawValue)
        guard !categories.isEmpty else { return [] }
        guard descriptor.coverage.contains(area.region.center) else { throw SourceError.outsideCoverage }
        try await throttle.acquire()
        let records: [MapItemRecord]
        do { records = try await execute(area.region, categories) } catch { throw MapKitErrors.map(error) }
        let now = clock.now
        let wanted = features
        return Array(MapKitConversion.unique(records)
            .filter { area.contains($0.coordinate) }
            .compactMap { MapKitPlaceMapping.candidate(from: $0, source: descriptor.id, fetchedAt: now, licence: descriptor.licence) }
            .filter { !wanted.isDisjoint(with: $0.featureKinds) }
            .prefix(limit))
    }

    private static let runMapKit: Execute = { region, categories in
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: MapKitConversion.region(region))
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories.map(MKPointOfInterestCategory.init(rawValue:)))
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(MapItemRecord.init)
    }
}
