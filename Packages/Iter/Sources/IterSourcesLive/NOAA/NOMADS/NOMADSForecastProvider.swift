import Foundation
import IterModel
import IterSources

/// NOAA forecasts through the NOMADS GRIB filter (public domain, no key): HRRR (CONUS, 3 km, hourly) stitched into GFS
/// (global, 0.25°). Rows keep each model's native valid times; nothing is interpolated.
///
/// Requests are one box per (model, cycle, forecast hour), cut around the point's tile (see `NOMADSTiling` and
/// `NOMADSRequestBuilder.box`), so every point in a tile shares them. `forecasts(at:span:)` serves many points in one pass:
/// it plans the hours once, fetches each (tile, hour) once, near hours first, and samples every point from the shared
/// files. Raw boxes go through `BlobCaching`, so repeated or overlapping requests cost nothing. The newest cycle is found by trying likely-posted cycles newest first; when an
/// hour of a cycle is not posted (404 "Data file is not present", or 403 "Request for Future Data") that hour comes from
/// the previous cycle of the same model, or from GFS for HRRR. A series is returned if at least one hour could be read.
public actor NOMADSForecastProvider: BatchForecastProvider, NowcastProvider {
    public nonisolated let descriptor: SourceDescriptor
    let clock: any SourceClock
    let engine: NOMADSEngine
    let tiling: NOMADSTiling

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(), cache: (any BlobCaching)? = nil,
                descriptor: SourceDescriptor = SourceCatalogue.noaaNOMADS, tiling: NOMADSTiling = .standard) {
        self.descriptor = descriptor
        self.clock = clock
        self.tiling = tiling
        self.engine = NOMADSEngine(http: http, clock: clock, cache: cache)
    }

    /// The newest cycle of `model` that delivered a file, if any.
    public func lastGoodCycle(_ model: NOMADSModel) async -> Date? { await engine.lastGoodCycle(model) }

    public func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        let rows = try await NOMADSCollector.rows(engine: engine, descriptor: descriptor, coordinate: coordinate, span: span,
                                                  tiling: tiling)
        return series(from: rows)
    }

    /// Many points in one pass. Points in the same tile share every download; the hours are planned once and fetched near
    /// term first (every tile's earliest hour before any tile's later hour). One entry per distinct coordinate: a series,
    /// or that point's error. Cancelling stops the remaining downloads (files already fetched stay cached).
    public func forecasts(at coordinates: [Coordinate], span: TimeSpan) async -> [Coordinate: Result<Sourced<HourlySeries>, SourceError>] {
        let rows = await NOMADSCollector.batchRows(engine: engine, descriptor: descriptor, coordinates: coordinates, span: span,
                                                   tiling: tiling, hrrrOnly: false)
        return rows.mapValues { $0.map { series(from: $0) } }
    }

    /// The next six hours, from HRRR in its domain (f01 to f06 of the newest cycle) else from GFS.
    public func nowcast(at coordinate: Coordinate) async throws -> Sourced<[NowcastStep]> {
        let start = NOMADSTime.floorHour(clock.now)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(6 * 3600))
        let rows = try await NOMADSCollector.rows(engine: engine, descriptor: descriptor, coordinate: coordinate, span: span,
                                                  tiling: tiling)
        let built = NOMADSSeries.series(rows, source: descriptor.id)
        return Sourced(value: built.series.hours.map(NOMADSMapping.nowcastStep),
                       provenance: NOMADSProvenance.make(descriptor: descriptor, now: clock.now, used: built.used))
    }

    private func series(from rows: [NOMADSSeries.Row]) -> Sourced<HourlySeries> {
        let built = NOMADSSeries.series(rows, source: descriptor.id)
        return Sourced(value: built.series, provenance: NOMADSProvenance.make(descriptor: descriptor, now: clock.now, used: built.used))
    }
}

