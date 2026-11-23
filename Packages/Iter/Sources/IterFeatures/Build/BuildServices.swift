import Foundation
import IterModel
import IterSky
import IterSources
import IterConditions

/// What the builder reads of one (place, day) slot: the best forecast tier it has reached and each window's score.
public struct ConditionsSample: Equatable, Sendable {
    /// nil until a first report has arrived.
    public var tier: ForecastTier?
    public var scores: [LightWindowKind: Int]
    /// Forecast sources the report is still waiting on.
    public var pendingSources: [SourceID]

    public init(tier: ForecastTier? = nil, scores: [LightWindowKind: Int] = [:], pendingSources: [SourceID] = []) {
        self.tier = tier
        self.scores = scores
        self.pendingSources = pendingSources
    }

    public static let empty = ConditionsSample()
}

/// The part of the Conditions stage the builder uses, protocol-typed so tests and previews inject a fake and the model never
/// holds the whole container. `ConditionsStore` is wrapped by `StoreConditions`.
@MainActor
public protocol BuildConditionsSource: AnyObject {
    /// The places of the trip being built (their loads outrank everything but what is on screen).
    func setActiveTrip(_ placeIDs: Set<UUID>)
    /// The places whose stops are on screen now.
    func setVisible(_ placeIDs: Set<UUID>)
    /// Asks for a place on a day. Loads already running at an equal or higher priority are left alone.
    func request(_ place: Place, day: LocalDay, priority: ConditionsPriority)
    /// What the slot has now. Reads observable state, so a model that reads it inside observation tracking hears about changes.
    func sample(placeID: UUID, day: LocalDay) -> ConditionsSample
}

/// The real thing: `ConditionsStore` seen through `BuildConditionsSource`.
@MainActor
public final class StoreConditions: BuildConditionsSource {
    private let store: ConditionsStore
    public init(_ store: ConditionsStore) { self.store = store }

    public func setActiveTrip(_ placeIDs: Set<UUID>) { store.setActiveTrip(placeIDs) }
    public func setVisible(_ placeIDs: Set<UUID>) { store.setVisible(placeIDs) }

    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) {
        // A slot that already has a complete report is not asked for again; one that is loading keeps its load.
        switch store.state(for: place.id, day: day) {
        case .idle: store.request(place, day: day, priority: priority)
        case .loading: store.request(place, day: day, priority: priority)
        case .ready(let report): if report.tier != .complete { store.request(place, day: day, priority: priority) }
        }
    }

    public func sample(placeID: UUID, day: LocalDay) -> ConditionsSample {
        guard let report = store.state(for: placeID, day: day).report else { return .empty }
        var scores: [LightWindowKind: Int] = [:]
        for window in report.daylight.windows { if let s = window.score { scores[window.kind] = s } }
        var pending: [SourceID] = []
        for part in report.loading { if case .forecast(let id) = part { pending.append(id) } }
        return ConditionsSample(tier: report.tier, scores: scores, pendingSources: pending)
    }
}

/// Offline packs: what the builder needs of `ConditionsService`.
public protocol OfflinePackBuilding: Sendable {
    /// Collects the trip's stops' conditions into the pack file and returns when it was built.
    func buildOfflinePack(for trip: Trip) async throws -> Date
    /// When the stored pack for a trip was built, if there is one.
    func packBuiltAt(tripID: UUID) async -> Date?
}

extension ConditionsService: OfflinePackBuilding {
    public func buildOfflinePack(for trip: Trip) async throws -> Date {
        try await buildPack(for: trip, priority: .pinnedTrip).builtAt
    }

    public func packBuiltAt(tripID: UUID) async -> Date? { pack(for: tripID)?.builtAt }
}
