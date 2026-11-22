@_exported import IterGoActivity
import Foundation
import IterModel
import IterSources

// Types every part of the trip-mode engine shares. Each part (run, location, ETA, conditions, notifications, activity)
// owns its own directory; only these cross between them.

/// One position fix. `timestamp` is the fix's own time, never `Date.now`.
public struct LocationFix: Codable, Hashable, Sendable {
    public var coordinate: Coordinate
    /// Horizontal accuracy, metres (CoreLocation's 68 % radius). Negative is invalid.
    public var accuracyM: Double
    /// Metres per second; nil when unknown (CoreLocation's negative speed).
    public var speedMs: Double?
    /// Degrees from true north; nil when unknown.
    public var courseDeg: Double?
    public var timestamp: Date

    public init(coordinate: Coordinate, accuracyM: Double, speedMs: Double? = nil, courseDeg: Double? = nil, timestamp: Date) {
        self.coordinate = coordinate
        self.accuracyM = accuracyM
        self.speedMs = speedMs
        self.courseDeg = courseDeg
        self.timestamp = timestamp
    }

    /// Usable for decisions: valid and no worse than `maxAccuracyM`.
    public func isUsable(maxAccuracyM: Double = 200) -> Bool { accuracyM >= 0 && accuracyM <= maxAccuracyM }
}

/// The device's power situation. Low Power Mode or a battery below 20 % stretches every interval (§10.6).
public struct PowerState: Codable, Hashable, Sendable {
    public var isLowPowerMode: Bool
    /// 0...1, nil when unknown (the simulator, a Mac).
    public var batteryLevel: Double?
    public var isCharging: Bool

    public init(isLowPowerMode: Bool = false, batteryLevel: Double? = nil, isCharging: Bool = false) {
        self.isLowPowerMode = isLowPowerMode
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }

    public static let normal = PowerState()

    /// Low Power Mode, or under 20 % and not charging.
    public var isSaving: Bool {
        if isLowPowerMode { return true }
        if let batteryLevel, batteryLevel < 0.2, !isCharging { return true }
        return false
    }
}

/// Reads the power state. The iOS adapter reads `ProcessInfo.isLowPowerModeEnabled` and `UIDevice.batteryLevel`.
public protocol PowerMonitoring: Sendable {
    func current() -> PowerState
}

/// A fixed power state, for tests and the Mac.
public struct FixedPower: PowerMonitoring {
    public var state: PowerState
    public init(_ state: PowerState = .normal) { self.state = state }
    public func current() -> PowerState { state }
}

/// A clock tests move by hand. `sleep` returns once `now` has reached the deadline (tests advance time and then yield).
public final class ManualClock: SourceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    public init(_ start: Date) { _now = start }

    public var now: Date { lock.withLock { _now } }

    public func set(_ date: Date) { lock.withLock { _now = date } }
    public func advance(by seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }

    public func sleep(for duration: Duration) async throws {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let deadline = now.addingTimeInterval(seconds)
        while now < deadline {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}
