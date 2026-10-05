import Foundation
import MapKit
import CoreLocation
import IterCore

/// Geocoding with the macOS 26 requests (`MKReverseGeocodingRequest`, `MKGeocodingRequest`); `CLGeocoder` is deprecated.
public struct MapKitGeocoder: Geocoding {
    public init() {}

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { throw MapServiceError.invalidRequest }
        let items = try await request.mapItems
        guard let first = items.first else { throw MapServiceError.noResult }
        return MapKitMapping.placeResult(from: first)
    }

    public func geocode(_ query: String) async throws -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let request = MKGeocodingRequest(addressString: trimmed) else { throw MapServiceError.invalidRequest }
        let items = try await request.mapItems
        return MapKitMapping.unique(items.map(MapKitMapping.placeResult(from:)))
    }
}
