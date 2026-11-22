import Foundation
import MapKit
import IterModel
import IterSources

/// Free-text place search through `MKLocalSearch`. No key, no location permission.
public struct MapKitPlaceSearch: PlaceSearchProvider {
    typealias Execute = @Sendable (String, GeoRegion) async throws -> [MapItemRecord]

    public let descriptor: SourceDescriptor
    private let clock: any SourceClock
    private let throttle: MapKitThrottle
    private let execute: Execute

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.appleSearch) {
        self.init(clock: clock, descriptor: descriptor, execute: Self.runMapKit)
    }

    init(clock: any SourceClock, descriptor: SourceDescriptor = SourceCatalogue.appleSearch, execute: @escaping Execute) {
        self.descriptor = descriptor
        self.clock = clock
        self.throttle = MapKitThrottle(policy: descriptor.policy, clock: clock)
        self.execute = execute
    }

    public func search(_ text: String, near region: GeoRegion) async throws -> [PlaceCandidate] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        guard descriptor.coverage.contains(region.center) else { throw SourceError.outsideCoverage }
        try await throttle.acquire()
        let records: [MapItemRecord]
        do { records = try await execute(query, region) } catch { throw MapKitErrors.map(error) }
        let now = clock.now
        return MapKitConversion.unique(records).compactMap {
            MapKitPlaceMapping.candidate(from: $0, source: descriptor.id, fetchedAt: now, licence: descriptor.licence)
        }
    }

    private static let runMapKit: Execute = { query, region in
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MapKitConversion.region(region)
        request.resultTypes = [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(MapItemRecord.init)
    }
}
