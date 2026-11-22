import Foundation
import IterModel
import IterSources

/// api.weather.gov: active alerts at a point and the latest observation from the nearest stations (US only).
///
/// Every request sends `Accept: application/geo+json`. A point outside `CoverageShapes.unitedStates` throws
/// `.outsideCoverage` without a request, and so does the API's own 404 InvalidPoint answer from `/points`.
public struct NWSProvider: AlertProvider, ObservationProvider {
    /// Stations tried per call, and observations returned per call.
    public static let maxStationsTried = 5
    public static let maxObservations = 2

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.nwsAPI) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    static let headers = ["Accept": "application/geo+json"]

    /// Coordinates with at most 4 decimals, trailing zeros dropped (the API redirects longer ones).
    static func pair(_ c: Coordinate) -> String { "\(decimal(c.latitude)),\(decimal(c.longitude))" }

    static func decimal(_ v: Double) -> String {
        var s = String(format: "%.4f", (v * 10_000).rounded() / 10_000)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    public static func alertsURL(at c: Coordinate) -> URL { URL(string: "https://api.weather.gov/alerts/active?point=\(pair(c))")! }
    public static func pointsURL(at c: Coordinate) -> URL { URL(string: "https://api.weather.gov/points/\(pair(c))")! }
    public static func latestObservationURL(station: String) -> URL {
        URL(string: "https://api.weather.gov/stations/\(station)/observations/latest")!
    }

    private func get(_ url: URL) async throws -> SourceResponse {
        do { return try await http.send(.get(url, from: descriptor, headers: Self.headers)) } catch { throw SourceError.wrap(error) }
    }

    private func checkCoverage(_ c: Coordinate) throws {
        guard (-90...90).contains(c.latitude), (-180...180).contains(c.longitude) else {
            throw SourceError.invalidRequest("coordinate out of range")
        }
        guard descriptor.coverage.contains(c) else { throw SourceError.outsideCoverage }
    }

    // MARK: AlertProvider

    public func alerts(at coordinate: Coordinate) async throws -> Sourced<[WeatherAlert]> {
        try checkCoverage(coordinate)
        let response = try await get(Self.alertsURL(at: coordinate))
        let mapped = try NWSMapping.alerts(from: response.body)
        let provenance = descriptor.provenance(
            fetchedAt: clock.now, issuedAt: mapped.updated,
            url: URL(string: "https://forecast.weather.gov/MapClick.php?lat=\(Self.decimal(coordinate.latitude))&lon=\(Self.decimal(coordinate.longitude))"))
        return Sourced(value: mapped.alerts, provenance: provenance)
    }

    // MARK: ObservationProvider

    public func latest(near coordinate: Coordinate, within km: Double, maxAge: Duration) async throws -> [Sourced<WeatherObservation>] {
        try checkCoverage(coordinate)
        let points: SourceResponse
        do { points = try await get(Self.pointsURL(at: coordinate)) } catch SourceError.http(let status, _) where status == 404 {
            throw SourceError.outsideCoverage
        }
        let stationsURL = try NWSMapping.observationStationsURL(fromPoints: points.body)
        let stations = try NWSMapping.stations(from: try await get(stationsURL).body)
            .map { ($0, coordinate.distance(to: $0.coordinate) / 1000) }
            .filter { $0.1 <= km }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.maxStationsTried)

        let now = clock.now
        let oldest = now.addingTimeInterval(-maxAge.timeInterval)
        var out: [Sourced<WeatherObservation>] = []
        for (station, distanceKm) in stations {
            if out.count >= Self.maxObservations { break }
            let response: SourceResponse
            do { response = try await get(Self.latestObservationURL(station: station.id)) } catch SourceError.http {
                continue  // this station has no report; try the next one
            }
            guard let latest = try NWSMapping.latestObservation(from: response.body), latest.observation.time >= oldest else { continue }
            var observation = latest.observation
            if observation.stationName == nil { observation.stationName = station.name }
            let provenance = descriptor.provenance(
                fetchedAt: now, issuedAt: observation.time, distanceKm: distanceKm,
                url: URL(string: "https://www.weather.gov/wrh/timeseries?site=\(station.id)"), origin: descriptor.origin)
            out.append(Sourced(value: observation, provenance: provenance))
        }
        return out
    }
}
