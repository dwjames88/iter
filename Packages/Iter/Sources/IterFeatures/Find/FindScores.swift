import Foundation
import Observation
import IterModel
import IterSky
import IterConditions

// A Sky Index score for each result, fed lazily by the shared `ConditionsStore` (BLUEPRINT §7, step 9): rows in view are
// asked for first, a quick score stays on screen until the complete one replaces it, and a place with no score shows no number.

/// The score one row, pin or card shows: the headline window of today at that place. Never a number standing in for missing data:
/// `value` is nil while loading and when no forecast could score the day.
public struct FindScore: Equatable, Sendable {
    public var kind: LightWindowKind
    /// The window's start (the chip's time).
    public var start: Date
    public var value: Int?
    public var confidence: Confidence?
    /// True while the store is still fetching and there is nothing to show yet. A shown score is never "loading".
    public var isLoading: Bool
    public var zoneIdentifier: String

    public var timeZone: TimeZone { TimeZone(identifier: zoneIdentifier) ?? .gmt }
    public var isLowConfidence: Bool { confidence == .low }

    public init(kind: LightWindowKind, start: Date, value: Int?, confidence: Confidence?, isLoading: Bool, zoneIdentifier: String) {
        self.kind = kind
        self.start = start
        self.value = value
        self.confidence = confidence
        self.isLoading = isLoading
        self.zoneIdentifier = zoneIdentifier
    }
}

/// The part of the Conditions stage Find uses, protocol-typed so tests and previews inject a fake. `ConditionsStore` is wrapped by
/// `StoreFindScores`.
@MainActor
public protocol FindScoreSource: AnyObject {
    /// What the slot has now. Reads observable state, so a model that reads it inside observation tracking hears about changes.
    func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState
    func request(_ place: Place, day: LocalDay, priority: ConditionsPriority)
    func setVisible(_ placeIDs: Set<UUID>)
    func cancel(_ placeID: UUID, day: LocalDay)
}

/// The real thing: the container's shared `ConditionsStore`.
@MainActor
public final class StoreFindScores: FindScoreSource {
    private let store: ConditionsStore
    public init(_ store: ConditionsStore) { self.store = store }

    public func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState { store.state(for: placeID, day: day) }
    public func setVisible(_ placeIDs: Set<UUID>) { store.setVisible(placeIDs) }

    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) {
        // A slot that already has a complete report is not asked for again.
        if case .ready(let report) = store.state(for: place.id, day: day), report.tier == .complete { return }
        store.request(place, day: day, priority: priority)
    }

    public func cancel(_ placeID: UUID, day: LocalDay) {
        // Only an unfinished load is stopped; a report already held is kept.
        if case .loading = store.state(for: placeID, day: day) { store.cancel(placeID, day: day) }
    }
}

extension FindScore {
    /// The window a result's chip scores: the place's intent window if scored, else the best scored window of daytime light
    /// still to come. A night window never stands in for a daytime intent (the rule on `LightIntent`): once golden and blue
    /// hour have passed, the chip shows no number rather than the night's 0 (a bright moon scores a night window 0, which is
    /// true of astrophotography and says nothing about the light a result is being picked for). A place whose own intent is
    /// night is scored on night.
    static func headline(_ r: SkyReport, intent: LightIntent) -> HeadlineScore? {
        if let w = r.daylight.headline(for: intent), let s = w.assessment.skyScore {
            return ConditionsDerivation.score(s, kind: w.kind, tier: r.tier)
        }
        guard intent != .night else { return nil }
        var best: (kind: LightWindowKind, score: SkyScore)?
        for w in r.daylight.windows.sorted(by: { $0.span.start < $1.span.start }) where w.kind.isDaytimeLight {
            guard let s = w.assessment.skyScore else { continue }
            if best == nil || s.value > best!.score.value { best = (w.kind, s) }
        }
        return best.map { ConditionsDerivation.score($0.score, kind: $0.kind, tier: r.tier) }
    }

    /// The score for a slot: the place's intent window if scored, else the best scored window left today; nil when the slot holds
    /// nothing that scores (and nothing is loading).
    @MainActor static func make(state: ConditionsLoadState?, place: Place, now: Date) -> FindScore? {
        let zone = place.timeZone
        let loading = state?.isLoading ?? true
        if let report = state?.report, let h = headline(report, intent: place.defaultIntent) {
            let window = report.daylight.windows.first { $0.kind == h.kind }
            return FindScore(kind: h.kind, start: window?.span.start ?? now, value: h.value, confidence: h.confidence, isLoading: false,
                             zoneIdentifier: place.timeZoneIdentifier)
        }
        // Nothing scorable. Say "loading" only while the store is still working on it; otherwise the chip shows no number and no spinner.
        let kind = place.defaultSession
        let window = state?.report?.daylight.windows.first { $0.kind == kind }
        return FindScore(kind: kind, start: window?.span.start ?? now, value: nil, confidence: nil, isLoading: loading,
                         zoneIdentifier: place.timeZoneIdentifier)
    }
}

extension FindModel {
    /// What the list says is on screen now (row ids). Their places are asked for first; call with the rows in view as the list
    /// scrolls. Before the first call the top of the list counts as visible.
    public func setVisibleResults(_ ids: Set<String>) {
        guard visibleResultIDs != ids else { return }
        visibleResultIDs = ids
        refreshScoreRequests()
    }

