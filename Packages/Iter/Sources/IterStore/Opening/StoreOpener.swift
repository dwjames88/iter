import Foundation
import SwiftData
import IterModel

/// Opens the store safely (blueprint §5.3 steps 2, 3 and 5):
///
/// 1. A recovery manifest next to the store that names an existing file wins: that file is opened, never re-recovered.
/// 2. No store file: a fresh V5 store, no backup.
/// 3. The store's schema is read from its metadata WITHOUT opening it with SwiftData. Already V5: open, no backup.
/// 4. Older: back up first (raw files, then every trip as `.iter` v1 from a scratch copy). Any failure removes the
///    partial backup and throws `StoreOpenError.backupFailed`; the real store is not opened and not touched.
/// 5. Open the real store with the full V1 to V5 plan. If that throws, open an EMPTY V5 store under a new name, import
///    the backup's `.iter` files into it, write the manifest and report it, so the app can show a one-time notice.
///    The original file is never deleted, moved or overwritten.
/// 6. Every successful open runs `flattenFolders`.
public struct StoreOpener: Sendable {
    public var storeURL: URL
    public var backupsDirectory: URL
    public var clock: @Sendable () -> Date
    public var files: any StoreFileOperations
    public var containers: StoreContainerFactory
    /// Where the scratch copy for the `.iter` export is made.
    public var scratchDirectory: URL
    /// Encodes a trip as an `.iter` v1 file (injectable so a test can make the export fail).
    public var exportTrip: @Sendable (Trip, Date) throws -> Data

    public init(storeURL: URL, backupsDirectory: URL,
                clock: @escaping @Sendable () -> Date = { Date() },
                files: any StoreFileOperations = DefaultStoreFileOperations(),
                containers: StoreContainerFactory = .live,
                scratchDirectory: URL = FileManager.default.temporaryDirectory,
                exportTrip: @escaping @Sendable (Trip, Date) throws -> Data = { trip, date in
                    try ITERFileV1(trip: trip, exportedAt: date).encoded()
                }) {
        self.storeURL = storeURL
        self.backupsDirectory = backupsDirectory
        self.clock = clock
        self.files = files
        self.containers = containers
        self.scratchDirectory = scratchDirectory
        self.exportTrip = exportTrip
    }

    private var directory: URL { storeURL.deletingLastPathComponent() }
    private var manifestURL: URL { directory.appending(path: RecoveryManifest.fileName) }

    public func open() throws -> StoreOpenOutcome {
        // 1. A recovered store, if the manifest names one that exists.
        if let manifest = readManifest() {
            let active = directory.appending(path: manifest.activeFileName)
            if files.fileExists(at: active) {
                let container: ModelContainer
                do { container = try containers.openCurrent(active) } catch { throw StoreOpenError.openFailed(error) }
                flatten(container)
                return StoreOpenOutcome(container: container, activeURL: active,
                                        backupFolder: URL(filePath: manifest.backupFolder, directoryHint: .isDirectory),
                                        recovered: info(from: manifest))
            }
        }

        // 2. No store yet.
        guard files.fileExists(at: storeURL) else {
            try files.createDirectory(at: directory)
            let container: ModelContainer
            do { container = try containers.openCurrent(storeURL) } catch { throw StoreOpenError.openFailed(error) }
            flatten(container)
            return StoreOpenOutcome(container: container, activeURL: storeURL, backupFolder: nil, recovered: nil)
        }

        // 3. Which schema is it?
        let found: StoreSchemaVersion?
        do { found = try StoreSchemaDetector.detectOnCopy(storeURL: storeURL, scratchDirectory: scratchDirectory) } catch { throw StoreOpenError.schemaDetectionFailed(error) }
        guard let found else { throw StoreOpenError.unrecognizedSchema }

        if found == .v5 {
            let container: ModelContainer
            do { container = try containers.openCurrent(storeURL) } catch { throw StoreOpenError.openFailed(error) }
            flatten(container)
            return StoreOpenOutcome(container: container, activeURL: storeURL, backupFolder: nil, recovered: nil)
        }

        // 4. Older: back up before anything opens it.
        let backup = StoreBackup(storeURL: storeURL, backupsDirectory: backupsDirectory, scratchDirectory: scratchDirectory,
                                 files: files, containers: containers, exportTrip: exportTrip, now: clock())
        let backupFolder: URL
        do { backupFolder = try backup.make(foundVersion: found) } catch { throw StoreOpenError.backupFailed(error) }

        // 5. Open the real store with the full plan; fall back to a recovered store if that fails.
        do {
            let container = try containers.openCurrent(storeURL)
            flatten(container)
            return StoreOpenOutcome(container: container, activeURL: storeURL, backupFolder: backupFolder, recovered: nil)
        } catch let openError {
            return try recover(from: backupFolder, openError: openError)
        }
    }

    /// Marks the one-time recovery notice as shown (rewrites the manifest). No-op when there is no manifest.
    public func markRecoveryNoticeShown() throws {
        guard var manifest = readManifest() else { return }
        manifest.noticeShown = true
        try files.write(try RecoveryManifest.encoder().encode(manifest), to: manifestURL)
    }

    // MARK: - Recovery

    private func recover(from backupFolder: URL, openError: any Error) throws -> StoreOpenOutcome {
        let fm = FileManager.default
        let now = clock()
        let base = storeURL.deletingPathExtension().lastPathComponent
        var name = "\(base)-recovered-\(StoreBackup.timestamp(now)).store"
        var n = 2
        while files.fileExists(at: directory.appending(path: name)) {
            name = "\(base)-recovered-\(StoreBackup.timestamp(now))-\(n).store"
            n += 1
        }
        let recoveredURL = directory.appending(path: name)
        func discardRecovered() {
            for item in StoreBackup.storeItemNames(for: recoveredURL) { try? fm.removeItem(at: directory.appending(path: item)) }
        }
        do {
            let container = try containers.openCurrent(recoveredURL)
            let result = try RecoveryImporter.importBackup(from: backupFolder, into: container, files: files, now: now)
            let manifest = RecoveryManifest(activeFileName: name, originalFileName: storeURL.lastPathComponent,
                                            backupFolder: backupFolder.path, recoveredAt: now, noticeShown: false,
                                            skippedFiles: result.skipped)
            try files.write(try RecoveryManifest.encoder().encode(manifest), to: manifestURL)
            flatten(container)
            return StoreOpenOutcome(container: container, activeURL: recoveredURL, backupFolder: backupFolder,
                                    recovered: info(from: manifest))
        } catch {
            discardRecovered()
            throw StoreOpenError.recoveryFailed(open: openError, recovery: error)
        }
    }

    private func readManifest() -> RecoveryManifest? {
        guard files.fileExists(at: manifestURL), let data = try? files.read(manifestURL) else { return nil }
        return try? RecoveryManifest.decoder().decode(RecoveryManifest.self, from: data)
    }

    private func info(from manifest: RecoveryManifest) -> RecoveryInfo {
        RecoveryInfo(activeURL: directory.appending(path: manifest.activeFileName),
                     originalURL: directory.appending(path: manifest.originalFileName),
                     backupFolder: URL(filePath: manifest.backupFolder, directoryHint: .isDirectory),
                     recoveredAt: manifest.recoveredAt, noticeShown: manifest.noticeShown, skippedFiles: manifest.skippedFiles)
    }

    /// Runs the per-open fixup. Not fatal: a failure here leaves the folders as they were and the next open retries.
    private func flatten(_ container: ModelContainer) {
        let context = ModelContext(container)
        _ = try? FolderFlatten.flattenFolders(in: context, now: clock())
    }
}
