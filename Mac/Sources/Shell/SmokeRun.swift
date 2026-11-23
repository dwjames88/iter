import AppKit
import Foundation
import OSLog
import IterFeatures
import IterStore

/// `-IterSmokeQuitAfter N`: once the window is up (and, for a seeded trip, its Build rows are loaded) print one line to
/// stdout and the unified log, then quit after N seconds. `scripts/smoke-mac.sh` reads the line.
@MainActor
enum SmokeRun {
    static let logger = Logger(subsystem: "com.dwjames.iter", category: "smoke")
    /// How long the window gets to come up and load before the run is called failed.
    static let loadTimeout: Duration = .seconds(25)

    static func readyLine(trips: Int, stops: Int, route: String) -> String {
        "smoke: ready trips=\(trips) stops=\(stops) route=\(route)"
    }

    static func emit(_ line: String) {
        print(line)
        fflush(stdout)
        logger.notice("\(line, privacy: .public)")
    }

    static func runIfRequested(shell: AppShell, window: WindowShell) async {
        guard let quitAfter = shell.smoke.quitAfter, shell.smokeState == .idle else { return }
        shell.smokeState = .waiting
        let options = shell.container.options
        let expectsTripRows = options.seedTrip && options.section?.lowercased() == "trip"
        let clock = ContinuousClock()
        let deadline = clock.now + loadTimeout
        while clock.now < deadline {
            let loaded = window.hasAppeared && (!expectsTripRows || window.currentBuild?.rows.isEmpty == false)
            if loaded { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard window.hasAppeared, !expectsTripRows || window.currentBuild?.rows.isEmpty == false else {
            fail(shell, "the window did not finish loading in \(loadTimeout.components.seconds) s")
            return
        }
        window.library.refresh()
        let trips = window.library.trips.count
        let stops = window.currentBuild?.stops.count ?? window.library.trips.reduce(0) { $0 + $1.stopCount }
        emit(readyLine(trips: trips, stops: stops, route: window.route.shortName))
        shell.smokeState = .ready
        try? await Task.sleep(for: .seconds(quitAfter))
        NSApp.terminate(nil)
    }

    /// If no window ever runs the smoke task (a launch that never builds one), fail instead of hanging.
    static func watchdog(_ shell: AppShell) {
        guard shell.smoke.quitAfter != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: loadTimeout + .seconds(5))
            if shell.smokeState == .idle || shell.smokeState == .waiting { fail(shell, "no window loaded") }
        }
    }

    static func fail(_ shell: AppShell, _ reason: String) {
        shell.smokeState = .failed
        emit("smoke: failed \(reason)")
        exit(1)
    }
}