    /// The place and day a score id stands for, if it is a result or the selected card.
    private func scoreTarget(for id: String) -> (place: Place, day: LocalDay)? {
        let place: Place
        if let d = raw.first(where: { $0.id == id }) { place = placeForRow(d) }
        else if let c = card, c.id == id { place = c.place }
        else { return nil }
        let day = scoreDayOffset == 0 ? now() : now().addingTimeInterval(TimeInterval(scoreDayOffset) * 86_400)
        return (place, LocalDay(day, in: place.timeZone))
    }

    /// Asks the store for the places in view (and the selected one) at on-screen priority, once each per search, and tells it which
    /// places are on screen. Places not in view are not asked for at all.
    func refreshScoreRequests() {
        guard let source = scoreSource else { return }
        var wanted: [String] = []
        // While results stream in their order keeps changing, so only the selected place is asked for; the list is scored once settled.
        if phase != .discovering {
            let inView = visibleResultIDs ?? Set(rows.prefix(configuration.scoreLeadCount).map(\.id))
            for row in rows where inView.contains(row.id) { wanted.append(row.id) }
        }
        if let selectedID, !wanted.contains(selectedID) { wanted.append(selectedID) }
        var visibleIDs: Set<UUID> = []
        for id in wanted {
            guard let target = scoreTarget(for: id) else { continue }
            visibleIDs.insert(target.place.id)
            if scoreTargets[id] == nil {
                scoreTargets[id] = ScoreTarget(place: target.place, day: target.day)
                source.request(target.place, day: target.day, priority: .onScreen)
            }
        }
        if !visibleIDs.isEmpty { source.setVisible(visibleIDs) }
        observeScores()
    }

    /// A new search (or Clear): stop what this one started and forget its scores.
    func resetScores() {
        scoreGeneration += 1
        if let source = scoreSource { for t in scoreTargets.values { source.cancel(t.place.id, day: t.day) } }
        scoreTargets = [:]
        scoreValues = [:]
        visibleResultIDs = nil
        if cardScore != nil { cardScore = nil }
    }

    /// Reads every tracked slot under observation tracking, applies what it saw, and watches for the next change.
    private func observeScores() {
        guard let source = scoreSource, !scoreTargets.isEmpty else { return }
        scoreGeneration += 1
        watchScores(source, generation: scoreGeneration)
    }

    private func watchScores(_ source: any FindScoreSource, generation: Int) {
        guard scoreGeneration == generation, !scoreTargets.isEmpty else { return }
        let targets = scoreTargets
        let states = withObservationTracking({
            targets.mapValues { source.state(for: $0.place.id, day: $0.day) }
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let source = self.scoreSource else { return }
                self.watchScores(source, generation: generation)
            }
        })
        applyScores(states, targets: targets)
    }

    private func applyScores(_ states: [String: ConditionsLoadState], targets: [String: ScoreTarget]) {
        let at = now()
        var changed: [String] = []
        for (id, state) in states {
            guard let target = targets[id] else { continue }
            let next = FindScore.make(state: state, place: target.place, now: at)
            if scoreValues[id] != next {
                scoreValues[id] = next
                changed.append(id)
            }
        }
        guard !changed.isEmpty else { return }
        for id in changed { refreshRow(id) }
        rebuildMapContent()
        if let id = selectedID, changed.contains(id) { cardScore = scoreValues[id] }
    }
}

struct ScoreTarget: Equatable, Sendable {
    var place: Place
    var day: LocalDay
}

/// A source the test or preview drives by hand: it answers each request from a script (by place) and records what was asked.
@MainActor @Observable
public final class FakeFindScores: FindScoreSource {
    public struct Request: Equatable, Sendable {
        public var placeID: UUID
        public var day: LocalDay
        public var priority: ConditionsPriority
    }
    private struct Key: Hashable { var id: UUID; var day: LocalDay }
    private var states: [Key: ConditionsLoadState] = [:]
    @ObservationIgnored public private(set) var requests: [Request] = []
    @ObservationIgnored public private(set) var visibleSets: [Set<UUID>] = []
    @ObservationIgnored public private(set) var cancelled: [UUID] = []
    /// When set, a request is answered at once with this state (a preview or a test that wants scores without ticking).
    @ObservationIgnored public var script: (@MainActor (Place, LocalDay) -> ConditionsLoadState?)?

    public init() {}

    public func set(_ state: ConditionsLoadState, place: UUID, day: LocalDay) { states[Key(id: place, day: day)] = state }
    public func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState { states[Key(id: placeID, day: day)] ?? .idle }
    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) {
        requests.append(Request(placeID: place.id, day: day, priority: priority))
        if let s = script?(place, day) { states[Key(id: place.id, day: day)] = s }
        else if states[Key(id: place.id, day: day)] == nil { states[Key(id: place.id, day: day)] = .loading(previous: nil) }
    }
    public func setVisible(_ placeIDs: Set<UUID>) { visibleSets.append(placeIDs) }
    public func cancel(_ placeID: UUID, day: LocalDay) { cancelled.append(placeID) }
}
