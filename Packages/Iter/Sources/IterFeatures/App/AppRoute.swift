import Foundation

/// What the detail area shows. Shared by the Mac sidebar and the iOS shells. Sidebar sections (owner's rule): Find, Trips
/// (All Trips, pinned trips, trip folders), Saved Places (folders; replaces "Locations"). Conditions opens from any place.
public enum AppRoute: Hashable, Codable, Sendable {
    case find
    case allTrips
    case trip(UUID)
    case tripFolder(UUID)
    case savedPlaces
    case placeFolder(UUID)
    /// A saved place's own page (Conditions for it, with its card).
    case place(UUID)
}