/// Plan, fetch, map: the part both providers share.
enum NOMADSCollector {
    /// One coordinate. Throws what the batch records for it.
    static func rows(engine: NOMADSEngine, descriptor: SourceDescriptor, coordinate: Coordinate, span: TimeSpan,
                     tiling: NOMADSTiling, hrrrOnly: Bool = false) async throws -> [NOMADSSeries.Row] {
        let all = await batchRows(engine: engine, descriptor: descriptor, coordinates: [coordinate], span: span, tiling: tiling,
                                  hrrrOnly: hrrrOnly)
        switch all[coordinate] {
        case .success(let rows)?: return rows
        case .failure(let e)?: throw e
        case nil: throw SourceError.invalidRequest("no result for the coordinate")
        }
    }

    /// Rows per distinct coordinate. HRRR-capable points use [HRRR, GFS], others GFS only (or, with `hrrrOnly`, HRRR only
    /// and `.outsideCoverage` outside its domain). Points are grouped by their boxes, the plan is made once for the union
    /// of the models, and every (group, hour) is fetched once.
    static func batchRows(engine: NOMADSEngine, descriptor: SourceDescriptor, coordinates: [Coordinate], span: TimeSpan,
                          tiling: NOMADSTiling, hrrrOnly: Bool) async -> [Coordinate: Result<[NOMADSSeries.Row], SourceError>] {
        var out: [Coordinate: Result<[NOMADSSeries.Row], SourceError>] = [:]
        var distinct: [Coordinate] = []
        var seen = Set<Coordinate>()
        for c in coordinates where seen.insert(c).inserted { distinct.append(c) }

        // Group by boxes, in order of first appearance.
        var groupOf: [Coordinate: Int] = [:]
        var groups: [NOMADSEngine.Boxes] = []
        var groupIndex: [NOMADSEngine.Boxes: Int] = [:]
        var models = Set<NOMADSModel>()
        for c in distinct {
            let inHRRR = CoverageShapes.hrrrDomain.contains(c)
            if hrrrOnly && !inHRRR { out[c] = .failure(.outsideCoverage); continue }
            let m: [NOMADSModel] = hrrrOnly ? [.hrrr] : (inHRRR ? [.hrrr, .gfs] : [.gfs])
            var boxes: NOMADSEngine.Boxes = [:]
            for model in m { boxes[model] = NOMADSRequestBuilder.box(for: c, model: model, tiling: tiling); models.insert(model) }
            if let i = groupIndex[boxes] { groupOf[c] = i } else {
                groupIndex[boxes] = groups.count
                groupOf[c] = groups.count
                groups.append(boxes)
            }
        }
        guard !groups.isEmpty else { return out }

        let plan = await engine.plan(span: span, models: NOMADSModel.allCases.filter { models.contains($0) })
        guard !plan.isEmpty else {
            // Older than the models' retention (about two days of cycles), or past the last forecast hour.
            let e: SourceError
            if span.end < NOMADSTime.floorHour(await engine.now).addingTimeInterval(-48 * 3600) {
                e = .invalidRequest("the span ends more than two days in the past; NOMADS keeps no such cycle")
            } else {
                e = .notPublished("no forecast hours cover \(span.start) to \(span.end)")
            }
            for c in groupOf.keys { out[c] = .failure(e) }
            return out
        }
        let runs = await engine.runBatch(plan, groups: groups, descriptor: descriptor)
        let cancelled = Task.isCancelled

        for (c, g) in groupOf {
            if cancelled { out[c] = .failure(.cancelled); continue }
            let run = runs[g]
            var rows: [NOMADSSeries.Row] = []
            for f in run.fetched {
                guard let s = NOMADSMapping.sample(f.file, model: f.ref.model, at: c) else { continue }
                rows.append(NOMADSSeries.Row(ref: f.ref, conditions: s.conditions, distanceKm: s.distanceKm))
            }
            if rows.isEmpty {
                if let e = run.errors.first(where: { if case .decoding = $0 { return false } else { return true } }) ?? run.errors.first {
                    out[c] = .failure(e)
                } else {
                    out[c] = .failure(.notPublished("NOMADS has not posted the requested hours yet"))
                }
                continue
            }
            // HRRR rows first, so a valid time both models supply keeps HRRR.
            out[c] = .success(rows.sorted { a, b in
                if a.ref.model != b.ref.model { return a.ref.model == .hrrr }
                return a.conditions.time < b.conditions.time
            })
        }
        return out
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
