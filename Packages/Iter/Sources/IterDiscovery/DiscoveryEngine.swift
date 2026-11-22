import Foundation
import IterAI
import IterModel
import IterSources
import Synchronization

/// The Find pipeline (BLUEPRINT §7): query plan, area, fan-out, extraction, verification, merge, rank, explain, cite.
///
///     let engine = DiscoveryEngine(providers: providers, model: model, clock: SystemSourceClock())
///     for await event in engine.run(DiscoveryRequest(text: "waterfalls in Yosemite", mapRegion: region)) { ... }
///
/// Cancelling the consumer's task, or ending the stream, cancels every provider call and model call: all fan-out is
/// structured (task groups) beneath one task that the stream owns. A failing source becomes a `SourceStatus`; it never
/// fails the run. Without a model (or when it fails) `BasicQueryParser` and a deterministic extractor take over, so a
/// search always works.
public struct DiscoveryEngine: Sendable {
    public let providers: DiscoveryProviders
    public let model: (any LanguageModeling)?
    public let clock: any SourceClock
    public let configuration: DiscoveryConfiguration

    public init(providers: DiscoveryProviders, model: (any LanguageModeling)? = nil, clock: any SourceClock = SystemSourceClock(),
                configuration: DiscoveryConfiguration = .default) {
        self.providers = providers
        self.model = model
        self.clock = clock
        self.configuration = configuration
    }

