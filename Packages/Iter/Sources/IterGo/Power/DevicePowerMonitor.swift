#if os(iOS)
import Foundation
import UIKit

/// Reads Low Power Mode and the battery. `UIDevice` is main-actor, so the battery is cached from notifications and
/// `current()` (which may be called anywhere) reads the cache; Low Power Mode is read live.
/// Never constructed in tests.
public final class DevicePowerMonitor: PowerMonitoring, @unchecked Sendable {
    private struct Battery { var level: Double?; var charging: Bool }
    private let lock = NSLock()
    private var battery = Battery(level: nil, charging: false)
    private var observers: [any NSObjectProtocol] = []

    @MainActor
    public init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
    }

    deinit { for o in observers { NotificationCenter.default.removeObserver(o) } }

    @MainActor
    private func refresh() {
        let device = UIDevice.current
        let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        let charging = device.batteryState == .charging || device.batteryState == .full
        lock.withLock { battery = Battery(level: level, charging: charging) }
    }

    public func current() -> PowerState {
        let b = lock.withLock { battery }
        return PowerState(isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, batteryLevel: b.level, isCharging: b.charging)
    }
}
#endif
