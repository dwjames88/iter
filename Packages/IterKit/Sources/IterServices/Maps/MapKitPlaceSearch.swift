import Foundation
import MapKit
import IterCore

/// Place search backed by `MKLocalSearch`.
public struct MapKitPlaceSearch: PlaceSearching {
    public init() {}

    public func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]
        if let region {
            request.region = MapKitMapping.region(region)
        }
        let response = try await MKLocalSearch(request: request).start()
        return MapKitMapping.unique(response.mapItems.map(MapKitMapping.placeResult(from:)))
    }

    public func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] {
        let request = MKLocalPointsOfInterestRequest(center: MapKitMapping.clCoordinate(center), radius: max(1, radiusMeters))
        if !categories.isEmpty {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories.map(MKPointOfInterestCategory.init(rawValue:)))
        }
        let response = try await MKLocalSearch(request: request).start()
        return MapKitMapping.unique(response.mapItems.map(MapKitMapping.placeResult(from:)))
    }
}
