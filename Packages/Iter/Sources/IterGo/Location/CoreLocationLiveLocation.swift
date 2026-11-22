#if os(iOS)
import CoreLocation
import Foundation
import IterModel

/// The CoreLocation adapter. Never constructed in tests (creating it touches `CLLocationManager`).
///
/// - continuous: a `CLBackgroundActivitySession` keeps the app running while locked, and
///   `CLLocationUpdate.liveUpdates(...)` delivers fixes (profile kind picks the configuration; the distance filter is
///   applied here). Backup regions go to `CLMonitor`.
/// - monitor: `CLMonitor` circular conditions plus `startMonitoringSignificantLocationChanges()`.
/// - off: everything stopped.
@MainActor
public final class CoreLocationLiveLocation: LiveLocation {
    public let events: AsyncStream<LocationEvent>
    private let continuation: AsyncStream<LocationEvent>.Continuation

    private let manager = CLLocationManager()
    private let delegate: Delegate
    private var mode: LocationMode = .off

    private var session: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?
    private var lastDelivered: CLLocation?

    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?
    private var regionTriggers: [String: RegionTrigger] = [:]
    /// Serialises monitor changes so rapid `apply` calls apply in order.
    private var regionWork: Task<Void, Never>?

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: LocationEvent.self, bufferingPolicy: .unbounded)
        delegate = Delegate()
        delegate.onAuthorization = { [weak self] in
            guard let self else { return }
            self.continuation.yield(.authorizationChanged(self.authorization))
        }
        delegate.onLocations = { [weak self] locations in
            for location in locations { self?.deliver(location) }
        }
        delegate.onError = { [weak self] message in self?.continuation.yield(.error(message)) }
        manager.delegate = delegate
    }

    public var authorization: LocationAuthorization { Self.map(manager.authorizationStatus) }

    public func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    public func requestAlways() { manager.requestAlwaysAuthorization() }

    public func apply(_ mode: LocationMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        switch mode {
        case .off:
            stopContinuous()
            stopSignificant()
            setRegions([])
        case .monitor(let regions, let significant):
            stopContinuous()
            if significant { startSignificant() } else { stopSignificant() }
            setRegions(regions)
        case .continuous(let profile, let backup):
            stopSignificant()
            startContinuous(profile)
            setRegions(backup)
        }
    }

    // MARK: Continuous

    private func startContinuous(_ profile: LocationAccuracyProfile) {
        stopContinuous()
        session = CLBackgroundActivitySession()
        let configuration: CLLocationUpdate.LiveConfiguration = switch profile.kind {
        case .automotiveNavigation: .automotiveNavigation
        case .otherNavigation: .otherNavigation
        case .standard: .default
        }
        let filter = profile.distanceFilterM
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard let location = update.location else { continue }
                    guard let self else { return }
                    if filter > 0, let last = self.lastDelivered, location.distance(from: last) < filter { continue }
                    self.deliver(location)
                }
            } catch {
                self?.continuation.yield(.error(error.localizedDescription))
            }
        }
    }

    private func stopContinuous() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
        lastDelivered = nil
    }

    private func startSignificant() { manager.startMonitoringSignificantLocationChanges() }
    private func stopSignificant() { manager.stopMonitoringSignificantLocationChanges() }

    private func deliver(_ location: CLLocation) {
        lastDelivered = location
        continuation.yield(.fix(Self.fix(from: location)))
    }

    /// Negative speed or course (CoreLocation's "unknown") becomes nil.
    nonisolated static func fix(from location: CLLocation) -> LocationFix {
        LocationFix(coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                    accuracyM: location.horizontalAccuracy,
                    speedMs: location.speed >= 0 ? location.speed : nil,
                    courseDeg: location.course >= 0 ? location.course : nil,
                    timestamp: location.timestamp)
    }

    // MARK: Regions

    private func setRegions(_ regions: [MonitoredRegion]) {
        let previous = regionWork
        regionWork = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.syncRegions(regions)
        }
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor("IterGo")
        monitor = created
        monitorTask = Task { [weak self] in
            do {
                for try await event in await created.events {
                    guard let self else { return }
                    self.handle(identifier: event.identifier, state: event.state)
                }
            } catch {
                self?.continuation.yield(.error(error.localizedDescription))
            }
        }
        return created
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) {
        switch (regionTriggers[identifier], state) {
        case (.enter?, .satisfied): continuation.yield(.regionEntered(identifier))
        case (.exit?, .unsatisfied): continuation.yield(.regionExited(identifier))
        default: break
        }
    }

    private func syncRegions(_ regions: [MonitoredRegion]) async {
        let monitor = await ensureMonitor()
        for id in await monitor.identifiers { await monitor.remove(id) }
        regionTriggers = [:]
        for region in regions {
            regionTriggers[region.id] = region.notifyOn
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                radius: max(100, region.radiusM))
            // An exit region starts as "inside"; an enter region as "outside". The first change then fires.
            await monitor.add(condition, identifier: region.id, assuming: region.notifyOn == .exit ? .satisfied : .unsatisfied)
        }
    }

    // MARK: Authorization

    nonisolated static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        @unknown default: .notDetermined
        }
    }

    /// Bridges `CLLocationManagerDelegate` (an `NSObject` protocol) back to the main actor.
    private final class Delegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        nonisolated(unsafe) var onAuthorization: (@MainActor () -> Void)?
        nonisolated(unsafe) var onLocations: (@MainActor ([CLLocation]) -> Void)?
        nonisolated(unsafe) var onError: (@MainActor (String) -> Void)?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            Task { @MainActor in self.onAuthorization?() }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            Task { @MainActor in self.onLocations?(locations) }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
            let message = error.localizedDescription
            Task { @MainActor in self.onError?(message) }
        }
    }
}
#endif
