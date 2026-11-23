import SwiftUI
import IterFeatures

// OWNER: W1 (shell). Replace freely; keep `IOSLaunch.shell` as the one place the shell is built.

@main
struct IterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            if let shell = IOSLaunch.shell {
                Text(verbatim: "Iter \(shell.library.trips.count)")
            } else {
                Text(verbatim: "Iter")
            }
        }
    }
}

/// Builds the shell once per process, reachable from the App and the app delegate (which runs before any scene).
@MainActor
enum IOSLaunch {
    static let shell: IOSShell? = {
        guard let container = try? AppContainer.live(options: .current, bundleID: Bundle.main.bundleIdentifier,
                                                     environment: ProcessInfo.processInfo.environment) else { return nil }
        return IOSShell(container: container)
    }()
}
