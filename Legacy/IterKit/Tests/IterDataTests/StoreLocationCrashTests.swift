import Foundation
import Testing
@testable import IterData

/// Interrupted and repeated one-time moves out of the sandbox container.
@Suite struct StoreLocationCrashTests {
    let id = "com.test.crash"

    func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "iter-crash-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func container(_ home: URL) -> URL {
        home.appending(path: "Library/Containers/\(id)/Data/Library/Application Support", directoryHint: .isDirectory)
    }

    /// Symptom: a crash (or an I/O error) while the offline packs were being copied, after the store had been
    /// moved, meant the next launch saw `Iter.store`, stopped, and the remaining packs were never copied.
    @Test func interruptedFolderMergeResumesNextLaunch() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let old = container(home)
        try write("store", to: old.appending(path: "default.store"))
        try write("wal", to: old.appending(path: "default.store-wal"))
        try write("a", to: old.appending(path: "Iter/OfflinePacks/a.pack"))
        let blocked = old.appending(path: "Iter/OfflinePacks/b.pack")
        try write("b", to: blocked)
        try write("c", to: old.appending(path: "Iter/OfflinePacks/c.pack"))

        // Force the merge to fail part way: b.pack cannot be read.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        #expect(throws: (any Error).self) { try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: blocked.path)

        let out = StoreLocation.directStoreURL(home: home).deletingLastPathComponent()
        #expect(text(out.appending(path: "Iter.store")) == "store")
        #expect(text(out.appending(path: "OfflinePacks/b.pack")) == nil)

        // Next launch: finishes the folders, copies nothing twice, leaves no marker or temporary names.
        let resumed = try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home)
        #expect(resumed.storeItems.isEmpty)
        #expect(text(out.appending(path: "OfflinePacks/a.pack")) == "a")
        #expect(text(out.appending(path: "OfflinePacks/b.pack")) == "b")
        #expect(text(out.appending(path: "OfflinePacks/c.pack")) == "c")
        let names = try FileManager.default.subpathsOfDirectory(atPath: out.path)
        #expect(!names.contains { $0.contains(".migrating-") || $0.hasSuffix(StoreLocation.supportPendingName) })

        // And then it is done for good: a pack the user deletes is not copied back.
        try FileManager.default.removeItem(at: out.appending(path: "OfflinePacks/a.pack"))
        #expect(try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home) == StoreLocation.MigrationResult())
        #expect(text(out.appending(path: "OfflinePacks/a.pack")) == nil)
        // The container is untouched.
        #expect(text(old.appending(path: "default.store-wal")) == "wal")
        #expect(text(old.appending(path: "Iter/OfflinePacks/a.pack")) == "a")
    }

    /// A crash between the side-file renames and the store rename leaves orphan side files and no store: the
    /// relaunch replaces them with the container's current ones and the data arrives once.
    @Test func orphanSideFilesFromACrashedAttemptAreReplaced() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let old = container(home)
        try write("store", to: old.appending(path: "default.store"))
        try write("wal-new", to: old.appending(path: "default.store-wal"))
        let out = StoreLocation.directStoreURL(home: home).deletingLastPathComponent()
        try write("wal-stale", to: out.appending(path: "Iter.store-wal"))
        try write("junk", to: out.appending(path: "Iter.store-shm.migrating-DEAD"))

        let result = try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home)
        #expect(Set(result.storeItems) == ["Iter.store", "Iter.store-wal"])
        #expect(text(out.appending(path: "Iter.store-wal")) == "wal-new")
        #expect(text(out.appending(path: "Iter.store")) == "store")
    }

    /// A source store that cannot be read leaves no store at the new location (so the next launch tries again).
    @Test func failedStoreCopyLeavesNothingBehind() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let old = container(home)
        let source = old.appending(path: "default.store")
        try write("store", to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        #expect(throws: (any Error).self) { try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
        let out = StoreLocation.directStoreURL(home: home).deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
        #expect(try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home).storeItems == ["Iter.store"])
    }
}
