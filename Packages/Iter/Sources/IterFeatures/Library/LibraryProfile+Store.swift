import Foundation
import IterDiscovery
import IterStore

extension LibraryProfile {
    /// The profile of the library as it is now: saved places and every trip's stops. Read on the main actor at search time;
    /// a few hundred rows at most, so it is cheap. Nothing here is stored or sent anywhere.
    @MainActor
    static func current(in library: LibraryStore) -> LibraryProfile {
        LibraryProfile(savedPlaces: library.places.savedValues(), trips: library.trips.values())
    }
}
