import Foundation

/// Where the Mac app's data lives, and the one-time move from the old App Sandbox container.
///
/// Iter used to be sandboxed. Direct distribution (in-app updates replace the app bundle) needs it unsandboxed, and
/// an unsandboxed app that asked SwiftData for its default store would get `~/Library/Application Support/default.store`,
/// a file shared with every other unsandboxed app that does the same. So the direct build opens an explicit URL,
/// `~/Library/Application Support/Iter/Iter.store`, and copies the sandbox container's data there once.
/// The container is never modified: it stays as a backup.
public enum StoreLocation {
    /// What a migration did. All names are relative paths, for logging and tests.
    public struct MigrationResult: Equatable, Sendable {
        /// Store files copied to the new location (`Iter.store`, `Iter.store-wal`, `.Iter_SUPPORT`, ...).
        public var storeItems: [String] = []
        /// Items copied from the container's `Application Support/Iter/` folder (offline packs, forecast cache).
        public var supportItems: [String] = []
        public init(storeItems: [String] = [], supportItems: [String] = []) {
            self.storeItems = storeItems
            self.supportItems = supportItems
        }
        public var didMigrate: Bool { !storeItems.isEmpty || !supportItems.isEmpty }
    }

    /// The marker written into UserDefaults once preferences were copied.
    public static let preferencesMigratedKey = "IterMigratedFromSandbox"

    /// True when the process runs in the App Sandbox.
    public static func isSandboxed(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static func applicationSupport(home: URL) -> URL {
        home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/Iter/Iter.store`.
    public static func directStoreURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupport(home: home).appending(path: "Iter/Iter.store", directoryHint: .notDirectory)
    }

    private static func containerSupport(bundleIdentifier: String, home: URL) -> URL {
        home.appending(path: "Library/Containers/\(bundleIdentifier)/Data/Library/Application Support", directoryHint: .isDirectory)
    }

    /// Copies the sandbox container's store and `Iter/` folder to the direct locations.
    ///
    /// Runs only when `Iter.store` does not exist yet and the container has a `default.store`. Copies go to temporary
    /// names and are renamed at the end, the store file last, so a crash never leaves a half store at the final name
    /// (the next launch simply tries again). Items already at the destination are never overwritten.
    @discardableResult
    public static func migrateFromSandboxContainer(bundleIdentifier: String,
                                                   home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                                   fileManager fm: FileManager = .default) throws -> MigrationResult {
        let source = containerSupport(bundleIdentifier: bundleIdentifier, home: home)
        let destinationStore = directStoreURL(home: home)
        let destinationDirectory = destinationStore.deletingLastPathComponent()
        guard !fm.fileExists(atPath: destinationStore.path),
              fm.fileExists(atPath: source.appending(path: "default.store").path) else { return MigrationResult() }

        var result = MigrationResult()
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        // 1. Copy to temporary names. Order matters only for the rename step below.
        let pairs: [(from: String, to: String)] = [
            ("default.store-shm", "Iter.store-shm"), ("default.store-wal", "Iter.store-wal"),
            (".default_SUPPORT", ".Iter_SUPPORT"), ("default.store", "Iter.store"),
        ]
        var staged: [(temp: URL, final: URL, name: String)] = []
        func discardStaged() { for item in staged { try? fm.removeItem(at: item.temp) } }
        do {
            for pair in pairs {
                let from = source.appending(path: pair.from)
                guard fm.fileExists(atPath: from.path) else { continue }
                let temp = destinationDirectory.appending(path: pair.to + ".migrating-\(UUID().uuidString)")
                try fm.copyItem(at: from, to: temp)
                staged.append((temp, destinationDirectory.appending(path: pair.to), pair.to))
            }
            // 2. Rename. Side files first; the store last, because its existence is what marks the migration done.
            //    Leftovers at the final names can only be orphans of an earlier crashed attempt (the store is absent).
            for item in staged {
                if fm.fileExists(atPath: item.final.path) { try fm.removeItem(at: item.final) }
                try fm.moveItem(at: item.temp, to: item.final)
                result.storeItems.append(item.name)
            }
        } catch {
            discardStaged()
            throw error
        }

        // 3. The rest of the old Application Support/Iter folder (OfflinePacks, ForecastCache), merged.
        let oldSubtree = source.appending(path: "Iter", directoryHint: .isDirectory)
        if fm.fileExists(atPath: oldSubtree.path) {
            try merge(from: oldSubtree, into: destinationDirectory, relativeTo: "", fileManager: fm, copied: &result.supportItems)
        }
        return result
    }

    /// Copies every item of `from` that does not exist in `into`, descending into folders that exist on both sides.
    private static func merge(from: URL, into: URL, relativeTo prefix: String, fileManager fm: FileManager,
                              copied: inout [String]) throws {
        try fm.createDirectory(at: into, withIntermediateDirectories: true)
        let children = try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: [.isDirectoryKey])
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = child.lastPathComponent
            let target = into.appending(path: name)
            let relative = prefix.isEmpty ? name : prefix + "/" + name
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: child, to: target)
                copied.append(relative)
            } else if isDirectory {
                var isTargetDirectory: ObjCBool = false
                if fm.fileExists(atPath: target.path, isDirectory: &isTargetDirectory), isTargetDirectory.boolValue {
                    try merge(from: child, into: target, relativeTo: relative, fileManager: fm, copied: &copied)
                }
            }
        }
    }

    /// Copies the sandbox container's preferences into `defaults` for keys it does not hold yet, once (guarded by
    /// `IterMigratedFromSandbox`). Returns the number of keys copied; 0 when already done or nothing to copy.
    /// `domain` is the preferences domain `defaults` stands for (the bundle identifier for `.standard`).
    @discardableResult
    public static func migratePreferencesFromSandboxContainer(bundleIdentifier: String,
                                                              home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                                              defaults: UserDefaults = .standard,
                                                              domain: String? = nil) -> Int {
        guard !defaults.bool(forKey: preferencesMigratedKey) else { return 0 }
        let plist = home.appending(path: "Library/Containers/\(bundleIdentifier)/Data/Library/Preferences/\(bundleIdentifier).plist")
        var copied = 0
        if let old = NSDictionary(contentsOf: plist) as? [String: Any] {
            let existing = defaults.persistentDomain(forName: domain ?? bundleIdentifier) ?? [:]
            for (key, value) in old where key != preferencesMigratedKey && existing[key] == nil {
                defaults.set(value, forKey: key)
                copied += 1
            }
        }
        defaults.set(true, forKey: preferencesMigratedKey)
        return copied
    }
}
