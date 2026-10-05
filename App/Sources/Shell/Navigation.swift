import Foundation
import Observation
import IterCore

/// Where the main window is. Trip-first (plan 6.1-A): trips lead the sidebar, then Explore, Saved, Scout.
enum SidebarItem: Hashable, Codable, Sendable {
    case trips
    case trip(UUID)
    case explore
    case saved
    case scout
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
    var savedPath: [SpotRoute] = []
    var scoutPath: [SpotRoute] = []
    var tripPath: [SpotRoute] = []

    /// Explore's search field focus request (Edit > Find).
    var focusSearchRequest = 0
    /// Explore: add-spot mode (click the map to drop a pin).
    var addSpotModeRequest = 0
    /// Trips: a "New Trip" request from the menu or toolbar.
    var newTripRequest = 0
    /// Import request from File > Import Trip.
    var importRequest = 0

    func show(_ item: SidebarItem) { selection = item }

    func open(_ route: SpotRoute) {
        switch selection {
        case .saved: savedPath.append(route)
        case .scout: scoutPath.append(route)
        case .trip, .trips: tripPath.append(route)
        default:
            selection = .explore
            explorePath.append(route)
        }
    }
}
