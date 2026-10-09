import Foundation
import Observation
import IterCore

/// Where the main window is. Trip-first (plan 6.1-A): trips lead the sidebar, then Locations, then Explore.
/// A stored selection that no longer decodes (the old `saved` case) falls back to `.trips`.
enum SidebarItem: Hashable, Codable, Sendable {
    case trips
    case trip(UUID)
    case locations
    case locationFolder(UUID)
    case explore
}

/// A request to show a spot page, pushed onto the current section's navigation stack.
struct SpotRoute: Hashable {
    var spot: Spot
    /// The day to open on (e.g. the trip day the stop belongs to); nil = today at the spot.
    var day: LocalDay?
}

/// Window-scoped navigation state. Each main window has its own.
@MainActor
@Observable
final class AppNavigation {
    var selection: SidebarItem? = .trips
    /// Per-section stacks so switching sections keeps your place.
    var explorePath: [SpotRoute] = []
    var locationsPath: [SpotRoute] = []
    var tripPath: [SpotRoute] = []

    /// Explore's search field focus request (Edit > Find).
    var focusSearchRequest = 0
    /// The window's one search field, at the top of the sidebar as in Maps: Explore searches places and asks Iter with
    /// it; Locations filters with it.
    var searchText = ""
    /// Return in the search field: Explore runs the search (switching to Explore from anywhere but Locations).
    var searchSubmitRequest = 0
    /// Explore: add-spot mode (click the map to drop a pin).
    var addSpotModeRequest = 0
    /// Trips: a "New Trip" request from the menu or toolbar.
    var newTripRequest = 0
    /// Import request from File > Import Trip.
    var importRequest = 0
    /// The trip or folder whose sidebar row is being renamed in place; nil = none.
    var renamingID: UUID?

    func show(_ item: SidebarItem) { selection = item }

    func open(_ route: SpotRoute) {
        switch selection {
        case .locations, .locationFolder: locationsPath.append(route)
        case .trip, .trips: tripPath.append(route)
        default:
            selection = .explore
            explorePath.append(route)
        }
    }
}
