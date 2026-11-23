import Foundation
import IterFeatures

/// Which detail view a route shows. Pure, so navigation is testable without a window.
enum DetailKind: Equatable {
    case find, allTrips, trip, savedPlaces, place

    init(_ route: AppRoute) {
        switch route {
        case .find: self = .find
        case .allTrips, .tripFolder: self = .allTrips
        case .trip: self = .trip
        case .savedPlaces, .placeFolder: self = .savedPlaces
        case .place: self = .place
        }
    }
}

extension AppRoute {
    /// A short stable name, for the smoke line.
    var shortName: String {
        switch self {
        case .find: "find"
        case .allTrips: "allTrips"
        case .trip: "trip"
        case .tripFolder: "tripFolder"
        case .savedPlaces: "savedPlaces"
        case .placeFolder: "placeFolder"
        case .place: "place"
        }
    }

    /// The route the window restores from `@SceneStorage` (JSON text; empty means none).
    var stored: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init?(stored: String) {
        guard !stored.isEmpty, let route = try? JSONDecoder().decode(AppRoute.self, from: Data(stored.utf8)) else { return nil }
        self = route
    }

    /// The route for `-IterSection find|trips|places|trip`. `trip` needs a trip id to open (the first trip).
    static func forSection(_ section: String?, firstTripID: UUID?) -> AppRoute? {
        switch section?.lowercased() {
        case "find": .find
        case "trips": .allTrips
        case "places": .savedPlaces
        case "trip": firstTripID.map { .trip($0) } ?? .allTrips
        default: nil
        }
    }
}
