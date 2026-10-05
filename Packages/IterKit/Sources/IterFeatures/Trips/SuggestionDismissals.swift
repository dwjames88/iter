import Foundation

/// Light-first suggestions the user waved away, remembered for the session per trip, day and proposed order.
/// A different order (the plan changed) is a new suggestion and shows again.
@MainActor
public final class SuggestionDismissals {
    public static let shared = SuggestionDismissals()

    private struct Key: Hashable {
        var trip: UUID
        var day: Int
        var order: [UUID]
    }

    private var keys: Set<Key> = []

    public init() {}

    public func dismiss(trip: UUID, day: Int, order: [UUID]) {
        keys.insert(Key(trip: trip, day: day, order: order))
    }

    public func isDismissed(trip: UUID, day: Int, order: [UUID]) -> Bool {
        keys.contains(Key(trip: trip, day: day, order: order))
    }
}
