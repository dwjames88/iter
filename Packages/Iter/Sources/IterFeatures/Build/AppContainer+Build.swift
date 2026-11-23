import Foundation

extension AppContainer {
    /// The builder's model for one trip, wired to this container's library, conditions, routing and clock. Models are created
    /// by the screen that opens the trip and call `open()` and `close()` as it appears and goes.
    public func makeBuildModel(tripID: UUID) -> BuildModel {
        BuildModel(tripID: tripID, library: library, conditions: StoreConditions(conditions), packs: conditionsService,
                   routing: routing, now: now, legStore: plannedLegStore, isSampleData: dataMode == .sample)
    }
}
