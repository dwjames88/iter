import Foundation
import IterModel

public enum LocationAuthorization: String, Codable, Hashable, Sendable {
    case notDetermined, whenInUse, always, denied, restricted

    /// Location can be read at all.
    public var isAuthorized: Bool { self == .whenInUse || self == .always }
}

public enum LocationEvent: Hashable, Sendable {
    case fix(LocationFix)
    case regionEntered(String)
    case regionExited(String)
    case authorizationChanged(LocationAuthorization)
    case error(String)
}

/// The engine's only view of location hardware. The iOS adapter is `CoreLocationLiveLocation`; tests use `ScriptedLocation`.
/// `apply` is idempotent: applying the mode already running changes nothing.
@MainActor
public protocol LiveLocation: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestWhenInUse()
    func requestAlways()
    func apply(_ mode: LocationMode)
    /// One stream for the life of the object; a second consumer is not supported.
    var events: AsyncStream<LocationEvent> { get }
}
