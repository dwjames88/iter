import Foundation
import MapKit
import CoreLocation
import IterModel
import IterSources

/// Forward and reverse geocoding through `MKGeocodingRequest` and `MKReverseGeocodingRequest` (the 26 SDK
/// replacements for the deprecated `CLGeocoder`). No location permission is needed.
public struct MapKitGeocoder: Geocoder {
    typealias Forward = @Sendable (String, GeoRegion?) async throws -> [MapItemRecord]
    typealias Reverse = @Sendable (Coordinate) async throws -> [MapItemRecord]

    public let descriptor: SourceDescriptor
    private let throttle: MapKitThrottle
    private let forward: Forward
    private let reverseLookup: Reverse

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.appleGeocoder) {
        self.init(clock: clock, descriptor: descriptor, forward: Self.runForward, reverse: Self.runReverse)
    }

    init(clock: any SourceClock, descriptor: SourceDescriptor = SourceCatalogue.appleGeocoder,
         forward: @escaping Forward, reverse: @escaping Reverse) {
        self.descriptor = descriptor
        self.throttle = MapKitThrottle(policy: descriptor.policy, clock: clock)
        self.forward = forward
        self.reverseLookup = reverse
    }

    public func geocode(_ text: String, near region: GeoRegion?) async throws -> [GeocodeResult] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        try await throttle.acquire()
        do {
            return MapKitConversion.unique(try await forward(query, region)).map(MapKitPlaceMapping.geocodeResult(from:))
        } catch { throw MapKitErrors.map(error) }
    }

    public func reverse(_ coordinate: Coordinate) async throws -> GeocodeResult {
        guard MapKitConversion.isValid(coordinate) else { throw SourceError.invalidRequest("coordinate out of range") }
        try await throttle.acquire()
        let records: [MapItemRecord]
        do { records = try await reverseLookup(coordinate) } catch { throw MapKitErrors.map(error) }
        guard let first = records.first else { throw SourceError.http(status: 404, excerpt: "no reverse geocode result") }
        return MapKitPlaceMapping.geocodeResult(from: first)
    }

    /// MapKit returns points and addresses, never outlines, so this is always nil (no request is made).
    public func boundary(of name: String, near coordinate: Coordinate?) async throws -> GeoPolygon? { nil }

    private static let runForward: Forward = { text, region in
        guard let request = MKGeocodingRequest(addressString: text) else { throw SourceError.invalidRequest("address string") }
        if let region { request.region = MapKitConversion.region(region) }
        return try await request.mapItems.map(MapItemRecord.init)
    }

    private static let runReverse: Reverse = { coordinate in
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { throw SourceError.invalidRequest("location") }
        return try await request.mapItems.map(MapItemRecord.init)
    }
}
