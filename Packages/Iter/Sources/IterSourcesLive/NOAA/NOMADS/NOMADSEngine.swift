import Foundation
import IterModel
import IterSources

/// Fetches, caches and decodes NOMADS files for a plan. Shared by the forecast and smoke providers (one actor holds the
/// "last good cycle" and "recently missing" memory, so both agree).
actor NOMADSEngine {
    struct CycleKey: Hashable, Sendable { let model: NOMADSModel; let cycle: Date }

    /// One fetched file of a plan.
    struct Fetched: Sendable {
        let planIndex: Int
        let ref: NOMADSFileRef
        let file: GRIB2File
    }

    struct Run: Sendable {
        var fetched: [Fetched] = []
        /// Errors other than "not published", in plan order.
        var errors: [SourceError] = []
        /// Plan hours for which every alternative was missing.
        var missingHours = 0
        var requestedHours = 0
    }

    /// How long a "this cycle is not posted from hour N" finding is trusted.
    static let missTTL: TimeInterval = 300
    static let maxConcurrent = 2

    private let http: any HTTPClient
    private let clock: any SourceClock
    private let cache: (any BlobCaching)?
    private var lastGood: [NOMADSModel: Date] = [:]
    private var misses: [CycleKey: (fromHour: Int, at: Date)] = [:]

    init(http: any HTTPClient, clock: any SourceClock, cache: (any BlobCaching)?) {
        self.http = http
        self.clock = clock
        self.cache = cache
    }

    func lastGoodCycle(_ model: NOMADSModel) -> Date? { lastGood[model] }

    var now: Date { clock.now }

    // MARK: Memory

    private func isMissing(_ ref: NOMADSFileRef) -> Bool {
        guard let m = misses[CycleKey(model: ref.model, cycle: ref.cycle)] else { return false }
        if clock.now.timeIntervalSince(m.at) > Self.missTTL { return false }
        return ref.forecastHour >= m.fromHour
    }

    private func recordMiss(_ ref: NOMADSFileRef) {
        let key = CycleKey(model: ref.model, cycle: ref.cycle)
        let now = clock.now
        if let m = misses[key], now.timeIntervalSince(m.at) <= Self.missTTL, m.fromHour <= ref.forecastHour { return }
        misses[key] = (ref.forecastHour, now)
    }

    private func recordGood(_ ref: NOMADSFileRef) {
        if let g = lastGood[ref.model], g >= ref.cycle { return }
        lastGood[ref.model] = ref.cycle
    }

    // MARK: Plan and fetch

    func plan(span: TimeSpan, models: [NOMADSModel]) -> NOMADSHourPlan {
        NOMADSCyclePlanner.plan(span: span, now: clock.now, models: models) { self.isMissing($0) }
    }

    typealias Boxes = [NOMADSModel: NOMADSBox]

    /// Fetches every hour of the plan for one set of boxes. Never throws: failures are collected.
    func run(_ plan: NOMADSHourPlan, boxes: Boxes, descriptor: SourceDescriptor) async -> Run {
        await runBatch(plan, groups: [boxes], descriptor: descriptor)[0]
    }

    /// One unit of work: a plan hour for one group of boxes (one tile set).
    private struct Item: Hashable, Sendable { let hour: Int; let group: Int }

    /// Fetches every hour of the plan for every group of boxes, one `Run` per group, in group order.
    ///
    /// Order: first the first hour of each model alone (finding the right cycle; for the first group that has a box for
    /// the model), then near term first: hour by hour, every group's file for that hour before any group's next hour, two
    /// at a time. A caller that stops after the first part therefore has the near hours of every tile. Identical files
    /// (the same box, cycle and hour) are fetched once, also when requested at the same moment. Cancelling stops the rest.
    func runBatch(_ plan: NOMADSHourPlan, groups: [Boxes], descriptor: SourceDescriptor) async -> [Run] {
        var runs = Array(repeating: Run(), count: groups.count)
        for g in runs.indices { runs[g].requestedHours = plan.hours.count }
        var results: [Item: Outcome] = [:]

        var probe: [Item] = []
        var seen = Set<NOMADSModel>()
        for i in plan.hours.indices {
            guard let m = plan.hours[i].primary?.model, seen.insert(m).inserted,
                  let g = groups.indices.first(where: { groups[$0][m] != nil }) else { continue }
            probe.append(Item(hour: i, group: g))
        }
        var fatal: SourceError?
        var stop = false
        for item in probe {
            let o = await fetchHour(plan.hours[item.hour], item: item, boxes: groups[item.group], descriptor: descriptor)
            results[item] = o
            if o.isFatal { stop = true; fatal = o.errors.last; break }
        }
        let probed = Set(probe)
        var pending: [Item] = []
        for i in plan.hours.indices {
            for g in groups.indices where !probed.contains(Item(hour: i, group: g)) { pending.append(Item(hour: i, group: g)) }
        }

        if !stop {
            await withTaskGroup(of: (Item, Outcome).self) { group in
                var inFlight = 0
                var next = 0
                while next < pending.count || inFlight > 0 {
                    while inFlight < Self.maxConcurrent, next < pending.count, !stop, !Task.isCancelled {
                        let item = pending[next]
                        next += 1
                        inFlight += 1
                        group.addTask {
                            (item, await self.fetchHour(plan.hours[item.hour], item: item, boxes: groups[item.group],
                                                        descriptor: descriptor))
                        }
                    }
                    guard let (item, o) = await group.next() else { break }
                    inFlight -= 1
                    results[item] = o
                    if o.isFatal { stop = true; fatal = fatal ?? o.errors.last }
                    if (stop || Task.isCancelled) && inFlight == 0 { break }
                }
            }
        }
        if fatal == nil, Task.isCancelled { fatal = .cancelled }

        for g in groups.indices {
            for i in plan.hours.indices {
                guard let o = results[Item(hour: i, group: g)] else { continue }
                if let f = o.fetched { runs[g].fetched.append(Fetched(planIndex: i, ref: f.ref, file: f.file)) }
                else if o.missing { runs[g].missingHours += 1 }
                runs[g].errors += o.errors
            }
            if let fatal, !runs[g].errors.contains(fatal) { runs[g].errors.append(fatal) }
        }
        return runs
    }

    struct Outcome: Sendable {
        var fetched: (ref: NOMADSFileRef, file: GRIB2File)?
        var missing = false
        var errors: [SourceError] = []
        /// An error after which more requests are pointless (offline, rate limited, timed out, cancelled).
        var isFatal = false
    }

    private func fetchHour(_ hour: NOMADSPlannedHour, item: Item, boxes: Boxes,
                           descriptor: SourceDescriptor) async -> Outcome {
        var outcome = Outcome()
        for ref in hour.alternatives {
            if Task.isCancelled { outcome.errors.append(.cancelled); outcome.isFatal = true; return outcome }
            guard let box = boxes[ref.model] else { continue }
            if isMissing(ref) { continue }
            do {
                let file = try await fetchFile(ref, box: box, descriptor: descriptor)
                recordGood(ref)
                outcome.fetched = (ref, file)
                return outcome
            } catch {
                let e = SourceError.wrap(error)
                switch e {
                case .notPublished:
                    recordMiss(ref)
                case .decoding:
                    outcome.errors.append(e)
                case .offline, .timedOut, .rateLimited, .cancelled:
                    outcome.errors.append(e)
                    outcome.isFatal = true
                    return outcome
                default:
                    outcome.errors.append(e)
                    return outcome
                }
            }
        }
        outcome.missing = true
        return outcome
    }

    /// Files being downloaded right now, so a second identical request joins the first instead of repeating it.
    private var inFlight: [CacheKey: Task<GRIB2File, any Error>] = [:]

    /// One file: the cache first, then the network (and then the cache is filled). Concurrent calls for the same box,
    /// cycle and hour share one download. Throws `SourceError`.
    func fetchFile(_ ref: NOMADSFileRef, box: NOMADSBox, descriptor: SourceDescriptor) async throws -> GRIB2File {
        let key = CacheKey(source: .noaaNOMADS, kind: .forecast, cell: box.id, bucket: ref.cacheBucket)
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await self.loadFile(ref, box: box, key: key, descriptor: descriptor) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private func loadFile(_ ref: NOMADSFileRef, box: NOMADSBox, key: CacheKey, descriptor: SourceDescriptor) async throws -> GRIB2File {
        if let cache, let blob = await cache.blob(for: key, maxAge: nil), let file = try? Self.decode(blob.data, ref: ref) {
            return file
        }
        guard let url = NOMADSRequestBuilder.url(for: ref, box: box) else {
            throw SourceError.invalidRequest("NOMADS URL for \(ref)")
        }
        let response: SourceResponse
        do {
            response = try await http.send(.get(url, from: descriptor))
        } catch {
            throw NOMADSErrors.classify(SourceError.wrap(error), what: "\(ref) is not posted yet")
        }
        let file = try Self.decode(response.body, ref: ref)
        if let cache {
            // Public domain (NOAA): the raw box may be kept on disk.
            await cache.storeBlob(response.body, for: key, licence: LicenceTag(key: descriptor.licence.key, mayStore: true))
        }
        return file
    }

    static func decode(_ data: Data, ref: NOMADSFileRef) throws -> GRIB2File {
        try NOMADSErrors.checkGRIB(data, what: "\(ref)")
        let file: GRIB2File
        do { file = try GRIB2File(data: data) } catch { throw SourceError.decoding("\(ref): \(error)") }
        guard !file.fields.isEmpty else { throw SourceError.decoding("\(ref): no readable fields") }
        guard let valid = NOMADSMapping.validTime(of: file), abs(valid.timeIntervalSince(ref.validTime)) < 1 else {
            throw SourceError.decoding("\(ref): file is not valid at the expected time")
        }
        return file
    }
}
