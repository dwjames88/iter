import Foundation
import CoreLocation
import IterCore

public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined, denied, restricted, authorized
}

/// Where the user is. Main-actor isolated because CLLocationManager wants the main thread.
@MainActor
public protocol UserLocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    /// Shows the system dialog the first time; a no-op afterwards.
    func requestAuthorization()
    /// One fix, or nil on failure, denial or timeout.
    func requestFix() async -> Coordinate?
    /// Called whenever the authorization changes (including the initial status after the manager is created).
    var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)? { get set }
}

/// Always authorized, returns a given coordinate (`-IterLocation` and tests).
@MainActor
public final class FixedLocationProvider: UserLocationProviding {
    public let coordinate: Coordinate
    public var authorization: LocationAuthorization { .authorized }
    public var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
    public init(_ coordinate: Coordinate) { self.coordinate = coordinate }
    public func requestAuthorization() {}
    public func requestFix() async -> Coordinate? { coordinate }
}

/// Never prompts, never locates (default in tests and in `AppModel`'s default).
@MainActor
public final class InertLocationProvider: UserLocationProviding {
    public var authorization: LocationAuthorization { .notDetermined }
    public var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
    public init() {}
    public func requestAuthorization() {}
    public func requestFix() async -> Coordinate? { nil }
}

/// CoreLocation-backed provider. The manager is created lazily on the main actor.
@MainActor
public final class CoreLocationProvider: NSObject, UserLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let timeout: Duration
    private var waiters: [UUID: CheckedContinuation<Coordinate?, Never>] = [:]
    public var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?

    public init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public var authorization: LocationAuthorization { Self.map(manager.authorizationStatus) }

    static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        default: .authorized   // authorizedAlways / authorizedWhenInUse
        }
    }

    public func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    public func requestFix() async -> Coordinate? {
        guard authorization == .authorized else { return nil }
        let id = UUID()
        let timeout = self.timeout
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish(id, with: nil)
        }
        let result: Coordinate? = await withCheckedContinuation { continuation in
            waiters[id] = continuation
            manager.requestLocation()
        }
        timer.cancel()
        return result
    }

    private func finish(_ id: UUID, with value: Coordinate?) {
        waiters.removeValue(forKey: id)?.resume(returning: value)
    }

    private func finishAll(with value: Coordinate?) {
        let pending = waiters
        waiters = [:]
        for continuation in pending.values { continuation.resume(returning: value) }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(Self.map(manager.authorizationStatus))
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        finishAll(with: Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finishAll(with: nil)
    }
}
