import Foundation
import IterModel
import IterSources
import IterSky
import IterAstro

struct JobKey: Hashable, Sendable {
    var placeID: UUID
    var day: LocalDay
}

struct JobState {
    var request: ConditionsRequest
    var generation: UInt64
    var latest: SkyReport?
    var subscribers: [UUID: AsyncStream<SkyReport>.Continuation] = [:]
    var task: Task<Void, Never>?
    /// Keeps running with no subscriber left (a caller that took the first usable answer; the rest fills the cache).
    var detached = false
    var settled = false
}

struct Subscription: Sendable {
    var key: JobKey
    var id: UUID
    var generation: UInt64
}

struct PlaceDay: Hashable, Sendable {
    var placeID: UUID
    var day: LocalDay
}

/// What the cache held for a forecast step.
enum ForecastLookup: Sendable {
    case fresh(Sourced<HourlySeries>)
    case stale(Sourced<HourlySeries>, storedAt: Date)
    case none
}

struct ForecastStep: Sendable {
    var provider: any ForecastProvider
    var coordinate: Coordinate
    var hours: Int
    var priority: ConditionsPriority
    var lookup: ForecastLookup
    var ticket: Int?
    var refresh: Bool
}

struct StepOutcome: Sendable {
    var step: ForecastStep
    var state: DataState<HourlySeries>
    var reasons: [NoDataReason]
    var needsRefresh: Bool
}

/// A job's working state. Only the job's own actor-isolated code touches it.
final class JobBox: @unchecked Sendable {
    var parts = JobParts()
    var expected: [PendingPart] = []
    var emitted = false
    var emittedComplete = false
}

enum JobPart: Sendable {
    case forecast(StepOutcome)
    case observations(DataState<[Sourced<WeatherObservation>]>, DataState<[Sourced<StationReport>]>)
    case alerts(DataState<[WeatherAlert]>)
    case aurora(DataState<AuroraOutlook>)
    case smokeAnalysis(DataState<SmokeAnalysis>)
    case horizon(DataState<HorizonProfile>)
    case optionalInputs(bortle: Double?, bortleReasons: [NoDataReason], seeing: Double?, seeingReasons: [NoDataReason])
}

