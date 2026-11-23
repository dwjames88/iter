import Foundation
import IterDiscovery

extension AppContainer {
    /// The Find model on the container's discovery engine, place search, geocoder, routing, library and preferences.
    public func makeFindModel(configuration: FindConfiguration = FindConfiguration()) -> FindModel {
        FindModel(discoveryFactory: { [unowned self] in self.discovery }, placeSearch: placeSearch, geocoder: geocoder, routing: routing, streetLevel: streetLevel,
                  magnetic: magnetic, gridReference: gridReference, library: library, preferences: preferences, location: location, now: now,
                  configuration: configuration, scores: StoreFindScores(conditions))
    }
}
