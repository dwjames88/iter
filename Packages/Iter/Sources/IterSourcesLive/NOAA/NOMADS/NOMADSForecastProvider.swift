import Foundation
import IterModel
import IterSources

/// NOAA forecasts through the NOMADS GRIB filter (public domain, no key): HRRR (CONUS, 3 km, hourly) stitched into GFS
/// (global, 0.25°). Rows keep each model's native valid times; nothing is interpolated.
///
/// Requests are one small box per (model, cycle, forecast hour), cut around the point's grid cell
/// (see `NOMADSRequestBuilder.box`), so every point in a cell shares them. Raw boxes go through `BlobCaching`, so repeated
/// or overlapping requests cost nothing. The newest cycle is found by trying likely-posted cycles newest first; when an
/// hour of a cycle is not posted (404 "Data file is not present", or 403 "Request for Future Data") that hour comes from
/// the previous cycle of the same model, or from GFS for HRRR. A series is returned if at least one hour could be read.
public actor NOMADSForecastProvider: ForecastProvider, NowcastProvider {
    public nonisolated let descriptor: SourceDescriptor
    let clock: any SourceClock
    let engine: NOMADSEngine

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(), cache: (any BlobCaching)? = nil,
                descriptor: SourceDescriptor = SourceCatalogue.noaaNOMADS) {
        self.descriptor = descriptor
        self.clock = clock
        self.engine = NOMADSEngine(http: http, clock: clock, cache: cache)
    }

    /// The newest cycle of `model` that delivered a file, if any.
    public func lastGoodCycle(_ model: NOMADSModel) async -> Date? { await engine.lastGoodCycle(model) }

    public func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        let useHRRR = CoverageShapes.hrrrDomain.contains(coordinate)
        let rows = try await collect(at: coordinate, span: span, models: useHRRR ? [.hrrr, .gfs] : [.gfs])
        let built = NOMADSSeries.series(rows, source: descriptor.id)
        return Sourced(value: built.series, provenance: NOMADSProvenance.make(descriptor: descriptor, now: clock.now, used: built.used))
    }

    /// The next six hours, from HRRR in its domain (f01 to f06 of the newest cycle) else from GFS.
    public func nowcast(at coordinate: Coordinate) async throws -> Sourced<[NowcastStep]> {
        let start = NOMADSTime.floorHour(clock.now)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(6 * 3600))
        let useHRRR = CoverageShapes.hrrrDomain.contains(coordinate)
        let rows = try await collect(at: coordinate, span: span, models: useHRRR ? [.hrrr, .gfs] : [.gfs])
        let built = NOMADSSeries.series(rows, source: descriptor.id)
        return Sourced(value: built.series.hours.map(NOMADSMapping.nowcastStep),
                       provenance: NOMADSProvenance.make(descriptor: descriptor, now: clock.now, used: built.used))
    }

    private func collect(at coordinate: Coordinate, span: TimeSpan, models: [NOMADSModel]) async throws -> [NOMADSSeries.Row] {
        try await NOMADSCollector.rows(engine: engine, descriptor: descriptor, coordinate: coordinate, span: span, models: models)
    }
}

/// Plan, fetch, map: the part both providers share.
enum NOMADSCollector {
    static func rows(engine: NOMADSEngine, descriptor: SourceDescriptor, coordinate: Coordinate, span: TimeSpan,
                     models: [NOMADSModel]) async throws -> [NOMADSSeries.Row] {
        let plan = await engine.plan(span: span, models: models)
        guard !plan.isEmpty else {
            // Older than the models' retention (about two days of cycles), or past the last forecast hour.
            if span.end < NOMADSTime.floorHour(await engine.now).addingTimeInterval(-48 * 3600) {
                throw SourceError.invalidRequest("the span ends more than two days in the past; NOMADS keeps no such cycle")
            }
            throw SourceError.notPublished("no forecast hours cover \(span.start) to \(span.end)")
        }
        var boxes: [NOMADSModel: NOMADSBox] = [:]
        for m in models { boxes[m] = NOMADSRequestBuilder.box(for: coordinate, model: m) }
        let run = await engine.run(plan, boxes: boxes, descriptor: descriptor)
        if Task.isCancelled { throw SourceError.cancelled }
        var rows: [NOMADSSeries.Row] = []
        for f in run.fetched {
            guard let s = NOMADSMapping.sample(f.file, model: f.ref.model, at: coordinate) else { continue }
            rows.append(NOMADSSeries.Row(ref: f.ref, conditions: s.conditions, distanceKm: s.distanceKm))
        }
        if rows.isEmpty {
            if let e = run.errors.first(where: { if case .decoding = $0 { return false } else { return true } }) ?? run.errors.first {
                throw e
            }
            throw SourceError.notPublished("NOMADS has not posted the requested hours yet")
        }
        // HRRR rows first, so a valid time both models supply keeps HRRR.
        return rows.sorted { a, b in
            if a.ref.model != b.ref.model { return a.ref.model == .hrrr }
            return a.conditions.time < b.conditions.time
        }
    }
}

enum NOMADSProvenance {
    static let url = URL(string: "https://nomads.ncep.noaa.gov/")

    static func make(descriptor: SourceDescriptor, now: Date, used: [NOMADSSeries.Row]) -> Provenance {
        let times = used.map(\.conditions.time)
        let span = times.min().flatMap { lo in times.max().map { TimeSpan(start: lo, end: $0) } }
        return descriptor.provenance(
            fetchedAt: now, model: NOMADSSeries.modelDescription(used.map(\.ref)),
            issuedAt: used.map(\.ref.cycle).max(), validFor: span, distanceKm: used.compactMap(\.distanceKm).min(), url: url)
    }
}
