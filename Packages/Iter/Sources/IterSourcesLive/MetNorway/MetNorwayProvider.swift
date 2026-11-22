import Foundation
import IterModel
import IterSources

/// MET Norway locationforecast 2.0 (`complete`): the global model forecast with cloud layers.
///
/// Terms: coordinates are rounded to 4 decimals (5 or more gets HTTP 403), no cache-busting parameters are added, and
/// `SourceHTTP` (not this type) honours `Expires` and sends conditional requests per the descriptor's policy.
public struct MetNorwayProvider: ForecastProvider {
    public static let modelName = "MET Norway locationforecast 2.0"

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.metNorway) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    /// `lat`/`lon` rounded to at most 4 decimals, trailing zeros dropped, in that order and with no other parameters.
    public static func requestURL(for coordinate: Coordinate) -> URL {
        let lat = decimal(coordinate.latitude)
        let lon = decimal(coordinate.longitude)
        return URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=\(lat)&lon=\(lon)")!
    }

    /// A human page for the place (yr.no accepts `lat,lon`).
    public static func humanURL(for coordinate: Coordinate) -> URL? {
        URL(string: "https://www.yr.no/en/forecast/daily-table/\(decimal(coordinate.latitude)),\(decimal(coordinate.longitude))")
    }

    static func decimal(_ v: Double) -> String {
        var s = String(format: "%.4f", (v * 10_000).rounded() / 10_000)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    public func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        guard (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else {
            throw SourceError.invalidRequest("coordinate out of range")
        }
        guard descriptor.coverage.contains(coordinate) else { throw SourceError.outsideCoverage }
        let response: SourceResponse
        do { response = try await http.send(.get(Self.requestURL(for: coordinate), from: descriptor)) } catch {
            throw SourceError.wrap(error)
        }
        let forecast = try MetNorwayMapping.forecast(from: response.body, span: span)
        var fields: [HourlyField: SourceID] = [:]
        for row in forecast.hours { for f in row.presentFields { fields[f] = descriptor.id } }
        let provenance = descriptor.provenance(
            fetchedAt: clock.now, model: Self.modelName, issuedAt: forecast.updatedAt, validFor: span,
            url: Self.humanURL(for: coordinate))
        return Sourced(value: HourlySeries(hours: forecast.hours, fieldSources: fields), provenance: provenance)
    }
}
