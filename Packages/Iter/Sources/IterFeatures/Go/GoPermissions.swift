import Foundation
import IterGo

/// What Go still needs from the user, and the one thing to ask for next (BLUEPRINT §10.6).
public enum GoPermissionStep: Hashable, Sendable {
    /// Location has not been asked: ask for When In Use.
    case locationWhenInUse
    /// When In Use only, and a run is starting or active: ask for Always, with the sentence that says why.
    case locationAlways(reason: String)
    /// Notifications have not been asked.
    case notifications
    /// Denied (or restricted): the system will not ask again; send the user to Settings.
    case openSettings(for: GoPermissionTopic)
    /// Informational: Live Activities are turned off in Settings, so the Lock Screen card will not appear.
    case liveActivitiesOff
}

public enum GoPermissionTopic: Hashable, Sendable {
    case location, notifications
}

/// The three permission inputs Go cares about and the run state, as a value. `nextStep` is a pure function of them.
public struct GoPermissions: Hashable, Sendable {
    public static let alwaysReason = "Always lets Iter notice when you arrive at a stop while your phone is locked."

    public var location: LocationAuthorization
    public var notifications: NotificationAuthorization
    public var liveActivitiesEnabled: Bool
    public var runPhase: GoPhase

    public init(location: LocationAuthorization = .notDetermined, notifications: NotificationAuthorization = .notDetermined,
                liveActivitiesEnabled: Bool = true, runPhase: GoPhase = .idle) {
        self.location = location
        self.notifications = notifications
        self.liveActivitiesEnabled = liveActivitiesEnabled
        self.runPhase = runPhase
    }

    /// A run exists and has not ended (armed, driving, at a stop, between stops, paused).
    public var runIsStartingOrActive: Bool { runPhase != .idle && runPhase != .finished }

    /// Location can be read (When In Use or Always).
    public var canUseLocation: Bool { location.isAuthorized }

    public var nextStep: GoPermissionStep? {
        Self.nextStep(location: location, notifications: notifications, liveActivitiesEnabled: liveActivitiesEnabled, runPhase: runPhase)
    }

    /// Order: location first (nothing works without it), then Always, then notifications, then the Live Activity note.
    public static func nextStep(location: LocationAuthorization, notifications: NotificationAuthorization, liveActivitiesEnabled: Bool,
                                runPhase: GoPhase) -> GoPermissionStep? {
        switch location {
        case .notDetermined: return .locationWhenInUse
        case .denied, .restricted: return .openSettings(for: .location)
        case .whenInUse where runPhase != .idle && runPhase != .finished: return .locationAlways(reason: alwaysReason)
        case .whenInUse, .always: break
        }
        switch notifications {
        case .notDetermined: return .notifications
        case .denied: return .openSettings(for: .notifications)
        case .authorized, .provisional: break
        }
        return liveActivitiesEnabled ? nil : .liveActivitiesOff
    }
}
