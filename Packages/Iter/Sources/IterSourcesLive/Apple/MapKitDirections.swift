import Foundation
import MapKit
import CoreLocation
import IterModel
import IterSources

/// Driving routes and ETAs through `MKDirections`. `departureDate` is set whenever a departure is given, so MapKit
/// can use traffic for that time. A route with no departure is not marked traffic-aware.
///
/// Errors: throttling -> `.rateLimited`; no route -> `.http(status: 404)`; no network -> `.offline`.
public struct MapKitDirections: RoutingProvider {
    struct RouteSnapshot: Sendable { var path: [Coordinate]; var seconds: TimeInterval; var meters: Double }
    struct ETASnapshot: Sendable { var seconds: TimeInterval; var arrival: Date? }
    typealias FetchRoute = @Sendable (Coordinate, Coordinate, Date?) async throws -> RouteSnapshot
    typealias FetchETA = @Sendable (Coordinate, Coordinate, Date) async throws -> ETASnapshot

    public let descriptor: SourceDescriptor
    private let throttle: MapKitThrottle
    private let fetchRoute: FetchRoute
    private let fetchETA: FetchETA

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.appleDirections) {
        self.init(clock: clock, descriptor: descriptor, fetchRoute: Self.runRoute, fetchETA: Self.runETA)
    }

    init(clock: any SourceClock, descriptor: SourceDescriptor = SourceCatalogue.appleDirections,
         fetchRoute: @escaping FetchRoute, fetchETA: @escaping FetchETA) {
        self.descriptor = descriptor
        self.throttle = MapKitThrottle(policy: descriptor.policy, clock: clock)
        self.fetchRoute = fetchRoute
        self.fetchETA = fetchETA
    }

    public func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        try validate(from, to)
        try await throttle.acquire()
        do {
            let r = try await fetchRoute(from, to, departing)
            return MapKitDirectionsMapping.route(path: r.path, seconds: r.seconds, meters: r.meters, departing: departing, from: from, to: to)
        } catch { throw MapKitErrors.map(error) }
    }

    public func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        try validate(from, to)
        try await throttle.acquire()
        do {
            let e = try await fetchETA(from, to, departing)
            return MapKitDirectionsMapping.eta(seconds: e.seconds, arrival: e.arrival, departing: departing)
        } catch { throw MapKitErrors.map(error) }
    }

    private func validate(_ a: Coordinate, _ b: Coordinate) throws {
        guard MapKitConversion.isValid(a), MapKitConversion.isValid(b) else { throw SourceError.invalidRequest("coordinate out of range") }
        guard descriptor.coverage.contains(a), descriptor.coverage.contains(b) else { throw SourceError.outsideCoverage }
    }

    private static func request(_ a: Coordinate, _ b: Coordinate, _ departing: Date?) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: a.latitude, longitude: a.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: b.latitude, longitude: b.longitude), address: nil)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        if let departing { request.departureDate = departing }
        return request
    }

    private static let runRoute: FetchRoute = { a, b, departing in
        let response = try await MKDirections(request: request(a, b, departing)).calculate()
        guard let route = response.routes.first else { throw SourceError.http(status: 404, excerpt: "directions not found") }
        return RouteSnapshot(path: MapKitConversion.coordinates(of: route.polyline), seconds: route.expectedTravelTime, meters: route.distance)
    }

    private static let runETA: FetchETA = { a, b, departing in
        let response = try await MKDirections(request: request(a, b, departing)).calculateETA()
        return ETASnapshot(seconds: response.expectedTravelTime, arrival: response.expectedArrivalDate)
    }
}
