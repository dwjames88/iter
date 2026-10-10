import Foundation
import IterCore
import IterData

/// A short, plain description of what the user saves and plans, so Ask and Discovery can lean toward it.
/// Built on this device from the library; it only ever goes into on-device prompts (see `DiscoveryPrompt`).
public enum TasteSummary {
    /// Matches `DiscoveryPrompt.maximumTasteLength`.
    public static let maximumLength = DiscoveryPrompt.maximumTasteLength
    static let maximumPlaces = 5
    static let maximumTrips = 3
    static let maximumCategories = 3
    /// How many recent places are looked at for categories.
    static let categorySample = 12

    /// "Recently saved: Mesa Arch, Tunnel View (desert, landscape); trips: Canyon Country". Pinned places come before
    /// the other saved ones, then the most recently changed; trips are pinned ones first, then the most recent.
    /// Nil when the library has nothing to say. At most `maximumLength` characters.
    @MainActor
    public static func make(store: IterStore) -> String? {
        var places: [PlaceRecord] = []
        var seen = Set<UUID>()
        for place in store.pinnedPlaces() + store.savedPlaces() where seen.insert(place.id).inserted { places.append(place) }
        let trips = (store.pinnedTrips() + store.trips()).reduce(into: [TripRecord]()) { list, trip in
            if !list.contains(where: { $0.id == trip.id }) { list.append(trip) }
        }.prefix(maximumTrips)

        var tally: [SpotCategory: Int] = [:]
        for place in places.prefix(categorySample) { tally[place.category, default: 0] += 1 }
        for trip in trips { for stop in trip.orderedStops { if let place = stop.place { tally[place.category, default: 0] += 1 } } }
        let categories = tally.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .prefix(maximumCategories).map(\.key.rawValue)

        return compose(places: places.prefix(maximumPlaces).map(\.name), categories: categories, trips: trips.map(\.name))
    }

    /// The text for already-chosen names; drops names from the end until it fits `maximumLength`.
    static func compose(places: [String], categories: [String], trips: [String]) -> String? {
        let places = places.map(clean).filter { !$0.isEmpty }
        let trips = trips.map(clean).filter { !$0.isEmpty }
        guard !places.isEmpty || !trips.isEmpty else { return nil }
        var placeCount = places.count, tripCount = trips.count
        while true {
            var parts: [String] = []
            if placeCount > 0 {
                var text = "Recently saved: " + places.prefix(placeCount).joined(separator: ", ")
                if !categories.isEmpty { text += " (" + categories.joined(separator: ", ") + ")" }
                parts.append(text)
            } else if !categories.isEmpty {
                parts.append("Likes: " + categories.joined(separator: ", "))
            }
            if tripCount > 0 { parts.append("trips: " + trips.prefix(tripCount).joined(separator: ", ")) }
            let text = parts.joined(separator: "; ")
            if text.count <= maximumLength { return text.isEmpty ? nil : text }
            if placeCount > 1 { placeCount -= 1 } else if tripCount > 0 { tripCount -= 1 } else if placeCount > 0 { placeCount -= 1 }
            else { return nil }
        }
    }

    private static func clean(_ name: String) -> String {
        let words = name.replacingOccurrences(of: ";", with: " ").split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(60)).trimmingCharacters(in: .whitespaces)
    }
}
