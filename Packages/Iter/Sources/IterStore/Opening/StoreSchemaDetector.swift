import Foundation
import CoreData
import SwiftData

/// Which schema a store file is at.
public enum StoreSchemaVersion: Int, Comparable, Sendable, CaseIterable {
    case v1 = 1, v2, v3, v4, v5

    public static func < (a: StoreSchemaVersion, b: StoreSchemaVersion) -> Bool { a.rawValue < b.rawValue }

    public var versionString: String { "\(rawValue).0.0" }

    var models: [any PersistentModel.Type] {
        switch self {
        case .v1: IterSchemaV1.models
        case .v2: IterSchemaV2.models
        case .v3: IterSchemaV3.models
        case .v4: IterSchemaV4.models
        case .v5: IterSchemaV5.models
        }
    }
}

/// Reads which schema a store is at WITHOUT opening it with SwiftData: the store's `NSStoreModelVersionHashes` metadata
/// is compared with the Core Data model SwiftData builds for each schema.
public enum StoreSchemaDetector {
    /// Detects on a throwaway COPY of the store file and its `-wal` and `-shm`, so the original is never touched.
    ///
    /// Reading the metadata in place is not free of side effects: SQLite rewrites the `-shm` index (and may checkpoint a
    /// non-empty `-wal`), so even this "read only" call would change the bytes of the owner's files. The opener promises
    /// those files stay byte for byte intact until the backup exists, so it always detects on a copy.
    public static func detectOnCopy(storeURL: URL, scratchDirectory: URL) throws -> StoreSchemaVersion? {
        let fm = FileManager.default
        let dir = scratchDirectory.appending(path: "iter-detect-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let name = storeURL.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let source = storeURL.deletingLastPathComponent().appending(path: name + suffix)
            if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: dir.appending(path: name + suffix)) }
        }
        return try detect(storeURL: dir.appending(path: name))
    }

    /// Detects in place. SQLite may rewrite the store's `-shm` while doing this: use `detectOnCopy` for a user's store.
    /// nil when the metadata matches no known schema (a store from a newer build, or not an Iter store).
    public static func detect(storeURL: URL) throws -> StoreSchemaVersion? {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL, options: nil)
        for version in StoreSchemaVersion.allCases.reversed() {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: version.models) else { continue }
            if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) { return version }
        }
        return nil
    }
}
