import Foundation
import MapKit
import CoreLocation
import IterCore

/// Conversions between MapKit and IterCore values. MapKit types are not Sendable, so they are converted here
/// and never cross an actor boundary.
enum MapKitMapping {
    static func coordinate(_ c: CLLocationCoordinate2D) -> Coordinate {
        Coordinate(latitude: c.latitude, longitude: c.longitude)
    }

    static func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    static func region(_ r: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: clCoordinate(r.center),
                           span: MKCoordinateSpan(latitudeDelta: min(r.latitudeDelta, 179), longitudeDelta: min(r.longitudeDelta, 359)))
    }

    /// A stable id when MapKit gives no identifier.
    static func fallbackID(_ c: Coordinate, name: String) -> String {
        String(format: "ll:%.5f,%.5f:", c.latitude, c.longitude) + name
    }

    /// "Moab, UT", "Yosemite Valley, CA"; falls back to the short address, then the region name.
    static func locality(of item: MKMapItem) -> String {
        if let reps = item.addressRepresentations {
            if let s = reps.cityWithContext(.short), !s.isEmpty { return s }
            if let s = reps.cityName, !s.isEmpty { return s }
        }
        if let s = item.address?.shortAddress, !s.isEmpty { return s }
        return item.addressRepresentations?.regionName ?? ""
    }

    static func placeResult(from item: MKMapItem) -> PlaceResult {
        let coord = coordinate(item.location.coordinate)
        let name = item.name ?? item.address?.shortAddress ?? coord.cacheKey
        return PlaceResult(
            id: item.identifier?.rawValue ?? fallbackID(coord, name: name),
            name: name,
            locality: locality(of: item),
            coordinate: coord,
            timeZoneIdentifier: item.timeZone?.identifier,
            pointOfInterestCategory: item.pointOfInterestCategory?.rawValue)
    }

    /// Keeps the first occurrence of each id.
    static func unique(_ results: [PlaceResult]) -> [PlaceResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    /// Evenly thinned to at most `maxPoints`, always keeping the first and last point.
    static func downsample(_ points: [Coordinate], maxPoints: Int) -> [Coordinate] {
        guard maxPoints >= 2, points.count > maxPoints else { return points }
        let last = points.count - 1
        return (0..<maxPoints).map { i in points[Int((Double(i) * Double(last) / Double(maxPoints - 1)).rounded())] }
    }

    static func coordinates(of polyline: MKPolyline) -> [Coordinate] {
        let n = polyline.pointCount
        guard n > 0 else { return [] }
        var buffer = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: n)
        polyline.getCoordinates(&buffer, range: NSRange(location: 0, length: n))
        return buffer.map(coordinate)
    }
}

/// Errors from the MapKit-backed services (MapKit's own errors are passed through for anything else).
public enum MapServiceError: Error, Hashable, Sendable {
    case noResult
    case invalidRequest
    /// MapKit kept answering "throttled" after the backoffs.
    case throttled
    case noRoute
}
