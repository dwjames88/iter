import Foundation
import IterFeatures
import IterModel
import IterStore

/// What the app owns once, for every window: the composition root and the models built from it. The real store is only
/// ever reached through `AppContainer.live`'s `StorePlacement`; the shell never computes a store path.
@MainActor
final class AppShell {
    let container: AppContainer
    let library: LibraryModel
    let settings: SettingsModel
    let updates: UpdateController
    let smoke: SmokeSwitches

    init(container: AppContainer, smoke: SmokeSwitches = .current, updates: UpdateController = .shared) {
        self.container = container
        self.library = container.libraryModel()
        self.settings = container.settingsModel()
        self.updates = updates
        self.smoke = smoke
    }

    private var recoveryTaken = false
    /// The smoke run belongs to the first window only.
    var smokeState: SmokeState = .idle

    /// The recovery notice, once: the first window to ask gets it while the store says it still needs showing.
    func takeRecoveryNotice() -> RecoveryInfo? {
        guard !recoveryTaken, let info = container.store.recovered, info.needsNotice else { return nil }
        recoveryTaken = true
        return info
    }

    /// Where Debug actions are offered: Debug builds (which include the render copy and the test host).
    static var debugMenuAvailable: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Where the smoke run (`-IterSmokeQuitAfter`) is.
enum SmokeState: Equatable { case idle, waiting, ready, failed }

/// The store could not be opened. Shown in a plain window; nothing was changed on disk by the failed open.
struct StoreFailure: Equatable {
    var message: String
    /// The folder that holds the store's backups, for "Show Backups in Finder".
    var backupFolder: URL
}

/// The outcome of launching: a ready shell, or a failure the app can show instead of crashing.
enum LaunchResult {
    case ready(AppShell)
    case failed(StoreFailure)

    /// Builds the container once from the process's switches. `makeContainer` is injectable so a test can force a failure.
    @MainActor
    static func launch(
        options: LaunchOptions = .current,
        bundleID: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        smoke: SmokeSwitches = .current,
        makeContainer: (() throws -> AppContainer)? = nil
    ) -> LaunchResult {
        do {
            let container = try makeContainer?() ?? AppContainer.live(options: options, bundleID: bundleID, environment: environment)
            // Location is asked at launch and nothing is gated on the answer (fixed and inert providers do nothing).
            container.location.start()
            return .ready(AppShell(container: container, smoke: smoke))
        } catch {
            return .failed(StoreFailure(message: StoreFailureText.message(for: error), backupFolder: StoreLocations.backupsDirectory()))
        }
    }
}

/// The words for a store that would not open.
enum StoreFailureText {
    static func message(for error: any Error) -> String {
        let detail = String(describing: error)
        return "Iter couldn't open your library. Nothing was changed or deleted. Quit Iter, then open it again. "
            + "If this keeps happening, your backups are in the folder below.\n\n\(detail)"
    }
}
