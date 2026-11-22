import Foundation
import IterModel
import IterStore

/// Why the composition root could not be built.
public enum AppContainerError: Error {
    /// A non-real process asked for a store path it may not open.
    case storePlacementRefused(StorePlacement.Refusal)
    /// The one-time copy out of the old App Sandbox container failed. The app does NOT go on to open an empty store,
    /// because the next launch would then see a store and never retry the copy.
    case sandboxMigrationFailed(any Error)
    /// `StoreOpener` could not open the store (the original is untouched; see `StoreOpenError`).
    case storeOpenFailed(any Error)
}

/// Opens the library store for a `StorePlacement`. The only code that calls `StoreOpener`.
@MainActor
enum StoreBuilder {
    struct Built {
        var library: LibraryStore
        var status: StoreStatus
        /// Rewrites the recovery manifest (nil in memory).
        var recoveryWriter: (@MainActor () throws -> Void)?
    }

    /// - Parameters:
    ///   - isRealStore: the placement is the owner's real store: backups go to the real backups folder and the one-time
    ///     sandbox migration runs first.
    static func build(placement: StorePlacement, isRealStore: Bool, bundleID: String?, backupsDirectory: URL?,
                      clock: @escaping @Sendable () -> Date) throws -> Built {
        switch placement {
        case .inMemory:
            let container = try IterStoreSchema.makeInMemoryContainer()
            return Built(library: LibraryStore(container: container, clock: clock),
                         status: StoreStatus(placement: placement), recoveryWriter: nil)
        case .file(let url):
            if isRealStore { try migrateSandbox(bundleID: bundleID) }
            let backups = backupsDirectory ?? url.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
            let opener = StoreOpener(storeURL: url, backupsDirectory: backups, clock: clock)
            let outcome: StoreOpenOutcome
            do { outcome = try opener.open() } catch { throw AppContainerError.storeOpenFailed(error) }
            let status = StoreStatus(placement: placement, activeURL: outcome.activeURL, recovered: outcome.recovered,
                                     backupFolder: outcome.backupFolder)
            return Built(library: LibraryStore(container: outcome.container, clock: clock), status: status,
                         recoveryWriter: { try opener.markRecoveryNoticeShown() })
        }
    }

    private static func migrateSandbox(bundleID: String?) throws {
#if os(macOS)
        guard let bundleID else { return }
        do {
            try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: bundleID)
        } catch {
            throw AppContainerError.sandboxMigrationFailed(error)
        }
        StoreLocation.migratePreferencesFromSandboxContainer(bundleIdentifier: bundleID)
#endif
    }
}
