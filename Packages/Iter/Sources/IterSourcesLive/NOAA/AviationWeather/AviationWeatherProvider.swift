import Foundation
import IterModel
import IterSources

/// aviationweather.gov METAR and TAF (military airfields included), as station reports and as observations.
///
/// Stations come from one `metar?bbox=S,W,N,E&format=json` request (box half-width = `within`, at most 150 km); when the
/// box (or the circle inside it) is empty it is widened once to twice the size. TAFs for the chosen ids come from one
/// `taf?ids=...&format=raw` request; a failed or empty TAF request just leaves `rawTAF` nil.
public struct AviationWeatherProvider: StationReportProvider, ObservationProvider {
    public static let maxWithinKm = 150.0
    /// Most observations `latest` returns.
    public static let maxObservations = 10

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.aviationWeather) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    // MARK: Requests

    /// The bbox query for a square of half-width `km` around `center`: `S,W,N,E` in degrees (3 decimals).
    public static func metarURL(near center: Coordinate, halfWidthKm km: Double) -> URL {
        let dLat = km / 111.32
        let dLon = km / (111.32 * max(0.05, cos(center.latitude * .pi / 180)))
        let s = max(-90, center.latitude - dLat), n = min(90, center.latitude + dLat)
        let w = max(-180, center.longitude - dLon), e = min(180, center.longitude + dLon)
        let box = [s, w, n, e].map(decimal).joined(separator: ",")
        return URL(string: "https://aviationweather.gov/api/data/metar?bbox=\(box)&format=json")!
    }

    public static func tafURL(ids: [String]) -> URL {
        URL(string: "https://aviationweather.gov/api/data/taf?ids=\(ids.joined(separator: ","))&format=raw")!
    }

    private static func decimal(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    // MARK: StationReportProvider

    public func reports(near coordinate: Coordinate, within km: Double, limit: Int) async throws -> [Sourced<StationReport>] {
        let stations = try await nearestStations(to: coordinate, within: km, limit: limit)
        guard !stations.isEmpty else { return [] }
        var tafs: [String: String] = [:]
        do {
            let r = try await http.send(.get(Self.tafURL(ids: stations.map(\.stationID)), from: descriptor))
            tafs = AviationWeatherMapping.tafs(fromRaw: r.text ?? "")
        } catch let e as SourceError where e != .cancelled {
            // A missing TAF is fine; the METARs are the answer.
        } catch { throw SourceError.wrap(error) }
        let fetchedAt = clock.now
        return stations.map { report in
            var r = report
            r.rawTAF = tafs[r.stationID]
            return Sourced(value: r, provenance: provenance(for: r, fetchedAt: fetchedAt))
        }
    }

    // MARK: ObservationProvider

    public func latest(near coordinate: Coordinate, within km: Double, maxAge: Duration) async throws -> [Sourced<WeatherObservation>] {
        let reports = try await nearestStations(to: coordinate, within: km, limit: Self.maxObservations * 3)
        let now = clock.now
        let oldest = now.addingTimeInterval(-maxAge.timeInterval)
        return reports.filter { $0.observedAt >= oldest }.prefix(Self.maxObservations).map {
            Sourced(value: $0.observation, provenance: provenance(for: $0, fetchedAt: now))
        }
    }

    // MARK: Shared

    /// Nearest `limit` stations within `km` (clamped to 1...150), widening the box once when none are found.
    func nearestStations(to coordinate: Coordinate, within km: Double, limit: Int) async throws -> [StationReport] {
        guard (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else {
            throw SourceError.invalidRequest("coordinate out of range")
        }
        guard limit > 0 else { return [] }
        let radius = min(Self.maxWithinKm, max(1, km))
        for factor in [1.0, 2.0] {
            let reach = radius * factor
            let response: SourceResponse
            do { response = try await http.send(.get(Self.metarURL(near: coordinate, halfWidthKm: reach), from: descriptor)) } catch {
                throw SourceError.wrap(error)
            }
            let found = try AviationWeatherMapping.reports(from: response.body, origin: coordinate)
                .filter { $0.distanceKm <= reach }
            if !found.isEmpty { return Array(found.prefix(limit)) }
        }
        return []
    }

    func provenance(for r: StationReport, fetchedAt: Date) -> Provenance {
        let origin = r.isMilitary
            ? SourceOrigin(tier: .military, producer: "Military airfield weather station",
                           distributor: "NOAA Aviation Weather Center")
            : SourceOrigin(tier: .government, producer: "Civil airport weather station",
                           distributor: "NOAA Aviation Weather Center")
        return descriptor.provenance(
            fetchedAt: fetchedAt, issuedAt: r.observedAt, distanceKm: r.distanceKm,
            url: URL(string: "https://aviationweather.gov/data/metar/?ids=\(r.stationID)"), origin: origin)
    }
}
