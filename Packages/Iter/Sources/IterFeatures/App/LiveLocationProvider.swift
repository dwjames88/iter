import Foundation
import Observation
import CoreLocation
import IterModel

/// The device location for the real app (CoreLocation). `start()` asks for When-In-Use authorisation once, at launch, and
/// streams fixes; nothing in the app waits on it. Never constructed by tests or render copies (they use
/// `FixedLocationProvider` or `InertLocationProvider`), because creating the manager is what can show a permission dialog.
@MainActor @Observable
public final class LiveLocationProvider: LocationProviding {
    public private(set) var current: Coordinate?
    public private(set) var status: LocationStatus = .notDetermined

    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var delegate: Delegate?

    public init() {}

    public func start() {
        guard manager == nil else { return }
        let delegate = Delegate { [weak self] event in self?.handle(event) }
        let manager = CLLocationManager()
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 250
        self.delegate = delegate
        self.manager = manager
        apply(manager.authorizationStatus)
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if status == .authorized { manager.startUpdatingLocation() }
    }

    public func stop() {
        manager?.stopUpdatingLocation()
    }

    // MARK: Events

    fileprivate enum Event: Sendable {
        case authorization(CLAuthorizationStatus)
        case fix(Coordinate)
    }

    private func handle(_ event: Event) {
        switch event {
        case .authorization(let s):
            apply(s)
            if status == .authorized { manager?.startUpdatingLocation() }
        case .fix(let c):
            current = c
        }
    }

    private func apply(_ s: CLAuthorizationStatus) {
        switch s {
        case .notDetermined: status = .notDetermined
        case .denied, .restricted: status = .denied
        default: status = .authorized
        }
    }

    private final class Delegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        private let send: @Sendable (Event) -> Void

        init(_ handler: @escaping @MainActor (Event) -> Void) {
            send = { event in Task { @MainActor in handler(event) } }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            send(.authorization(manager.authorizationStatus))
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
            send(.fix(Coordinate(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude)))
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
    }
}
