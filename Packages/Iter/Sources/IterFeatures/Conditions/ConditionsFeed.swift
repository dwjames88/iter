import Foundation
import IterModel
import IterConditions

/// What `ConditionsModel` needs from the Conditions stage: per (place, day) state it can observe, requests it can make, and
/// "Now". `StoreConditionsFeed` wraps the shared `ConditionsStore` and `ConditionsService`; tests and previews pass a fake.
@MainActor
public protocol ConditionsFeed: AnyObject {
    /// The state of one slot. Must be read from an `@Observable` so a change re-runs the model's tracking.
    func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState
    func request(_ place: Place, day: LocalDay, priority: ConditionsPriority)
    func refresh(_ place: Place, day: LocalDay, priority: ConditionsPriority)
    func cancel(_ placeID: UUID, day: LocalDay)
    /// Current conditions for "Now" (nearest observation, nowcast, current forecast hour).
    func live(for place: Place) async -> LiveConditions
}

/// The live feed: the container's shared `ConditionsStore` (de-duplicated, prioritised, cancellable loads, shared with every
/// other screen) and its `ConditionsService`.
@MainActor
public final class StoreConditionsFeed: ConditionsFeed {
    private let store: ConditionsStore
    private let service: ConditionsService

    public init(store: ConditionsStore, service: ConditionsService) {
        self.store = store
        self.service = service
    }

    public func state(for placeID: UUID, day: LocalDay) -> ConditionsLoadState { store.state(for: placeID, day: day) }
    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) { store.request(place, day: day, priority: priority) }
    public func refresh(_ place: Place, day: LocalDay, priority: ConditionsPriority) { store.refresh(place, day: day, priority: priority) }
    public func cancel(_ placeID: UUID, day: LocalDay) { store.cancel(placeID, day: day) }
    public func live(for place: Place) async -> LiveConditions { await service.live(for: place, priority: .onScreen) }
}
