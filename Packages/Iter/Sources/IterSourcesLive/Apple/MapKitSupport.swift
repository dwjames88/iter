import Foundation
import MapKit
import CoreLocation
import IterModel
import IterSources

/// A Sendable snapshot of an `MKMapItem`. MapKit types are not Sendable, so they are read into this inside the
/// MapKit call and only this crosses an actor boundary.
struct MapItemRecord: Sendable, Hashable {
    var name: String?
    var coordinate: Coordinate
    /// `MKPointOfInterestCategory.rawValue`.
    var categoryRaw: String?
    /// `MKMapItem.identifier?.rawValue`.
    var identifier: String?
    var url: URL?
    var shortAddress: String?
    var fullAddress: String?
    var countryCode: String?
    var timeZoneIdentifier: String?

    init(name: String? = nil, coordinate: Coordinate, categoryRaw: String? = nil, identifier: String? = nil, url: URL? = nil,
         shortAddress: String? = nil, fullAddress: String? = nil, countryCode: String? = nil, timeZoneIdentifier: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.categoryRaw = categoryRaw
        self.identifier = identifier
        self.url = url
        self.shortAddress = shortAddress
        self.fullAddress = fullAddress
        self.countryCode = countryCode
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(_ item: MKMapItem) {
        let c = item.location.coordinate
        self.init(name: item.name,
                  coordinate: Coordinate(latitude: c.latitude, longitude: c.longitude),
                  categoryRaw: item.pointOfInterestCategory?.rawValue,
                  identifier: item.identifier?.rawValue,
                  url: item.url,
                  shortAddress: item.address?.shortAddress,
                  fullAddress: item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) ?? item.address?.fullAddress,
                  countryCode: item.addressRepresentations?.region?.identifier,
                  timeZoneIdentifier: item.timeZone?.identifier)
    }
}

/// Pure helpers shared by the MapKit adapters.
enum MapKitConversion {
    static func coordinate(_ c: CLLocationCoordinate2D) -> Coordinate {
        Coordinate(latitude: c.latitude, longitude: c.longitude)
    }

    static func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    /// Spans are clamped to what `MKCoordinateRegion` accepts (179 and 359 degrees).
    static func region(_ r: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: clCoordinate(r.center),
                           span: MKCoordinateSpan(latitudeDelta: min(max(r.latitudeDelta, 0.0001), 179),
                                                  longitudeDelta: min(max(r.longitudeDelta, 0.0001), 359)))
    }

    /// `[CLLocationCoordinate2D]` to model coordinates.
    static func coordinates(_ points: [CLLocationCoordinate2D]) -> [Coordinate] { points.map(coordinate) }

    static func coordinates(of polyline: MKPolyline) -> [Coordinate] {
        let n = polyline.pointCount
        guard n > 0 else { return [] }
        var buffer = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: n)
        polyline.getCoordinates(&buffer, range: NSRange(location: 0, length: n))
        return coordinates(buffer)
    }

    /// Evenly thinned to at most `maxPoints`, always keeping the first and last point.
    static func downsample(_ points: [Coordinate], maxPoints: Int) -> [Coordinate] {
        guard maxPoints >= 2, points.count > maxPoints else { return points }
        let last = points.count - 1
        return (0..<maxPoints).map { points[Int((Double($0) * Double(last) / Double(maxPoints - 1)).rounded())] }
    }

    /// Valid latitude/longitude, finite.
    static func isValid(_ c: Coordinate) -> Bool {
        c.latitude.isFinite && c.longitude.isFinite && abs(c.latitude) <= 90 && abs(c.longitude) <= 180
    }

    /// Keeps the first record for each identifier (or, with none, each name and position).
    static func unique(_ records: [MapItemRecord]) -> [MapItemRecord] {
        var seen = Set<String>()
        return records.filter { r in
            seen.insert(r.identifier ?? ((r.name ?? "") + "@" + r.coordinate.cacheKey)).inserted
        }
    }
}

/// MapKit errors to `SourceError`.
///
/// - `loadingThrottled` -> `.rateLimited(retryAfter: nil)` (MapKit does not say when).
/// - `placemarkNotFound`, `directionsNotFound` -> `.http(status: 404, excerpt:)`: the service answered, nothing matched.
/// - `serverFailure` -> `.http(status: 503, excerpt:)`.
/// - `decodingFailed` -> `.decoding`.
/// - `CLError.network`, URL errors -> `.offline` / `.timedOut` via `SourceError.wrap`.
enum MapKitErrors {
    static func map(_ error: any Error) -> SourceError {
        if let e = error as? SourceError { return e }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == MKError.errorDomain, let code = MKError.Code(rawValue: UInt(bitPattern: ns.code)) {
            switch code {
            case .loadingThrottled: return .rateLimited(retryAfter: nil)
            case .placemarkNotFound: return .http(status: 404, excerpt: "placemark not found")
            case .directionsNotFound: return .http(status: 404, excerpt: "directions not found")
            case .serverFailure: return .http(status: 503, excerpt: "MapKit server failure")
            case .decodingFailed: return .decoding("MapKit response could not be decoded")
            default: return .http(status: -1, excerpt: "MapKit error \(ns.code)")
            }
        }
        if ns.domain == kCLErrorDomain, let code = CLError.Code(rawValue: ns.code) {
            switch code {
            case .network: return .offline
            case .geocodeFoundNoResult: return .http(status: 404, excerpt: "no geocode result")
            default: break
            }
        }
        return SourceError.wrap(error)
    }
}

/// A small local politeness guard: at least `spacing` between request starts and at most `perMinute` in any rolling
/// minute. Over the minute cap it throws `.rateLimited(retryAfter:)` instead of sleeping for up to a minute.
actor MapKitThrottle {
    private let spacing: Duration
    private let perMinute: Int?
    private let clock: any SourceClock
    private var starts: [Date] = []

    init(policy: RequestPolicy, clock: any SourceClock) {
        spacing = policy.spacing
        perMinute = policy.perMinute
        self.clock = clock
    }

    func acquire() async throws {
        let now = clock.now
        starts.removeAll { now.timeIntervalSince($0) >= 60 }
        if let perMinute, starts.count >= perMinute, let oldest = starts.first {
            throw SourceError.rateLimited(retryAfter: oldest.addingTimeInterval(60))
        }
        if let last = starts.last {
            let wait = spacing.timeInterval - now.timeIntervalSince(last)
            if wait > 0 { try await clock.sleep(for: .interval(wait)) }
        }
        // Reserve the slot at the time we actually proceed so concurrent callers queue behind it.
        starts.append(clock.now)
    }
}
