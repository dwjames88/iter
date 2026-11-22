import Foundation
import Observation
import IterModel

/// What one (place, day) slot shows.
public enum ConditionsLoadState: Sendable, Hashable {
    case idle
    /// Loading; `previous` is the last good report, kept on screen while the refresh runs.
    case loading(previous: SkyReport?)
    /// The latest report. `report.tier` says whether more is still arriving.
    case ready(SkyReport)

    /// The report to show, if any: the ready one or the last good one.
    public var report: SkyReport? {
        switch self {
        case .idle: nil
        case .loading(let previous): previous
        case .ready(let r): r
        }
    }

    public var isLoading: Bool {
        switch self {
        case .loading: true
        case .ready(let r): r.tier != .complete
        case .idle: false
        }
    }
}

/// One observable cell, so a view that reads one slot is not invalidated by loads of another.
@MainActor @Observable
public final class ConditionsSlot {
    public internal(set) var state: ConditionsLoadState = .idle

    init() {}
}

/// The main-actor face of the Conditions stage: per (place id, day) state for views, with de-duplicated, prioritised,
/// cancellable loads. Replaces the legacy ForecastCenter.
///
/// - `request` starts a load unless an equal or more urgent one is running; the last good report stays visible while it runs.
/// - `setVisible` re-prioritises: what left the screen is demoted (its load restarted at background priority) and what came
///   on screen is promoted.
/// - A late answer for a superseded load is dropped (generation guard).
@MainActor @Observable
public final class ConditionsStore {
    private struct SlotKey: Hashable {
        var placeID: UUID
        var day: LocalDay
    }

    private struct Load {
        var generation: UInt64
        var priority: ConditionsPriority
        var place: Place
        var task: Task<Void, Never>
    }

    @ObservationIgnored private let service: ConditionsService
    @ObservationIgnored private var slots: [SlotKey: ConditionsSlot] = [:]
    @ObservationIgnored private var loads: [SlotKey: Load] = [:]
    @ObservationIgnored private var known: [SlotKey: Place] = [:]
    @ObservationIgnored private var baseline: [SlotKey: ConditionsPriority] = [:]
    @ObservationIgnored private var generationCounter: UInt64 = 0
    @ObservationIgnored private var visible: Set<UUID> = []
    @ObservationIgnored private var activeTrip: Set<UUID> = []
    @ObservationIgnored private var pinned: Set<UUID> = []
    @ObservationIgnored private var visibilityKnown = false

    public init(service: ConditionsService) { self.service = service }

    // MARK: Reading

    /// The observable slot for a place and day (created idle).
    public func slot(for placeID: UUID, day: LocalDay) -> ConditionsSlot {
        let key = SlotKey(placeID: placeID, day: day)
        if let s = slots[key] { return s }
        let s = ConditionsSlot()
        slots[key] = s
        return s
    }

    public func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState { slot(for: placeID, day: day).state }

    /// The report to show for a place and day, the last good one while a refresh runs.
    public func report(for placeID: UUID, day: LocalDay) -> SkyReport? { state(for: placeID, day: day).report }

    /// How many loads are running (tests and diagnostics).
    public var activeLoadCount: Int { loads.count }

    // MARK: Requesting

    /// Loads `place` on `day`. An equal or more urgent load already running is left alone.
    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority = .onScreen) {
        let key = SlotKey(placeID: place.id, day: day)
        known[key] = place
        baseline[key] = priority
        let effective = effectivePriority(key)
        if let running = loads[key], running.priority <= effective { return }
        start(key, place: place, priority: effective)
    }

    /// Re-requests a slot whatever is cached (pull to refresh); a running load is restarted.
    public func refresh(_ place: Place, day: LocalDay, priority: ConditionsPriority = .onScreen) {
        let key = SlotKey(placeID: place.id, day: day)
        known[key] = place
        start(key, place: place, priority: min(priority, effectivePriority(key)))
    }

    /// The places on screen now. Their loads are promoted; loads of places that left the screen are demoted.
    public func setVisible(_ placeIDs: Set<UUID>) {
        visible = placeIDs
        visibilityKnown = true
        reprioritise()
    }

    /// The places of the trip being run or built.
    public func setActiveTrip(_ placeIDs: Set<UUID>) {
        activeTrip = placeIDs
        reprioritise()
    }

    /// The places of pinned trips.
    public func setPinned(_ placeIDs: Set<UUID>) {
        pinned = placeIDs
        reprioritise()
    }

    /// Stops a slot's load. The last good report stays.
    public func cancel(_ placeID: UUID, day: LocalDay) {
        let key = SlotKey(placeID: placeID, day: day)
        guard let load = loads.removeValue(forKey: key) else { return }
        load.task.cancel()
        generationCounter += 1
        if case .loading(let previous) = slot(for: placeID, day: day).state {
            slot(for: placeID, day: day).state = previous.map { .ready($0) } ?? .idle
        }
    }

    /// Stops every load.
    public func cancelAll() {
        for (key, load) in loads {
            load.task.cancel()
            if case .loading(let previous) = slot(for: key.placeID, day: key.day).state {
                slot(for: key.placeID, day: key.day).state = previous.map { .ready($0) } ?? .idle
            }
        }
        loads.removeAll()
    }

    // MARK: Internals

    private func effectivePriority(_ key: SlotKey) -> ConditionsPriority {
        if visible.contains(key.placeID) { return .onScreen }
        if activeTrip.contains(key.placeID) { return .activeTrip }
        if pinned.contains(key.placeID) { return .pinnedTrip }
        // Until the screen has said what is visible, a request keeps the urgency it was made with.
        return visibilityKnown ? .background : (baseline[key] ?? .background)
    }

    private func reprioritise() {
        for (key, load) in loads {
            guard let place = known[key] else { continue }
            let p = effectivePriority(key)
            if p != load.priority { start(key, place: place, priority: p) }
        }
    }

    private func start(_ key: SlotKey, place: Place, priority: ConditionsPriority) {
        loads[key]?.task.cancel()
        generationCounter += 1
        let generation = generationCounter
        let slot = slot(for: key.placeID, day: key.day)
        slot.state = .loading(previous: slot.state.report)
        let service = service
        let task = Task { [weak self] in
            let request = ConditionsRequest(place: place, day: key.day, priority: priority)
            for await report in service.reports(for: [request]) {
                guard let self, self.accept(key, generation) else { return }
                slot.state = .ready(report)
            }
            self?.finish(key, generation)
        }
        loads[key] = Load(generation: generation, priority: priority, place: place, task: task)
    }

    /// True when `generation` is still the current load for `key`; a superseded answer is dropped.
    private func accept(_ key: SlotKey, _ generation: UInt64) -> Bool { loads[key]?.generation == generation }

    private func finish(_ key: SlotKey, _ generation: UInt64) {
        guard accept(key, generation) else { return }
        loads[key] = nil
        let s = slot(for: key.placeID, day: key.day)
        if case .loading(let previous) = s.state { s.state = previous.map { .ready($0) } ?? .idle }
    }
}
