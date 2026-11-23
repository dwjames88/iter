import Foundation
import CoreData
import SwiftData
import Testing
import IterModel
@testable import IterStore

/// Each fixture store, written by the OLD module, opened by the new one and compared with what the old code read back.
@Suite struct FixtureMigrationTests {
    /// Reads the whole V5 store and compares it with `expected.json` (the field-by-field checks live in
    /// `StoreComparison`, shared with the real-store dry run).
    func assertMatches(_ container: ModelContainer, _ expected: ExpectedStore) throws {
        let context = ModelContext(container)
        let result = try StoreComparison.compare(context: context, expected: expected)
        #expect(result.differences.isEmpty, Comment(rawValue: result.summary))
        #expect(result.checkCount > 0)

        // Flattened folders were stamped by this open, after the fixture was written.
        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        for id in expected.flattenedFolderIDs {
            let got = try #require(folders.first { $0.id == id })
            #expect(got.parent == nil)
            let want = try #require(expected.folders.first { $0.id == id })
            #expect(got.updatedAt.timeIntervalSinceReferenceDate > want.updatedAt)
        }
    }

    func assertCarriesV5Metadata(_ url: URL) throws {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url, options: nil)
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: IterSchemaV5.models))
        let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        #expect(hashes == model.entityVersionHashesByName)
        #expect(metadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["5.0.0"])
        #expect(try StoreSchemaDetector.detect(storeURL: url) == .v5)
    }

    /// The pure migration: `makeContainer(url:)` alone, with no opener around it.
    @Test(arguments: ExpectedStore.fixtureNames)
    func containerMigratesFixtureToV5(fixture: String) throws {
        let dir = try TestSupport.copyFixtureStore(fixture)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        let expected = try ExpectedStore.load(fixture)
        do {
            let container = try IterStoreSchema.makeContainer(url: url)
            // The opener flattens on every open; here the fixup is run by hand.
            let flattened = try FolderFlatten.flattenFolders(in: ModelContext(container))
            #expect(flattened == expected.flattenedFolderIDs.count)
            try assertMatches(container, expected)
            // Idempotent.
            #expect(try FolderFlatten.flattenFolders(in: ModelContext(container)) == 0)
        }
        try assertCarriesV5Metadata(url)
    }

    @Test(arguments: ExpectedStore.fixtureNames)
    func openerMigratesFixtureToV5(fixture: String) throws {
        let dir = try TestSupport.copyFixtureStore(fixture)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        let expected = try ExpectedStore.load(fixture)
        do {
            let outcome = try StoreOpener(storeURL: url, backupsDirectory: dir.appending(path: "Backups")).open()
            #expect(outcome.activeURL == url)
            #expect(outcome.recovered == nil)
            #expect(outcome.backupFolder != nil)
            try assertMatches(outcome.container, expected)
        }
        try assertCarriesV5Metadata(url)
    }

    @Test(arguments: [("v1", StoreSchemaVersion.v1), ("v2", .v2), ("v3", .v3), ("v4-realistic", .v4)])
    func detectorReadsEachFixtureVersion(fixture: String, version: StoreSchemaVersion) throws {
        let dir = try TestSupport.copyFixtureStore(fixture)
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = try TestSupport.storeHashes(dir: dir)
        let scratch = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(try StoreSchemaDetector.detectOnCopy(storeURL: dir.appending(path: "Iter.store"), scratchDirectory: scratch) == version)
        // Detecting must not change the store, its -wal or its -shm, and leaves no scratch behind.
        #expect(TestSupport.names(in: scratch).isEmpty)
        #expect(try TestSupport.storeHashes(dir: dir) == before)
    }

    @Test func v4RealisticHasWhatTheOwnerStoreHas() throws {
        // Guard the fixture itself: folders, pins, transfer timings and drive notes are all present.
        let expected = try ExpectedStore.load("v4-realistic")
        #expect(expected.folders.contains { $0.isPinned })
        #expect(expected.trips.contains { $0.isPinned })
        #expect(expected.trips.contains { !$0.transferTimingsRaw.isEmpty })
        #expect(expected.stops.contains { !$0.driveNote.isEmpty })
    }
}
