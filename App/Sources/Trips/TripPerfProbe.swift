import Foundation
import IterCore

/// `-IterPerfProbe YES`: logs the perf counters every 5 seconds (development measurement only). Either perf flag
/// (`-IterPerfProbe` or `-IterPerfScript`) also starts the main-thread lag monitor.
@MainActor
enum TripPerfProbe {
    static func start() {
        IterPerf.startLagMonitorIfRequested()
        guard UserDefaults.standard.bool(forKey: "IterPerfProbe") else { return }
        Task { @MainActor in
            for i in 1...24 {
                try? await Task.sleep(for: .seconds(5))
                IterPerf.report("probe\(i)")
            }
        }
    }
}
