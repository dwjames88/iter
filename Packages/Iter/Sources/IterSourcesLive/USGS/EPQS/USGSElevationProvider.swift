import Foundation
import IterModel
import IterSources

/// USGS 3DEP point elevation (EPQS): metres above sea level from the best DEM (1 m where lidar exists), US only.
///
/// `TerrainProvider.horizon` is not something EPQS can answer (one point per request). It delegates to `horizonSource`
/// when one is injected (for example `TerrariumTerrainProvider`, whose provenance then names Terrarium, not USGS) and
/// otherwise throws `.noSource`.
public struct USGSElevationProvider: TerrainProvider {
    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock
    private let horizonSource: (any TerrainProvider)?

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.usgsEPQS, horizonSource: (any TerrainProvider)? = nil) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
        self.horizonSource = horizonSource
    }

    /// `x` is longitude and `y` latitude, in that order, `wkid=4326`, metres.
    public static func requestURL(for c: Coordinate) -> URL {
        URL(string: "https://epqs.nationalmap.gov/v1/json?x=\(decimal(c.longitude))&y=\(decimal(c.latitude))&units=Meters&wkid=4326")!
    }

    static func decimal(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    public func elevation(at coordinate: Coordinate) async throws -> Sourced<Double> {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite, abs(coordinate.latitude) <= 90,
              abs(coordinate.longitude) <= 180 else { throw SourceError.invalidRequest("coordinate out of range") }
        guard descriptor.coverage.contains(coordinate) else { throw SourceError.outsideCoverage }
        let body: Data
        do { body = try await http.send(.get(Self.requestURL(for: coordinate), from: descriptor)).body } catch {
            throw SourceError.wrap(error)
        }
        let result = try EPQSMapping.elevation(from: body)
        let model = result.resolutionM.map { "USGS 3DEP DEM, \(Self.decimal($0)) m resolution" } ?? "USGS 3DEP DEM"
        let provenance = descriptor.provenance(fetchedAt: clock.now, model: model,
                                               url: URL(string: "https://apps.nationalmap.gov/epqs/"))
        return Sourced(value: result.elevationM, provenance: provenance)
    }

    public func horizon(at coordinate: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile> {
        guard let horizonSource else { throw SourceError.noSource }
        return try await horizonSource.horizon(at: coordinate, azimuthStep: azimuthStep)
    }
}
