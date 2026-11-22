import Foundation
import IterModel
import IterSources

/// HRRR near-surface smoke (MASSDEN, µg/m³) and aerosol optical thickness (AOTK) for CONUS. The files are the same boxes
/// the forecast provider fetches (HRRR requests always include MASSDEN, COLMD and AOTK), so sharing a cache or a provider
/// instance makes smoke free once a forecast was fetched. Outside the HRRR domain it throws `.outsideCoverage` without a
/// request. Rows exist only for valid times HRRR covers (to f18, or f48 on 00/06/12/18Z cycles); beyond that there is no
/// smoke row, because GFS carries no smoke field.
public actor HRRRSmokeProvider: BatchForecastProvider {
    public nonisolated let descriptor: SourceDescriptor
    private let clock: any SourceClock
    private let engine: NOMADSEngine
    private let tiling: NOMADSTiling

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(), cache: (any BlobCaching)? = nil,
                descriptor: SourceDescriptor = SourceCatalogue.noaaHRRRSmoke, tiling: NOMADSTiling = .standard) {
        self.descriptor = descriptor
        self.clock = clock
        self.tiling = tiling
        self.engine = NOMADSEngine(http: http, clock: clock, cache: cache)
    }

    /// Shares the forecast provider's engine (its last-good-cycle memory and cache) and its tiling, so the files are the same.
    public init(sharing forecast: NOMADSForecastProvider, descriptor: SourceDescriptor = SourceCatalogue.noaaHRRRSmoke) {
        self.descriptor = descriptor
        self.clock = forecast.clock
        self.engine = forecast.engine
        self.tiling = forecast.tiling
    }

    public func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        guard descriptor.coverage.contains(coordinate) else { throw SourceError.outsideCoverage }
        let all = try await NOMADSCollector.rows(engine: engine, descriptor: descriptor, coordinate: coordinate, span: span,
                                                 tiling: tiling, hrrrOnly: true)
        return try smoke(from: all)
    }

    /// Many points in one pass, sharing the HRRR tiles like `NOMADSForecastProvider.forecasts(at:span:)`. Points outside
    /// the HRRR domain get `.outsideCoverage` without a request.
    public func forecasts(at coordinates: [Coordinate], span: TimeSpan) async -> [Coordinate: Result<Sourced<HourlySeries>, SourceError>] {
        let covered = coordinates.filter { descriptor.coverage.contains($0) }
        var out: [Coordinate: Result<Sourced<HourlySeries>, SourceError>] = [:]
        for c in coordinates where !descriptor.coverage.contains(c) { out[c] = .failure(.outsideCoverage) }
        let rows = await NOMADSCollector.batchRows(engine: engine, descriptor: descriptor, coordinates: covered, span: span,
                                                   tiling: tiling, hrrrOnly: true)
        for (c, r) in rows {
            switch r {
            case .success(let all):
                do { out[c] = .success(try smoke(from: all)) } catch { out[c] = .failure(SourceError.wrap(error)) }
            case .failure(let e): out[c] = .failure(e)
            }
        }
        return out
    }

    private func smoke(from all: [NOMADSSeries.Row]) throws -> Sourced<HourlySeries> {
        let smoke: [NOMADSSeries.Row] = all.compactMap { r in
            NOMADSMapping.smokeRow(r.conditions).map { NOMADSSeries.Row(ref: r.ref, conditions: $0, distanceKm: r.distanceKm) }
        }
        guard !smoke.isEmpty else { throw SourceError.decoding("HRRR files carry no smoke fields") }
        let built = NOMADSSeries.series(smoke, source: descriptor.id)
        return Sourced(value: built.series, provenance: NOMADSProvenance.make(descriptor: descriptor, now: clock.now, used: built.used))
    }
}