/// The Conditions stage: composite forecasts with per-field provenance, observations, alerts, smoke, aurora, horizons,
/// live conditions for trip mode, and offline packs.
///
/// A score appears fast and improves: `reports(for:)` yields a quick report from the first source that answers (often one
/// MET Norway request), then rebuilds the composite field by field as higher-ranked sources arrive. NOAA is fetched near
/// term first and long range only when a later day is asked for. Concurrent requests for nearby places share NOAA tiles
/// through one `BatchForecastProvider` call. Identical requests are joined, and everything stops when the last consumer
/// of a stream goes away.
public actor ConditionsService {
    let registry: SourceRegistry
    let cache: SourceCache
    let clock: any SourceClock
    let ephemeris: any Ephemeris
    let packDirectory: URL?
    let configuration: ConditionsConfiguration
    let assembler: ReportAssembler

    // Jobs: one per (place, day), joined by every consumer.
    var jobs: [JobKey: JobState] = [:]
    var generationCounter: UInt64 = 0
    /// Jobs admitted that have not yet registered their downloads.
    var unsettled = 0

    // Forecast downloads (ConditionsFetching.swift).
    var tickets: [Int: FetchTicket] = [:]
    var inflightByKey: [FetchKey: Int] = [:]
    /// Results of tickets that finished before every awaiter arrived.
    var finished: [Int: FinishedTicket] = [:]
    var laneRunning: [SourceID: Int] = [:]
    var batchRuns: [Int: BatchRun] = [:]
    var batchTimer: Task<Void, Never>?
    var ticketCounter = 0
    var waiterCounter = 0
    var batchCounter = 0

    var horizonFlights: [String: Task<DataState<HorizonProfile>, Never>] = [:]

    var packIndex: [PlaceDay: PackEntry] = [:]
    var packsLoaded = false

    public init(_ dependencies: ConditionsDependencies) {
        registry = dependencies.registry
        cache = dependencies.cache
        clock = dependencies.clock
        ephemeris = dependencies.ephemeris
        packDirectory = dependencies.packDirectory
        configuration = dependencies.configuration
        assembler = ReportAssembler(registry: dependencies.registry, ephemeris: dependencies.ephemeris,
                                    configuration: dependencies.configuration)
    }

    // MARK: Public API

    /// The report for one place and day. Returns as soon as the report is at least `waitFor` (the default is the first usable
    /// answer: a cached value at once, even a stale one, else the first source to answer). When it returns early the rest keeps
    /// loading in the background so the cache is warm for the next call; cancel the calling task to stop everything.
    public func report(for place: Place, day: LocalDay, priority: ConditionsPriority = .onScreen,
                       waitFor: ForecastTier = .quick) async -> SkyReport {
        let (stream, sub) = subscribe(ConditionsRequest(place: place, day: day, priority: priority))
        var last: SkyReport?
        var finished = true
        await withTaskCancellationHandler {
            for await r in stream {
                last = r
                if r.tier >= waitFor { finished = r.tier == .complete; break }
            }
        } onCancel: {
            Task { await self.unsubscribe(sub) }
        }
        if !Task.isCancelled, !finished { detach(sub) } else { unsubscribe(sub) }
        if let last { return last }
        return assembler.assemble(place: place, day: day, parts: JobParts(), pack: nil, now: clock.now)
    }

    /// Reports for many places and days, progressively: each report arrives as soon as it has a first usable answer and again
    /// as it improves (check `tier`). Higher-priority requests are started and served first, and concurrent requests share
    /// downloads. The stream ends when everything is complete; ending it early (cancelling its consumer) cancels the loading.
    public nonisolated func reports(for requests: [ConditionsRequest]) -> AsyncStream<SkyReport> {
        let (stream, continuation) = AsyncStream<SkyReport>.makeStream(bufferingPolicy: .unbounded)
        let pump = Task { await self.pump(requests, into: continuation) }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }

    /// The terrain horizon for a place. A horizon the place already carries is returned without a fetch; otherwise it is
    /// fetched once and cached for 30 days. Identical concurrent requests are joined.
    public func horizon(for place: Place) async -> DataState<HorizonProfile> {
        if let own = place.horizon {
            return .fresh(Sourced(value: own, provenance: Provenance(
                source: .terrariumTiles, fetchedAt: place.updatedAt, licence: LicenceTag(key: LicenceKey.terrainTiles, mayStore: true))))
        }
        let cell = place.coordinate.cacheKey
        if let flight = horizonFlights[cell] { return await flight.value }
        let flight = Task { await self.fetchHorizon(place.coordinate) }
        horizonFlights[cell] = flight
        let state = await flight.value
        horizonFlights[cell] = nil
        return state
    }

    // MARK: Streams

    private func pump(_ requests: [ConditionsRequest], into continuation: AsyncStream<SkyReport>.Continuation) async {
        let ordered = requests.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
        var seen = Set<JobKey>()
        var subs: [(AsyncStream<SkyReport>, Subscription)] = []
        for r in ordered where seen.insert(JobKey(placeID: r.place.id, day: r.day)).inserted { subs.append(subscribe(r)) }
        await withTaskGroup(of: Void.self) { group in
            for (stream, _) in subs {
                group.addTask { for await report in stream { continuation.yield(report) } }
            }
        }
        for (_, sub) in subs { unsubscribe(sub) }
        continuation.finish()
    }

    func subscribe(_ request: ConditionsRequest) -> (AsyncStream<SkyReport>, Subscription) {
        let key = JobKey(placeID: request.place.id, day: request.day)
        let (stream, continuation) = AsyncStream<SkyReport>.makeStream(bufferingPolicy: .bufferingNewest(8))
        if jobs[key] == nil { startJob(request, key) }
        let id = UUID()
        jobs[key]?.subscribers[id] = continuation
        if let latest = jobs[key]?.latest { continuation.yield(latest) }
        let sub = Subscription(key: key, id: id, generation: jobs[key]?.generation ?? 0)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.unsubscribe(sub) }
        }
        return (stream, sub)
    }

    func unsubscribe(_ sub: Subscription) {
        guard var j = jobs[sub.key], j.generation == sub.generation else { return }
        j.subscribers[sub.id] = nil
        jobs[sub.key] = j
        if j.subscribers.isEmpty, !j.detached { removeJob(sub.key, cancel: true) }
    }

    private func detach(_ sub: Subscription) {
        guard var j = jobs[sub.key], j.generation == sub.generation else { return }
        j.subscribers[sub.id] = nil
        j.detached = true
        jobs[sub.key] = j
    }

    private func startJob(_ request: ConditionsRequest, _ key: JobKey) {
        generationCounter += 1
        let generation = generationCounter
        unsettled += 1
        jobs[key] = JobState(request: request, generation: generation)
        jobs[key]?.task = Task { await self.runJob(key, generation) }
    }

    private func removeJob(_ key: JobKey, cancel: Bool) {
        guard let j = jobs.removeValue(forKey: key) else { return }
        if cancel { j.task?.cancel() }
        for c in j.subscribers.values { c.finish() }
        if !j.settled {
            unsettled -= 1
            if unsettled == 0 { pump() }
        }
    }

    private func emit(_ key: JobKey, _ generation: UInt64, _ report: SkyReport) {
        guard var j = jobs[key], j.generation == generation else { return }
        j.latest = report
        jobs[key] = j
        for c in j.subscribers.values { c.yield(report) }
    }

    // MARK: A job

    private func runJob(_ key: JobKey, _ generation: UInt64) async {
        guard let request = jobs[key]?.request, jobs[key]?.generation == generation else { return }
        defer {
            settle(key, generation: generation)
            if jobs[key]?.generation == generation { removeJob(key, cancel: false) }
        }
        let place = request.place, day = request.day
        let now = clock.now
        let zone = place.timeZone
        let windows = LightEngine(ephemeris: ephemeris).windows(for: place, on: day)
        let windowEnd = windows.map(\.span.end).max() ?? day.adding(days: 1).start(in: zone)
        let offset = LocalDay(now, in: zone).days(until: day)
        let live = (0...configuration.liveDays).contains(offset)
        let pack = await packEntry(place.id, day)

        let box = JobBox()
        box.parts.pastDay = windowEnd <= now
        let providers = box.parts.pastDay ? [] : forecastCandidates(at: place.coordinate)
        box.parts.candidates = providers.map(\.descriptor)

        // Plan the downloads: incremental sources near term first, the rest in one request for the longest horizon.
        struct Plan { var provider: any ForecastProvider; var tiers: [Int]; var steps: [ForecastStep] = []; var index = 0 }
        let neededHours = max(1, Int((windowEnd.timeIntervalSince(floorHour(now)) / 3600).rounded(.up)))
        var plans: [SourceID: Plan] = [:]
        for p in providers { plans[p.descriptor.id] = Plan(provider: p, tiers: tiers(for: p, needed: neededHours)) }

        // Register every download of the plan up front (the long range waits behind the near term), best priority first,
        // then let the queues move. Registering all of it together is what lets places share one batch call per horizon.
        var firstSteps: [ForecastStep] = []
        for p in providers {
            guard var plan = plans[p.descriptor.id] else { continue }
            var previous: Int?
            for hours in plan.tiers {
                let step = await makeStep(p, hours: hours, priority: request.priority, coordinate: place.coordinate, after: previous)
                plan.steps.append(step)
                previous = step.ticket ?? previous
            }
            plans[p.descriptor.id] = plan
            if let first = plan.steps.first { firstSteps.append(first) }
        }
        settle(key, generation: generation)

        box.expected.append(.lightAndSeeing)
        if live { box.expected += [.observations, .alerts, .smokeAnalysis, .aurora] }
        if place.horizon == nil, configuration.fetchesHorizon { box.expected.append(.horizon) }
        if live { box.parts.observations = nil } else {
            box.parts.observations = .none([]); box.parts.stationReports = .none([]); box.parts.alerts = .none([])
            box.parts.aurora = .none([]); box.parts.smokeAnalysis = .none([])
        }
        if place.horizon != nil || !configuration.fetchesHorizon { box.parts.horizon = nil }

        func refreshPending() {
            box.parts.pending = box.parts.candidates.filter { !box.parts.fullDone.contains($0.id) }.map { .forecast($0.id) } + box.expected
        }
        func publish(force: Bool = false) {
            refreshPending()
            let usable = box.parts.forecasts.values.contains { $0.value != nil }
            let nearDone = box.parts.candidates.allSatisfy { box.parts.nearDone.contains($0.id) }
            guard force || box.emitted || usable || nearDone else { return }
            let report = assembler.assemble(place: place, day: day, parts: box.parts, pack: pack, now: clock.now)
            if report.tier == .complete, box.emittedComplete { return }
            box.emitted = true
            box.emittedComplete = report.tier == .complete
            emit(key, generation, report)
        }
        refreshPending()

        await withTaskGroup(of: JobPart.self) { group in
            for step in firstSteps { group.addTask { await self.runStep(step) } }
            if live {
                group.addTask { await self.loadObservations(place) }
                group.addTask { await self.loadAlerts(place) }
                group.addTask { await self.loadAurora(place) }
                group.addTask { await self.loadSmokeAnalysis(place, day: day) }
            }
            if place.horizon == nil, configuration.fetchesHorizon { group.addTask { .horizon(await self.horizon(for: place)) } }
            group.addTask { await self.loadOptionalInputs(place) }

            for await part in group {
                switch part {
                case .forecast(let outcome):
                    let id = outcome.step.provider.descriptor.id
                    let existing = box.parts.forecasts[id]
                    if case .none = outcome.state {
                        if existing == nil { box.parts.forecasts[id] = outcome.state }
                    } else if let existing, existing.isFresh, !outcome.state.isFresh, existing.value != nil {
                        // keep the fresher near-term answer
                    } else {
                        box.parts.forecasts[id] = outcome.state
                    }
                    box.parts.failures[id] = outcome.reasons
                    if outcome.needsRefresh {
                        var refresh = outcome.step
                        refresh.refresh = true
                        group.addTask { await self.runStep(refresh) }
                    } else if var plan = plans[id] {
                        if plan.index == 0 { box.parts.nearDone.insert(id) }
                        if plan.index + 1 < plan.tiers.count {
                            plan.index += 1
                            plans[id] = plan
                            let next = plan.steps[plan.index]
                            group.addTask { await self.runStep(next) }
                        } else {
                            box.parts.fullDone.insert(id)
                        }
                    }
                case .observations(let o, let r):
                    box.parts.observations = o; box.parts.stationReports = r; box.expected.removeAll { $0 == .observations }
                case .alerts(let a):
                    box.parts.alerts = a; box.expected.removeAll { $0 == .alerts }
                case .aurora(let a):
                    box.parts.aurora = a; box.expected.removeAll { $0 == .aurora }
                case .smokeAnalysis(let s):
                    box.parts.smokeAnalysis = s; box.expected.removeAll { $0 == .smokeAnalysis }
                case .horizon(let h):
                    box.parts.horizon = h; box.expected.removeAll { $0 == .horizon }
                case .optionalInputs(let b, let br, let s, let sr):
                    box.parts.bortle = b; box.parts.bortleReasons = br; box.parts.seeing = s; box.parts.seeingReasons = sr
                    box.expected.removeAll { $0 == .lightAndSeeing }
                }
                publish()
            }
        }
        box.parts.fullDone = Set(box.parts.candidates.map(\.id))
        box.expected = []
        publish(force: true)
    }

    // MARK: Forecast steps

    func forecastCandidates(at c: Coordinate) -> [any ForecastProvider] {
        var out: [any ForecastProvider] = []
        var seen = Set<SourceID>()
        for kind in [DataKind.forecast, .smoke, .aerosol] {
            for p in registry.providers((any ForecastProvider).self, kind: kind, at: c) where seen.insert(p.descriptor.id).inserted {
                out.append(p)
            }
        }
        return out
    }

    /// The horizons to ask a source for: incremental sources near term first, then the smallest tier that covers the need;
    /// every other source once, for the longest horizon (one request serves every day).
    func tiers(for provider: any ForecastProvider, needed: Int) -> [Int] {
        let all = configuration.tierHours.isEmpty ? [12, 48, 240] : configuration.tierHours
        let incremental = provider is any BatchForecastProvider || configuration.incrementalSources.contains(provider.descriptor.id)
        guard incremental else { return [all.last!] }
        let target = all.first { $0 >= needed } ?? all.last!
        return target <= all[0] ? [all[0]] : [all[0], target]
    }

    func forecastKey(_ d: SourceDescriptor, _ c: Coordinate, hours: Int) -> CacheKey {
        CacheKey(source: d.id, kind: .forecast, cell: GeoCell.key(c, degrees: configuration.forecastCellDegrees), bucket: "h\(hours)")
    }

    func lookupForecast(_ provider: any ForecastProvider, coordinate: Coordinate, hours: Int) async -> ForecastLookup {
        let d = provider.descriptor
        var newestStale: (Sourced<HourlySeries>, Date)?
        for h in configuration.tierHours where h >= hours {
            guard let e = await cache.entry(forecastKey(d, coordinate, hours: h), as: Sourced<HourlySeries>.self) else { continue }
            if clock.now.timeIntervalSince(e.storedAt) < d.cacheTTL.timeInterval { return .fresh(e.value) }
            if newestStale == nil || e.storedAt > newestStale!.1 { newestStale = (e.value, e.storedAt) }
        }
        if let s = newestStale { return .stale(s.0, storedAt: s.1) }
        return .none
    }

    func makeStep(_ provider: any ForecastProvider, hours: Int, priority: ConditionsPriority, coordinate: Coordinate,
                  after: Int? = nil) async -> ForecastStep {
        let lookup = await lookupForecast(provider, coordinate: coordinate, hours: hours)
        var ticket: Int?
        if case .fresh = lookup {} else {
            ticket = registerFetch(provider: provider, coordinate: coordinate, hours: hours, priority: priority, after: after)
        }
        return ForecastStep(provider: provider, coordinate: coordinate, hours: hours, priority: priority, lookup: lookup, ticket: ticket, refresh: false)
    }

    func runStep(_ step: ForecastStep) async -> JobPart {
        let d = step.provider.descriptor
        func age(_ stored: Date) -> Duration { .interval(max(0, clock.now.timeIntervalSince(stored))) }
        switch step.lookup {
        case .fresh(let s):
            return .forecast(StepOutcome(step: step, state: .fresh(s), reasons: [], needsRefresh: false))
        case .stale(let s, let stored) where !step.refresh:
            return .forecast(StepOutcome(step: step, state: .stale(s, age: age(stored)), reasons: [], needsRefresh: true))
        default:
            guard let ticket = step.ticket else {
                return .forecast(StepOutcome(step: step, state: .none([]), reasons: [], needsRefresh: false))
            }
            let result = await awaitTicket(ticket)
            var storedAt: Date?
            var fallback: Sourced<HourlySeries>?
            if case .stale(let s, let at) = step.lookup { fallback = s; storedAt = at }
            switch result {
            case .success(let s):
                await cache.store(s, for: forecastKey(d, step.coordinate, hours: step.hours), licence: d.licence)
                return .forecast(StepOutcome(step: step, state: .fresh(s), reasons: [], needsRefresh: false))
            case .failure(let e):
                if e == .cancelled { return .forecast(StepOutcome(step: step, state: fallback.map { .stale($0, age: age(storedAt!)) } ?? .none([]), reasons: [], needsRefresh: false)) }
                let reason = e.noDataReason(source: d.id, lastGood: storedAt)
                let state: DataState<HourlySeries> = fallback.map { .stale($0, age: age(storedAt!)) } ?? .none([reason])
                return .forecast(StepOutcome(step: step, state: state, reasons: [reason], needsRefresh: false))
            }
        }
    }
}
