import Foundation
import Observation
import IterModel

/// Where the device is, as far as the app knows.
public enum LocationStatus: Sendable, Equatable {
    /// Not asked yet (the live provider asks at launch).
    case notDetermined
    /// Allowed; `current` fills in as fixes arrive.
    case authorized
    /// Denied or restricted in System Settings. Nothing in the app is gated on location; this only changes wording.
    case denied
    /// A fixed location from `-IterLocation`, or a test.
    case fixed
    /// No location at all (an inert provider in tests and previews).
    case unavailable
}

/// The device location behind "near me", reachability and the map's first camera. Location is requested at launch and
/// nothing waits on a "Use My Location" step (owner's rule). Render and test copies use `FixedLocationProvider` or
/// `InertLocationProvider`, which never prompt.
@MainActor
public protocol LocationProviding: AnyObject {
    var current: Coordinate? { get }
    var status: LocationStatus { get }
    /// Starts updates; the live provider asks for permission here, once, at launch.
    func start()
}

/// A fixed location (`-IterLocation lat,lon`, tests). Never prompts.
@MainActor @Observable
public final class FixedLocationProvider: LocationProviding {
    public private(set) var current: Coordinate?
    public var status: LocationStatus { .fixed }
    public init(_ coordinate: Coordinate) { current = coordinate }
    public func start() {}
}

/// No location at all. Never prompts.
@MainActor @Observable
public final class InertLocationProvider: LocationProviding {
    public var current: Coordinate? { nil }
    public var status: LocationStatus { .unavailable }
    public init() {}
    public func start() {}
}
