import Foundation

extension AppLaunch {
    /// `-IterEditStops YES`: the trip builder opens in edit mode (reorder handles and delete controls). For screenshots.
    static var editStops: Bool { UserDefaults.standard.bool(forKey: "IterEditStops") }
    /// `-IterRouteCollapsed YES`: the builder's route map starts collapsed to its bar. For screenshots.
    static var routeCollapsed: Bool { UserDefaults.standard.bool(forKey: "IterRouteCollapsed") }
    /// `-IterAddStop YES`: the builder opens the Add stop sheet for the launch day (day 1 by default). For screenshots.
    static var addStop: Bool { UserDefaults.standard.bool(forKey: "IterAddStop") }
    /// `-IterNewTrip YES`: the Trips list opens the New Trip sheet. For screenshots.
    static var newTripSheet: Bool { UserDefaults.standard.bool(forKey: "IterNewTrip") }
    /// `-IterTripsFilter pinned|<folder name>`: the Trips list opens with that chip selected. For screenshots.
    static var tripsFilterName: String? { UserDefaults.standard.string(forKey: "IterTripsFilter") }
}
