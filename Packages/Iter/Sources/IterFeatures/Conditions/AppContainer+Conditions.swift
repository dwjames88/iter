import Foundation
import IterModel
import IterAstro

extension AppContainer {
    /// A Conditions model for `place`, on the container's shared `ConditionsStore` and `ConditionsService` (so every screen
    /// shares loads) and the container's clock.
    public func makeConditionsModel(place: Place, selectedDay: LocalDay? = nil) -> ConditionsModel {
        ConditionsModel(place: place, feed: StoreConditionsFeed(store: conditions, service: conditionsService), ephemeris: Astronomy(),
                        now: now, selectedDay: selectedDay)
    }
}
