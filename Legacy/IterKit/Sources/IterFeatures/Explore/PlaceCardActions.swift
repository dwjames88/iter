import Foundation
import IterCore
import IterData

/// What the place card's action buttons do, apart from drawing them: Save, Add to Trip (an existing trip's day, or a
/// new trip), Open in Maps. Views call these and show the result; tests call them with an in-memory store and a
/// recording `openInMaps`, so "the button's action ran" is checked without any UI or launching Maps.
@MainActor
public struct PlaceCardActions {
    /// The result of adding a spot to a trip, for the card's confirmation.
    public struct Added: Equatable, Sendable {
        public let tripID: UUID
        public let tripName: String
        /// 1-based, as the menu shows it.
        public let dayNumber: Int
        public let isNewTrip: Bool

        /// "Added to Utah, Day 2" or "Added to a new trip".
        public var message: String {
            isNewTrip
                ? String(localized: "Added to “\(tripName)”", comment: "Place card: confirmation after Add to Trip made a new trip")
                : String(localized: "Added to “\(tripName)”, Day \(dayNumber)", comment: "Place card: confirmation after Add to Trip, with the day")
        }
    }

    public let store: IterStore
    /// Opens the spot in Apple Maps. The app passes `MKMapItem.openInMaps`; tests pass a recorder.
    public let openInMapsHandler: @MainActor (Spot) -> Void
    /// The day a new trip starts on for a spot: tomorrow in the spot's time zone.
    public let tomorrow: @MainActor (Spot) -> LocalDay

    public init(store: IterStore, tomorrow: @escaping @MainActor (Spot) -> LocalDay,
                openInMaps: @escaping @MainActor (Spot) -> Void) {
        self.store = store
        self.tomorrow = tomorrow
        self.openInMapsHandler = openInMaps
    }

    // MARK: Save

    /// Whether the spot is saved (or your own, which always is).
    public func isSaved(_ spot: Spot) -> Bool { store.isSaved(spotID: spot.id) }

    /// Flips the saved state and returns the new one.
    @discardableResult
    public func toggleSaved(_ spot: Spot) -> Bool {
        let now = !isSaved(spot)
        store.setSaved(spot, now)
        return isSaved(spot)
    }

    // MARK: Add to Trip

    /// Adds the spot to `day` (0-based) of the trip.
    @discardableResult
    public func add(_ spot: Spot, to trip: TripRecord, day: Int) -> Added {
        _ = store.addStop(spot, to: trip, day: day)
        return Added(tripID: trip.id, tripName: trip.name, dayNumber: day + 1, isNewTrip: false)
    }

    /// Makes a one-day trip starting tomorrow and puts the spot on it.
    @discardableResult
    public func addToNewTrip(_ spot: Spot, name: String) -> Added {
        let trip = store.createTrip(name: name, startDay: tomorrow(spot), dayCount: 1)
        _ = store.addStop(spot, to: trip, day: 0)
        return Added(tripID: trip.id, tripName: trip.name, dayNumber: 1, isNewTrip: true)
    }

    // MARK: Open in Maps

    public func openInMaps(_ spot: Spot) { openInMapsHandler(spot) }
}
