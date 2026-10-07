import Foundation
import Testing
import SwiftData
import IterCore
@testable import IterData

@MainActor
@Suite struct StoreLocationTests {
    let id = "com.test"

    /// A fake home with a sandbox container holding a real store with one trip and one stop.
    final class Home {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appending(path: "iter-home-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }
        func container(_ id: String) -> URL { url.appending(path: "Library/Containers/\(id)/Data/Library/Application Support", directoryHint: .isDirectory) }
    }

    @MainActor
    func makeSandboxStore(_ home: Home) throws {
        let dir = home.container(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = IterStore(container: try IterSchema.makeContainer(url: dir.appending(path: "default.store")))
        let trip = store.createTrip(name: "Canyon Country", startDay: LocalDay(year: 2026, month: 10, day: 10), dayCount: 2)
        store.addStop(CuratedSpots.spot(id: "mesa-arch")!, to: trip, day: 0)
    }

    func read(_ url: URL) throws -> (trips: [String], stops: Int) {
        let store = IterStore(container: try IterSchema.makeContainer(url: url))
        let trips = store.trips()
        return (trips.map(\.name), trips.reduce(0) { $0 + ($1.stops ?? []).count })
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func sandboxDetection() {
        #expect(StoreLocation.isSandboxed(environment: ["APP_SANDBOX_CONTAINER_ID": "com.dwjames.iter"]))
        #expect(!StoreLocation.isSandboxed(environment: [:]))
    }

    @Test func directURLIsNotTheSharedDefault() {
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)
        #expect(StoreLocation.directStoreURL(home: home).path == "/Users/x/Library/Application Support/Iter/Iter.store")
    }

    @Test func migratesStoreAndLeavesContainerUntouched() throws {
        let home = try Home()
        try makeSandboxStore(home)
        let before = try FileManager.default.contentsOfDirectory(atPath: home.container(id).path).sorted()
        let result = try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url)
        #expect(result.storeItems.contains("Iter.store"))
        #expect(result.didMigrate)
        let data = try read(StoreLocation.directStoreURL(home: home.url))
        #expect(data.trips == ["Canyon Country"])
        #expect(data.stops == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.container(id).path).sorted() == before)
        // No temporary leftovers.
        let names = try FileManager.default.contentsOfDirectory(atPath: StoreLocation.directStoreURL(home: home.url).deletingLastPathComponent().path)
        #expect(!names.contains { $0.contains(".migrating-") })
    }

    @Test func secondRunIsNoOp() throws {
        let home = try Home()
        try makeSandboxStore(home)
        #expect(try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url).didMigrate)
        #expect(try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url) == StoreLocation.MigrationResult())
    }

    @Test func existingDestinationIsNotTouched() throws {
        let home = try Home()
        try makeSandboxStore(home)
        let destination = StoreLocation.directStoreURL(home: home.url)
        try write("mine", to: destination)
        #expect(try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url) == StoreLocation.MigrationResult())
        #expect(try String(contentsOf: destination, encoding: .utf8) == "mine")
    }

    @Test func nothingToMigrate() throws {
        let home = try Home()
        #expect(try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url) == StoreLocation.MigrationResult())
        #expect(!FileManager.default.fileExists(atPath: StoreLocation.directStoreURL(home: home.url).deletingLastPathComponent().path))
    }

    @Test func sideFilesAndSupportFolderAreRenamed() throws {
        let home = try Home()
        let dir = home.container(id)
        try write("s", to: dir.appending(path: "default.store"))
        try write("w", to: dir.appending(path: "default.store-wal"))
        try write("m", to: dir.appending(path: "default.store-shm"))
        try write("x", to: dir.appending(path: ".default_SUPPORT/_EXTERNAL_DATA/blob"))
        let result = try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url)
        #expect(Set(result.storeItems) == ["Iter.store", "Iter.store-wal", "Iter.store-shm", ".Iter_SUPPORT"])
        let out = StoreLocation.directStoreURL(home: home.url).deletingLastPathComponent()
        #expect(try String(contentsOf: out.appending(path: "Iter.store-wal"), encoding: .utf8) == "w")
        #expect(FileManager.default.fileExists(atPath: out.appending(path: ".Iter_SUPPORT/_EXTERNAL_DATA/blob").path))
        #expect(!FileManager.default.fileExists(atPath: out.appending(path: "default.store").path))
    }

    @Test func subtreeMergeDoesNotOverwrite() throws {
        let home = try Home()
        try makeSandboxStore(home)
        let old = home.container(id).appending(path: "Iter")
        try write("old-a", to: old.appending(path: "OfflinePacks/a.pack"))
        try write("old-b", to: old.appending(path: "OfflinePacks/b.pack"))
        try write("old-f", to: old.appending(path: "ForecastCache/f.json"))
        let newRoot = StoreLocation.directStoreURL(home: home.url).deletingLastPathComponent()
        try write("new-a", to: newRoot.appending(path: "OfflinePacks/a.pack"))
        let result = try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: id, home: home.url)
        #expect(Set(result.supportItems) == ["OfflinePacks/b.pack", "ForecastCache"])
        #expect(try String(contentsOf: newRoot.appending(path: "OfflinePacks/a.pack"), encoding: .utf8) == "new-a")
        #expect(try String(contentsOf: newRoot.appending(path: "OfflinePacks/b.pack"), encoding: .utf8) == "old-b")
        #expect(try String(contentsOf: newRoot.appending(path: "ForecastCache/f.json"), encoding: .utf8) == "old-f")
        #expect(try String(contentsOf: old.appending(path: "OfflinePacks/a.pack"), encoding: .utf8) == "old-a")
    }

    @Test func copiesPreferencesOnceWithoutOverwriting() throws {
        let home = try Home()
        let prefs = home.url.appending(path: "Library/Containers/\(id)/Data/Library/Preferences", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let old: NSDictionary = ["IterTemperatureUnit": "celsius", "IterKept": "old", "Count": 3]
        #expect(old.write(to: prefs.appending(path: "\(id).plist"), atomically: true))

        let suite = "iter.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("new", forKey: "IterKept")

        let copied = StoreLocation.migratePreferencesFromSandboxContainer(bundleIdentifier: id, home: home.url, defaults: defaults, domain: suite)
        #expect(copied == 2)
        #expect(defaults.string(forKey: "IterTemperatureUnit") == "celsius")
        #expect(defaults.integer(forKey: "Count") == 3)
        #expect(defaults.string(forKey: "IterKept") == "new")
        #expect(defaults.bool(forKey: StoreLocation.preferencesMigratedKey))

        defaults.removeObject(forKey: "Count")
        #expect(StoreLocation.migratePreferencesFromSandboxContainer(bundleIdentifier: id, home: home.url, defaults: defaults, domain: suite) == 0)
        #expect(defaults.object(forKey: "Count") == nil)
    }

    @Test func preferencesWithNoContainerJustSetTheMarker() throws {
        let home = try Home()
        let suite = "iter.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(StoreLocation.migratePreferencesFromSandboxContainer(bundleIdentifier: id, home: home.url, defaults: defaults, domain: suite) == 0)
        #expect(defaults.bool(forKey: StoreLocation.preferencesMigratedKey))
    }
}
