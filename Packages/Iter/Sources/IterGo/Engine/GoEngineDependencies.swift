import Foundation
import IterSources

/// Everything the engine talks to. Tests pass fakes for all of it.
@MainActor
public struct GoEngineDependencies {
    public var clock: any SourceClock
    public var routing: any RoutingProvider
    public var conditions: any TripConditionsProviding
    public var location: any LiveLocation
    public var notifications: any NotificationScheduling
    public var activity: any LiveActivityControlling
    public var snapshotStore: any GoSnapshotStoring
    public var widgetReloader: any WidgetReloading
    public var persistence: any RunPersisting
    public var engineState: any GoEngineStateStoring
    public var power: any PowerMonitoring
    public var background: any BackgroundScheduling

    public init(clock: any SourceClock, routing: any RoutingProvider, conditions: any TripConditionsProviding, location: any LiveLocation,
                notifications: any NotificationScheduling, activity: any LiveActivityControlling, snapshotStore: any GoSnapshotStoring,
                widgetReloader: any WidgetReloading, persistence: any RunPersisting, engineState: any GoEngineStateStoring,
                power: any PowerMonitoring, background: any BackgroundScheduling) {
        self.clock = clock
        self.routing = routing
        self.conditions = conditions
        self.location = location
        self.notifications = notifications
        self.activity = activity
        self.snapshotStore = snapshotStore
        self.widgetReloader = widgetReloader
        self.persistence = persistence
        self.engineState = engineState
        self.power = power
        self.background = background
    }
}