    /// Streams events for one search. The stream ends after `.finished`. Terminating it early cancels the work.
    public func run(_ request: DiscoveryRequest) -> AsyncStream<DiscoveryEvent> {
        AsyncStream { continuation in
            let task = Task {
                let result = await self.execute(request) { event in
                    if !Task.isCancelled { continuation.yield(event) }
                }
                if !Task.isCancelled { continuation.yield(.finished(result)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole search, without streaming.
    public func discover(_ request: DiscoveryRequest) async -> DiscoveryResult {
        await execute(request) { _ in }
    }

    // MARK: Pipeline

    /// What each fan-out child hands back to the collecting loop.
    private enum StageOutput: Sendable {
        case source(SourceStatus, candidates: [PlaceCandidate], documents: [EvidenceDocument], isText: Bool)
        case extraction([VerifiedCandidate])
    }

    func execute(_ request: DiscoveryRequest, emit: @escaping @Sendable (DiscoveryEvent) -> Void) async -> DiscoveryResult {
        let log = StatusLog(emit: emit)
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return DiscoveryResult(request: request, plan: QueryPlan(areaMode: .mapArea), planOrigin: .basic(reason: nil), area: nil, places: [],
                                   statuses: [], failure: .emptyQuery)
        }

        // 1. Query understanding.
        let (plan, origin) = await QueryPlanner(model: model, timeout: configuration.planTimeout)
            .plan(for: text, hasMapRegion: request.mapRegion != nil)
        guard !Task.isCancelled else { return cancelled(request, plan, origin, log) }
        emit(.planReady(plan, origin))
        log.set(FixedSources.aiStatus(origin: origin))
        for s in FixedSources.unavailable(consulting: providers.textEvidence) { log.set(s) }

        // 2. Area.
        let resolver = AreaResolver(providers: providers, configuration: configuration, report: { log.set($0) }, now: clock.now)
        let resolution = await resolver.resolve(plan: plan, request: request, nearPhrasing: Self.hasNearPhrasing(text))
        guard !Task.isCancelled else { return cancelled(request, plan, origin, log) }
        let resolved: ResolvedArea
        switch resolution {
        case .failure(let f):
            return DiscoveryResult(request: request, plan: plan, planOrigin: origin, area: nil, places: [], statuses: log.statuses, failure: .area(f))
        case .success(let r):
            resolved = r
        }
        emit(.areaResolved(resolved))
        let area = resolved.area

        // Ranking context.
        let userNearby = request.currentLocation.map { $0.distance(to: resolved.centre) <= 400_000 } ?? false
        let anchor = (userNearby ? request.currentLocation : nil) ?? resolved.centre
        let context = DiscoveryRanker.Context(plan: plan, ordering: request.ordering, preferenceText: request.preferenceText,
                                              library: request.library, anchor: anchor, anchorIsUser: userNearby)

        // 3. Fan-out, 4. extraction, 5. verification: one task group, results collected as they arrive.
        var verified: [VerifiedCandidate] = []
        var dropped: [DroppedCandidate] = []
        func ingest(_ candidates: [PlaceCandidate]) {
            for c in candidates {
                switch CandidateVerifier.check(c, in: area) {
                case .success(let v): verified.append(v)
                case .failure(let reason): dropped.append(DroppedCandidate(name: c.name, source: c.source, reason: reason))
                }
            }
        }
        var documents: [EvidenceDocument] = []
        var textPending = providers.textEvidence.count
        let center = resolved.centre
        let features = Set(plan.features.isEmpty ? FeatureKind.allCases : plan.features)
        let config = configuration
        let limit = config.gazetteerLimit
        let query = TextQuery(terms: plan.searchTerms, features: Set(plan.features), limit: 20)

        await withTaskGroup(of: StageOutput.self) { group in
            for g in providers.gazetteers {
                let d = g.descriptor
                log.set(SourceStatus(source: d.id, name: d.name, role: .gazetteer, state: .searching))
                group.addTask {
                    let (value, state) = await self.guarded(d, center: center) { try await g.candidates(in: area, features: features, limit: limit) }
                    let items = value ?? []
                    return .source(SourceStatus(source: d.id, name: d.name, role: .gazetteer, state: state ?? (items.isEmpty ? .empty : .found(items.count))),
                                   candidates: items, documents: [], isText: false)
                }
            }
            for p in providers.placeSearch {
                let d = p.descriptor
                log.set(SourceStatus(source: d.id, name: d.name, role: .placeSearch, state: .searching))
                let queries = Self.placeSearchQueries(plan)
                group.addTask {
                    var items: [PlaceCandidate] = []
                    var failure: SourceState?
                    for q in queries {
                        if Task.isCancelled { break }
                        let (value, state) = await self.guarded(d, center: center) { try await p.search(q, near: area.region) }
                        if let value { items += value }
                        if let state, failure == nil { failure = state }
                    }
                    let state: SourceState = items.isEmpty ? (failure ?? .empty) : .found(items.count)
                    return .source(SourceStatus(source: d.id, name: d.name, role: .placeSearch, state: state), candidates: items, documents: [], isText: false)
                }
            }
            for t in providers.textEvidence {
                let d = t.descriptor
                log.set(SourceStatus(source: d.id, name: d.name, role: .text, state: .searching))
                group.addTask {
                    let (value, state) = await self.guarded(d, center: center) { try await t.documents(for: query, in: area) }
                    let docs = value ?? []
                    return .source(SourceStatus(source: d.id, name: d.name, role: .text, state: state ?? (docs.isEmpty ? .empty : .found(docs.count))),
                                   candidates: [], documents: docs, isText: true)
                }
            }

            while let out = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                switch out {
                case .source(let status, let candidates, let docs, let isText):
                    log.set(status)
                    ingest(candidates)
                    if isText {
                        documents += docs
                        ingest(DocumentCandidates.candidates(from: docs, plan: plan, areaName: area.name))
                        textPending -= 1
                        if textPending == 0, !documents.isEmpty {
                            let known = DiscoveryMerger.merge(verified)
                            let docsForExtraction = Array(EvidenceChunker.prioritised(documents, plan: plan).prefix(config.maxDocuments))
                            let useModel = origin == .ai
                            group.addTask { .extraction(await self.nameCandidates(from: docsForExtraction, plan: plan, area: area, known: known, useModel: useModel)) }
                        }
                    }
                case .extraction(let found):
                    verified += found
                }
                emit(.partial(Array(DiscoveryRanker.rank(Self.scored(DiscoveryMerger.merge(verified), photos: [:]), context: context).prefix(request.maxResults))))
            }
        }
        guard !Task.isCancelled else { return cancelled(request, plan, origin, log, area: resolved) }

        // 5b. Widening: when the strict pass came back short, ask the gazetteers once more for related subjects. Everything
        // already fetched (text, place search, articles) is reused; related places rank below strict ones.
        var widened = false
        let strictCount = DiscoveryMerger.merge(verified).filter { FeatureRelatedness.tier(of: $0.featureKinds, plan: plan) == .strict }.count
        let relatedKinds = FeatureRelatedness.related(to: plan.features)
        if strictCount < config.widenBelow, !relatedKinds.isEmpty, !providers.gazetteers.isEmpty {
            widened = true
            let relatedSet = Set(relatedKinds)
            let extra = await withTaskGroup(of: (SourceStatus, [PlaceCandidate]).self) { group -> [(SourceStatus, [PlaceCandidate])] in
                for g in providers.gazetteers {
                    let d = g.descriptor
                    // Only sources that answered the first time are asked again; a failed or slow one is not hammered.
                    guard let first = log.statuses.first(where: { $0.source == d.id && $0.role == .gazetteer }) else { continue }
                    var before = 0
                    switch first.state {
                    case .found(let n): before = n
                    case .empty: before = 0
                    default: continue
                    }
                    let beforeCount = before
                    group.addTask {
                        let (value, state) = await self.guarded(d, center: center) { try await g.candidates(in: area, features: relatedSet, limit: limit) }
                        let items = value ?? []
                        let total = beforeCount + items.count
                        return (SourceStatus(source: d.id, name: d.name, role: .gazetteer, state: state == nil ? (total == 0 ? .empty : .found(total)) : first.state),
                                items)
                    }
                }
                var out: [(SourceStatus, [PlaceCandidate])] = []
                while let r = await group.next() { out.append(r) }
                return out
            }
            for (status, items) in extra { log.set(status); ingest(items) }
            if !Task.isCancelled {
                emit(.partial(Array(DiscoveryRanker.rank(Self.scored(DiscoveryMerger.merge(verified), photos: [:]), context: context).prefix(request.maxResults))))
            }
        }
        guard !Task.isCancelled else { return cancelled(request, plan, origin, log, area: resolved) }

        // 6. Merge, then photo density for the top candidates.
        let merged = DiscoveryMerger.merge(verified)
        let preliminary = DiscoveryRanker.rank(Self.scored(merged, photos: [:]), context: context)
        let topIDs = Set(preliminary.prefix(config.photoLookupCount).map(\.id))
        let top = merged.filter { topIDs.contains(DiscoveredPlace.makeID(name: $0.name, coordinate: $0.coordinate.value)) }
        let photos = await photoEvidence(for: top, center: center, log: log)
        guard !Task.isCancelled else { return cancelled(request, plan, origin, log, area: resolved) }

        // 7. Rank.
        var ranked = Array(DiscoveryRanker.rank(Self.scored(merged, photos: photos), context: context).prefix(request.maxResults))

        // 8. Explain.
        let names = Dictionary(
            (providers.gazetteers.map { ($0.descriptor.id, $0.descriptor.name) } + providers.placeSearch.map { ($0.descriptor.id, $0.descriptor.name) }
                + providers.textEvidence.map { ($0.descriptor.id, $0.descriptor.name) } + providers.geocoders.map { ($0.descriptor.id, $0.descriptor.name) }
                + providers.photoEvidence.map { ($0.descriptor.id, $0.descriptor.name) }), uniquingKeysWith: { a, _ in a })
        let explainer = PlaceExplainer(model: origin == .ai ? model : nil, timeout: config.explanationTimeout, sourceNames: names,
                                       areaName: area.name, plan: plan)
        let toExplain = Array(ranked.prefix(config.explanationCount))
        let lines = await mapConcurrently(toExplain, limit: config.explanationConcurrency) { await explainer.explain($0) }
        guard !Task.isCancelled else { return cancelled(request, plan, origin, log, area: resolved) }
        for i in ranked.indices { ranked[i].why = i < lines.count ? lines[i] : PlaceExplanation(text: explainer.template(for: ranked[i]), isModelWritten: false) }

        return DiscoveryResult(request: request, plan: plan, planOrigin: origin, area: resolved, places: ranked, statuses: log.statuses,
                               widened: widened, dropped: dropped)
    }

    // MARK: Pieces

    private func cancelled(_ request: DiscoveryRequest, _ plan: QueryPlan, _ origin: PlanOrigin, _ log: StatusLog,
                           area: ResolvedArea? = nil) -> DiscoveryResult {
        DiscoveryResult(request: request, plan: plan, planOrigin: origin, area: area, places: [], statuses: log.statuses)
    }

    static func hasNearPhrasing(_ text: String) -> Bool {
        let tokens = Set(DiscoveryNames.tokens(text))
        return !tokens.isDisjoint(with: ["near", "around", "nearby", "close"])
    }

    /// Free-text searches for MapKit: each feature, then the keywords, at most four.
    static func placeSearchQueries(_ plan: QueryPlan) -> [String] {
        var queries = plan.features.map(\.pluralName)
        if !plan.keywords.isEmpty { queries.append(plan.keywords.joined(separator: " ")) }
        if queries.isEmpty { queries = ["scenic viewpoints"] }
        return Array(queries.prefix(4))
    }

    static func scored(_ merged: [VerifiedCandidate], photos: [String: PhotoEvidence]) -> [DiscoveryRanker.Scored] {
        merged.map { c in
            let id = DiscoveredPlace.makeID(name: c.name, coordinate: c.coordinate.value)
            let p = photos[id]
            return DiscoveryRanker.Scored(candidate: c, photoCount: p?.count ?? 0, photos: Array((p?.photos ?? []).prefix(6)))
        }
    }

    /// Runs one provider call under the source's timeout. Returns the value, or the state to show when there is none
    /// (`nil` state with a value means the caller counts the results). Cancellation returns `(nil, nil)`.
    func guarded<T: Sendable>(_ d: SourceDescriptor, center: Coordinate, _ operation: @escaping @Sendable () async throws -> T) async -> (T?, SourceState?) {
        guard d.coverage.contains(center) else { return (nil, .skipped("outside its coverage")) }
        guard !Task.isCancelled else { return (nil, nil) }
        do {
            return (try await withDeadline(configuration.timeout(for: d), operation), nil)
        } catch is DeadlineExceeded {
            return (nil, .timedOut)
        } catch {
            let e = SourceError.wrap(error)
            if e == .cancelled || Task.isCancelled { return (nil, nil) }
            if e == .timedOut { return (nil, .timedOut) }
            return (nil, .failed(e.noDataReason(source: d.id)))
        }
    }

    /// Names from documents, located by geocoder and place search inside the area. A name that matches a place already
    /// found reuses that place's own grounded coordinate (so the text counts as a second source for it).
    private func nameCandidates(from docs: [EvidenceDocument], plan: QueryPlan, area: DiscoveryArea, known: [VerifiedCandidate],
                                useModel: Bool) async -> [VerifiedCandidate] {
        var names: [ExtractedName] = []
        if useModel, let model {
            names = await ModelExtractor(model: model, timeout: configuration.extractionTimeout)
                .extract(chunks: EvidenceChunker.chunks(docs, plan: plan), plan: plan)
        } else {
            names = DeterministicExtractor.extract(from: docs, plan: plan)
        }
        guard !Task.isCancelled else { return [] }
        // Documents that are about the area itself are not places in it.
        if let areaName = area.name { names.removeAll { DiscoveryNames.matches($0.name, areaName) } }
        // Requested kinds first, then related or unknown ones, so the cap never costs a strict match.
        func rank(_ n: ExtractedName) -> Int { FeatureRelatedness.tier(of: n.featureHint.map { [$0] } ?? [], plan: plan).rawValue }
        names = Array(names.enumerated().sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }
            .map(\.element).prefix(configuration.maxNamedCandidates))

        var out: [VerifiedCandidate] = []
        var toLocate: [ExtractedName] = []
        for n in names {
            if let k = known.first(where: { DiscoveryNames.matches($0.name, n.name) }) {
                out.append(VerifiedCandidate(name: k.name, coordinate: k.coordinate, elevationMeters: k.elevationMeters, featureKinds: k.featureKinds,
                                             sources: [n.source], stableSources: [], citations: [n.citation], mentionCount: 1, snippet: n.snippet,
                                             externalIDs: []))
            } else {
                toLocate.append(n)
            }
        }
        let geocoders = providers.geocoders, search = providers.placeSearch
        let config = configuration
        let located = await mapConcurrently(toLocate, limit: 2) { n in
            await CandidateVerifier.verifyNamed(n, area: area, geocoders: geocoders, placeSearch: search, timeout: { config.timeout(for: $0) })
        }
        return out + located.compactMap { $0 }
    }

    /// Photo density for the top candidates: each photo source is asked for each, a few at a time. A source's status counts
    /// the photos it found.
    private func photoEvidence(for top: [VerifiedCandidate], center: Coordinate, log: StatusLog) async -> [String: PhotoEvidence] {
        var result: [String: PhotoEvidence] = [:]
        guard !top.isEmpty else { return result }
        let radius = configuration.photoRadiusMeters
        for p in providers.photoEvidence {
            let d = p.descriptor
            log.set(SourceStatus(source: d.id, name: d.name, role: .photos, state: .searching))
            let answers = await mapConcurrently(top, limit: 3) { c -> (String, PhotoEvidence?, SourceState?) in
                let id = DiscoveredPlace.makeID(name: c.name, coordinate: c.coordinate.value)
                let (value, state) = await self.guarded(d, center: center) { try await p.evidence(near: c.coordinate.value, radiusM: radius) }
                return (id, value, state)
            }
            if Task.isCancelled { return result }
            var total = 0
            for (id, value, _) in answers {
                guard let value else { continue }
                total += value.count
                if let existing = result[id] {
                    var merged = existing
                    merged.count = max(existing.count, value.count)
                    merged.photos += value.photos
                    result[id] = merged
                } else {
                    result[id] = value
                }
            }
            let firstFailure = answers.compactMap(\.2).first
            let state: SourceState = answers.contains { $0.1 != nil } ? (total > 0 ? .found(total) : .empty) : (firstFailure ?? .empty)
            log.set(SourceStatus(source: d.id, name: d.name, role: .photos, state: state))
        }
        return result
    }
}

// MARK: Support

/// The run's source statuses in first-seen order, emitting a `statusChanged` event for each change.
final class StatusLog: Sendable {
    private let state = Mutex<[SourceStatus]>([])
    private let emit: @Sendable (DiscoveryEvent) -> Void

    init(emit: @escaping @Sendable (DiscoveryEvent) -> Void) { self.emit = emit }

    func set(_ status: SourceStatus) {
        let changed = state.withLock { list -> Bool in
            if let i = list.firstIndex(where: { $0.id == status.id }) {
                if list[i] == status { return false }
                list[i] = status
            } else {
                list.append(status)
            }
            return true
        }
        if changed { emit(.statusChanged(status)) }
    }

    var statuses: [SourceStatus] { state.withLock { $0 } }
}

/// `transform` over `items` with at most `limit` in flight, results in input order. Structured: cancelling the caller cancels all.
func mapConcurrently<T: Sendable, R: Sendable>(_ items: [T], limit: Int, _ transform: @escaping @Sendable (T) async -> R) async -> [R] {
    await withTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        func startNext(_ group: inout TaskGroup<(Int, R)>) {
            guard next < items.count else { return }
            let i = next
            next += 1
            let item = items[i]
            group.addTask { (i, await transform(item)) }
        }
        for _ in 0..<min(max(1, limit), items.count) { startNext(&group) }
        while let (i, r) = await group.next() {
            results[i] = r
            if Task.isCancelled { group.cancelAll(); continue }
            startNext(&group)
        }
        return results.compactMap { $0 }
    }
}
