import SwiftUI
import UIKit
import IterFeatures
import IterStore
import IterUI

@main
struct IterIOSApp: App {
    @UIApplicationDelegateAdaptor(IterAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            switch IOSLaunch.result {
            case .ready(let shell): IOSRoot(shell: shell)
            case .failed(let failure): IOSStoreFailureView(failure: failure)
            }
        }
    }
}

/// Runs before any scene: installs Go's background task and notification delegate.
final class IterAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { GoLaunchHooks.install(shell: { IOSLaunch.shell }) }
        return true
    }
}

/// The store could not be opened. Shown instead of crashing; nothing was changed on disk by the failed open.
struct IOSStoreFailure: Equatable {
    var message: String
    var backupFolder: URL
}

enum IOSLaunchResult {
    case ready(IOSShell)
    case failed(IOSStoreFailure)
}

/// Builds the shell once per process, reachable from the App and the app delegate (which runs before any scene).
@MainActor
enum IOSLaunch {
    static let result: IOSLaunchResult = launch()

    static var shell: IOSShell? {
        if case .ready(let shell) = result { shell } else { nil }
    }

    /// The launch switches, plus (Debug builds only) the Settings switch for sample data, which takes effect on next launch.
    static func options(from base: LaunchOptions = .current, defaults: UserDefaults = .standard) -> LaunchOptions {
        var options = base
        #if DEBUG
        if defaults.bool(forKey: "IterDebugSampleData") { options.sampleData = true }
        #endif
        return options
    }

    static func launch(makeContainer: (() throws -> AppContainer)? = nil) -> IOSLaunchResult {
        do {
            let container = try makeContainer?() ?? AppContainer.live(options: options(), bundleID: Bundle.main.bundleIdentifier,
                                                                    environment: ProcessInfo.processInfo.environment)
            // Location is asked at launch (When In Use); nothing is gated on the answer. Fixed and inert providers never prompt.
            container.location.start()
            let shell = IOSShell(container: container)
            shell.apply(.current)
            return .ready(shell)
        } catch {
            let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
                ?? URL.applicationSupportDirectory
            return .failed(IOSStoreFailure(message: IOSStoreFailureText.message(for: error),
                                           backupFolder: StoreLocations.backupsDirectory(applicationSupportDirectory: support)))
        }
    }
}

enum IOSStoreFailureText {
    static func message(for error: any Error) -> String {
        "Iter couldn't open your library. Nothing was changed or deleted. Close Iter and open it again. "
            + "If this keeps happening, your backups are in the folder below.\n\n\(String(describing: error))"
    }
}
