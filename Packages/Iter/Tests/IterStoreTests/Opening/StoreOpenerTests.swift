import Foundation
import SwiftData
import Testing
import IterModel
@testable import IterStore

/// Backup before the first V5 open, the injected failures, and the recovered-store fallback.
@Suite struct StoreOpenerTests {
    let fixedNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

    struct Harness {
        var dir: URL            // holds the store, the backups and the scratch
        var storeURL: URL
        var backups: URL
        var scratch: URL
        var originalHashes: [String: String?]
        var storeName: String

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    func harness(_ fixture: String, storeName: String = "Iter.store") throws -> Harness {
        let dir = try TestSupport.copyFixtureStore(fixture, storeName: storeName)
        let scratch = dir.appending(path: "scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return Harness(dir: dir, storeURL: dir.appending(path: storeName), backups: dir.appending(path: "Backups", directoryHint: .isDirectory),
                       scratch: scratch, originalHashes: try TestSupport.storeHashes(dir: dir, storeName: storeName), storeName: storeName)
    }

    func opener(_ h: Harness, files: any StoreFileOperations = DefaultStoreFileOperations(),
                containers: StoreContainerFactory = .live,
                exportTrip: (@Sendable (Trip, Date) throws -> Data)? = nil) -> StoreOpener {
        let now = fixedNow
        if let exportTrip {
            return StoreOpener(storeURL: h.storeURL, backupsDirectory: h.backups, clock: { now }, files: files,
                               containers: containers, scratchDirectory: h.scratch, exportTrip: exportTrip)
        }
        return StoreOpener(storeURL: h.storeURL, backupsDirectory: h.backups, clock: { now }, files: files,
                           containers: containers, scratchDirectory: h.scratch)
    }

    func backupFolders(_ h: Harness) -> [String] {
        TestSupport.names(in: h.backups).filter { $0.hasPrefix("pre-v5-") }
    }

    func plans(of container: ModelContainer) throws -> [UUID: ITERFileV1.TripDTO] {
        let context = ModelContext(container)
        let trips = try context.fetch(FetchDescriptor<TripRecord>()).map { $0.value() }
        return Dictionary(uniqueKeysWithValues: trips.map { ($0.id, ITERFileV1(trip: $0, exportedAt: Date(timeIntervalSince1970: 0)).plan) })
    }

    // MARK: - Backup

    @Test(arguments: ExpectedStore.fixtureNames)
    func backupCopiesFilesAndExportsEveryTrip(fixture: String) throws {
        let h = try harness(fixture)
        defer { h.cleanup() }
        let expected = try ExpectedStore.load(fixture)
        let o = opener(h)
        let folder: URL
        do {
            let outcome = try o.open()
            folder = try #require(outcome.backupFolder)
            #expect(outcome.recovered == nil)
        }
        // Exactly one backup folder, named from the clock, with no marker left.
        #expect(backupFolders(h) == [StoreBackup.folderName(for: fixedNow)])
        #expect(folder.lastPathComponent == StoreBackup.folderName(for: fixedNow))
        let names = TestSupport.names(in: folder)
        #expect(!names.contains(".migration-pending"))
        #expect(!names.contains { $0.contains(".copying-") || $0.contains(".writing-") })
        // The raw files are byte-identical to the originals before the open.
        #expect(try TestSupport.storeHashes(dir: folder) == h.originalHashes)
        // One .iter per trip, each decoding to the expected plan.
        let iterFiles = names.filter { $0.hasSuffix(".iter") }
        #expect(iterFiles.count == expected.trips.count)
        var decoded: [UUID: ITERFileV1.TripDTO] = [:]
        for name in iterFiles {
            let file = try ITERFileV1.decode(Data(contentsOf: folder.appending(path: name)))
            decoded[file.plan.id] = file.plan
        }
        for trip in expected.trips {
            #expect(decoded[trip.id] == trip.plan, "trip \(trip.name)")
            #expect(iterFiles.contains { $0.hasPrefix(String(ITERFileInfo.suggestedFileName(forTripNamed: trip.name).dropLast(5))) })
        }
        // backup.json
        let info = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "backup.json"))) as? [String: Any]
        let counts = try #require(info?["counts"] as? [String: Int])
        #expect(counts == ["trips": expected.trips.count, "stops": expected.stops.count,
                           "places": expected.places.count, "folders": expected.folders.count])
        #expect(info?["schemaVersionFound"] as? String == expected.writtenSchemaVersion)
        #expect(Set(info?["tripFiles"] as? [String] ?? []) == Set(iterFiles))
        // The scratch copy is gone.
        #expect(TestSupport.names(in: h.scratch).isEmpty)
    }

    @Test func reopeningAV5StoreMakesNoSecondBackup() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        let first = try opener(h).open()
        #expect(first.backupFolder != nil)
        let second = try opener(h).open()
        #expect(second.backupFolder == nil)
        #expect(backupFolders(h).count == 1)
        #expect(try plans(of: second.container).count == 4)
    }

    @Test func twoBackupsInTheSameSecondDoNotClash() throws {
        let h = try harness("v1")
        defer { h.cleanup() }
        // A leftover folder with the same name (a finished backup) must be kept, not overwritten.
        let existing = h.backups.appending(path: StoreBackup.folderName(for: fixedNow))
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: existing.appending(path: "keep.txt"))
        let outcome = try opener(h).open()
        #expect(outcome.backupFolder?.lastPathComponent == StoreBackup.folderName(for: fixedNow) + "-2")
        #expect(try String(contentsOf: existing.appending(path: "keep.txt"), encoding: .utf8) == "keep")
    }

    @Test func staleUnfinishedBackupIsRemoved() throws {
        let h = try harness("v1")
        defer { h.cleanup() }
        let stale = h.backups.appending(path: "pre-v5-2020-01-01-000000")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data().write(to: stale.appending(path: ".migration-pending"))
        _ = try opener(h).open()
        #expect(backupFolders(h) == [StoreBackup.folderName(for: fixedNow)])
    }

    @Test func iOSNamesTheStoreDefaultStore() throws {
        let h = try harness("v4-realistic", storeName: "default.store")
        defer { h.cleanup() }
        let folder = try #require(try opener(h).open().backupFolder)
        let names = TestSupport.names(in: folder)
        #expect(Set(["default.store", "default.store-wal", "default.store-shm"]).isSubset(of: Set(names)))
        #expect(try TestSupport.storeHashes(dir: folder, storeName: "default.store") == h.originalHashes)
    }

    @Test func supportFolderIsBackedUpToo() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        let support = h.dir.appending(path: ".Iter_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("blob".utf8).write(to: support.appending(path: "x"))
        let folder = try #require(try opener(h).open().backupFolder)
        #expect(try String(contentsOf: folder.appending(path: ".Iter_SUPPORT/_EXTERNAL_DATA/x"), encoding: .utf8) == "blob")
    }

    // MARK: - Fresh and already V5

    @Test func freshInstallCreatesAV5StoreWithoutABackup() throws {
        let dir = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter/Iter.store")
        let backups = dir.appending(path: "Iter/Backups")
        let outcome = try StoreOpener(storeURL: url, backupsDirectory: backups, scratchDirectory: dir).open()
        #expect(outcome.backupFolder == nil && outcome.recovered == nil && outcome.activeURL == url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: backups.path))
        #expect(try ModelContext(outcome.container).fetchCount(FetchDescriptor<TripRecord>()) == 0)
        let scratch = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(try StoreSchemaDetector.detectOnCopy(storeURL: url, scratchDirectory: scratch) == .v5)
    }

    @Test func alreadyV5MakesNoBackup() throws {
        let dir = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        do {
            let container = try IterStoreSchema.makeContainer(url: url)
            let context = ModelContext(container)
            let trip = TripRecord()
            trip.name = "Already V5"
            context.insert(trip)
            try context.save()
        }
        let backups = dir.appending(path: "Backups")
        let outcome = try StoreOpener(storeURL: url, backupsDirectory: backups, scratchDirectory: dir).open()
        #expect(outcome.backupFolder == nil)
        #expect(!FileManager.default.fileExists(atPath: backups.path))
        #expect(try ModelContext(outcome.container).fetch(FetchDescriptor<TripRecord>()).map(\.name) == ["Already V5"])
    }

    @Test func aStoreThatIsNotAnIterStoreIsLeftAlone() throws {
        let dir = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        try Data("not a database".utf8).write(to: url)
        let before = try TestSupport.sha256(url)
        #expect(throws: StoreOpenError.self) {
            try StoreOpener(storeURL: url, backupsDirectory: dir.appending(path: "Backups"), scratchDirectory: dir).open()
        }
        #expect(try TestSupport.sha256(url) == before)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "Backups").path))
    }

    @Test func foldersAreFlattenedOnEveryOpen() throws {
        let dir = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        let ids: (UUID, UUID)
        do {
            let context = ModelContext(try IterStoreSchema.makeContainer(url: url))
            let root = FolderRecord(), kid = FolderRecord()
            root.name = "Root"; kid.name = "Kid"
            context.insert(root); context.insert(kid)
            kid.parent = root
            ids = (root.id, kid.id)
            try context.save()
        }
        let outcome = try StoreOpener(storeURL: url, backupsDirectory: dir.appending(path: "Backups"), scratchDirectory: dir).open()
        let folders = try ModelContext(outcome.container).fetch(FetchDescriptor<FolderRecord>())
        #expect(folders.allSatisfy { $0.parent == nil })
        #expect(Set(folders.map(\.id)) == [ids.0, ids.1])
        #expect(folders.first { $0.id == ids.0 }?.sortOrder == 0 && folders.first { $0.id == ids.1 }?.sortOrder == 1)
    }

    // MARK: - Injected failures

    /// The original store files are byte-identical, nothing partial is left, and the store was not opened.
    func assertUntouched(_ h: Harness, error: any Error) throws {
        guard case StoreOpenError.backupFailed = error else {
            Issue.record("expected backupFailed, got \(error)")
            return
        }
        #expect(try TestSupport.storeHashes(dir: h.dir, storeName: h.storeName) == h.originalHashes)
        #expect(backupFolders(h).isEmpty)
        let backupsContents = FileManager.default.fileExists(atPath: h.backups.path) ? TestSupport.names(in: h.backups) : []
        #expect(backupsContents.isEmpty)
        #expect(TestSupport.names(in: h.scratch).isEmpty)
        #expect(!TestSupport.names(in: h.dir).contains { $0.contains("recovered") || $0 == "store-manifest.json" })
    }

    @Test(arguments: ["v1", "v4-realistic"])
    func copyFailingMidBackupLeavesTheStoreUntouched(fixture: String) throws {
        for failAt in [1, 2, 3] {   // the store, the -wal, the -shm
            let h = try harness(fixture)
            defer { h.cleanup() }
            let files = FlakyFileOperations(failFrom: [.copy: failAt])
            do {
                _ = try opener(h, files: files).open()
                Issue.record("open should have failed")
            } catch {
                try assertUntouched(h, error: error)
            }
        }
    }

    @Test func copyFailingForTheScratchCopyLeavesTheStoreUntouched() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        // Copies 1 to 3 are the raw files; 4 to 6 are the scratch copy.
        let files = FlakyFileOperations(failFrom: [.copy: 5])
        do { _ = try opener(h, files: files).open(); Issue.record("open should have failed") } catch { try assertUntouched(h, error: error) }
    }

    @Test func renameFailingLeavesTheStoreUntouched() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        let files = FlakyFileOperations(failFrom: [.move: 2])
        do { _ = try opener(h, files: files).open(); Issue.record("open should have failed") } catch { try assertUntouched(h, error: error) }
    }

    @Test func removingTheMarkerFailingLeavesTheStoreUntouched() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        // The marker is the last thing removed; the scratch copy is removed just before it.
        let files = FlakyFileOperations(failFrom: [.remove: 2])
        do { _ = try opener(h, files: files).open(); Issue.record("open should have failed") } catch { try assertUntouched(h, error: error) }
    }

    @Test func exportFailingLeavesTheStoreUntouched() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        let exported = Counter()
        let export: @Sendable (Trip, Date) throws -> Data = { trip, date in
            if exported.next() == 2 { throw InjectedFailure(label: "export") }
            return try ITERFileV1(trip: trip, exportedAt: date).encoded()
        }
        do { _ = try opener(h, exportTrip: export).open(); Issue.record("open should have failed") } catch { try assertUntouched(h, error: error) }
        #expect(exported.value == 2)
    }

    @Test func writeFailingForAnIterFileLeavesTheStoreUntouched() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        // Writes: the marker, then one per trip. Fail the third.
        let files = FlakyFileOperations(failFrom: [.write: 3])
        do { _ = try opener(h, files: files).open(); Issue.record("open should have failed") } catch { try assertUntouched(h, error: error) }
    }

    @Test func scratchOpenFailingLeavesTheStoreUntouched() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        do { _ = try opener(h, containers: .failingScratch).open(); Issue.record("open should have failed") } catch { try assertUntouched(h, error: error) }
    }

    @Test func aFailedBackupCanBeRetried() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        _ = try? opener(h, containers: .failingScratch).open()
        let outcome = try opener(h).open()
        #expect(outcome.backupFolder != nil)
        #expect(try plans(of: outcome.container).count == 4)
    }

    // MARK: - V5 open fails: recovered store

    @Test(arguments: [("v4-realistic", "Iter.store"), ("v1", "Iter.store"), ("v3", "default.store")])
    func failedV5OpenFallsBackToARecoveredStore(fixture: String, storeName: String) throws {
        let h = try harness(fixture, storeName: storeName)
        defer { h.cleanup() }
        let expected = try ExpectedStore.load(fixture)
        let failing = StoreContainerFactory.failingCurrent(for: h.storeURL)
        let recoveredURL: URL, backupFolder: URL
        do {
            let outcome = try opener(h, containers: failing).open()
            let info = try #require(outcome.recovered)
            #expect(info.needsNotice)
            #expect(info.originalURL == h.storeURL)
            #expect(info.skippedFiles.isEmpty)
            recoveredURL = outcome.activeURL
            backupFolder = try #require(outcome.backupFolder)
            #expect(info.backupFolder == backupFolder && info.activeURL == recoveredURL)
            let base = storeName == "Iter.store" ? "Iter" : "default"
            #expect(recoveredURL.lastPathComponent == "\(base)-recovered-\(StoreBackup.timestamp(fixedNow)).store")
            #expect(recoveredURL.deletingLastPathComponent() == h.dir)
            // The recovered store holds the fixture's trips: same plans.
            let got = try plans(of: outcome.container)
            #expect(Set(got.keys) == Set(expected.trips.map(\.id)))
            for trip in expected.trips { #expect(got[trip.id] == trip.plan, "trip \(trip.name)") }
        }
        // The original is untouched, byte for byte (the V5 open was never attempted for real).
        #expect(try TestSupport.storeHashes(dir: h.dir, storeName: storeName) == h.originalHashes)
        // The manifest.
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: h.dir.appending(path: "store-manifest.json"))) as? [String: Any]
        #expect(manifest?["activeFileName"] as? String == recoveredURL.lastPathComponent)
        #expect(manifest?["originalFileName"] as? String == storeName)
        #expect(manifest?["backupFolder"] as? String == backupFolder.path)
        #expect(manifest?["noticeShown"] as? Bool == false)

        // A second open uses the recovered store and does not import again.
        let second = try opener(h, containers: failing).open()
        #expect(second.activeURL == recoveredURL)
        #expect(second.backupFolder == backupFolder)
        #expect(try plans(of: second.container).count == expected.trips.count)
        #expect(try ModelContext(second.container).fetchCount(FetchDescriptor<StopRecord>()) == expected.stops.filter { $0.placeID != nil }.count)
        #expect(backupFolders(h).count == 1)
        #expect(try TestSupport.storeHashes(dir: h.dir, storeName: storeName) == h.originalHashes)
        #expect(second.recovered?.needsNotice == true)

        // The notice is one-time.
        try opener(h, containers: failing).markRecoveryNoticeShown()
        let third = try opener(h, containers: failing).open()
        #expect(third.recovered?.needsNotice == false)
        #expect(third.activeURL == recoveredURL)
    }

    @Test func failedOpenWithNoBackupToRecoverFromThrowsAndTouchesNothing() throws {
        let dir = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        do { _ = try IterStoreSchema.makeContainer(url: url) }
        let before = try TestSupport.storeHashes(dir: dir)
        let o = StoreOpener(storeURL: url, backupsDirectory: dir.appending(path: "Backups"), containers: .failingCurrent(for: url),
                            scratchDirectory: dir)
        do { _ = try o.open(); Issue.record("should throw") } catch StoreOpenError.openFailed {} catch { Issue.record("wrong error \(error)") }
        #expect(try TestSupport.storeHashes(dir: dir) == before)
        #expect(!TestSupport.names(in: dir).contains { $0.contains("recovered") })
    }

    @Test func recoveryFailingLeavesNoRecoveredStoreBehind() throws {
        let h = try harness("v4-realistic")
        defer { h.cleanup() }
        // Both the original and the recovered open fail.
        let allFail = StoreContainerFactory(openCurrent: { _ in throw InjectedFailure(label: "any open") },
                                            openLegacyV4: StoreContainerFactory.live.openLegacyV4)
        do { _ = try opener(h, containers: allFail).open(); Issue.record("should throw") } catch StoreOpenError.recoveryFailed {} catch { Issue.record("wrong error \(error)") }
        #expect(try TestSupport.storeHashes(dir: h.dir) == h.originalHashes)
        #expect(!TestSupport.names(in: h.dir).contains { $0.contains("recovered") || $0 == "store-manifest.json" })
        #expect(backupFolders(h).count == 1)   // the backup is kept: it is the user's data
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// A store whose changes are still in the `-wal` (the way the owner's store can be at quit time) is backed up whole.
@Suite struct LiveWALBackupTests {
    @Test func storeWithANonEmptyWALIsBackedUpAndExported() throws {
        let live = try TestSupport.makeTempDirectory("iter-live")
        let dir = try TestSupport.makeTempDirectory("iter-wal")
        defer { try? FileManager.default.removeItem(at: live); try? FileManager.default.removeItem(at: dir) }
        let liveURL = live.appending(path: "Iter.store")
        let schema = Schema(versionedSchema: IterSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: liveURL, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let place = IterSchemaV4.PlaceRecord()
        place.name = "In the WAL"
        place.timeZoneIdentifier = "America/Denver"
        let trip = IterSchemaV4.TripRecord()
        trip.name = "Unflushed trip"
        trip.startDayISO = "2026-10-10"
        trip.dayCount = 1
        let stop = IterSchemaV4.StopRecord()
        context.insert(place); context.insert(trip); context.insert(stop)
        stop.trip = trip
        stop.place = place
        try context.save()
        // Copy while the container is open: the changes live in the -wal.
        for suffix in ["", "-wal", "-shm"] {
            let from = liveURL.path + suffix
            if FileManager.default.fileExists(atPath: from) { try FileManager.default.copyItem(atPath: from, toPath: dir.appending(path: "Iter.store" + suffix).path) }
        }
        let walSize = (try? FileManager.default.attributesOfItem(atPath: dir.appending(path: "Iter.store-wal").path)[.size] as? Int) ?? 0
        #expect(walSize > 0)
        let before = try TestSupport.storeHashes(dir: dir)

        let url = dir.appending(path: "Iter.store")
        let outcome = try StoreOpener(storeURL: url, backupsDirectory: dir.appending(path: "Backups"), scratchDirectory: dir).open()
        let folder = try #require(outcome.backupFolder)
        #expect(try TestSupport.storeHashes(dir: folder) == before)
        let exported = TestSupport.names(in: folder).filter { $0.hasSuffix(".iter") }
        #expect(exported == ["Unflushed trip.iter"])
        let file = try ITERFileV1.decode(Data(contentsOf: folder.appending(path: exported[0])))
        #expect(file.plan.stops.count == 1 && file.plan.stops[0].spot.name == "In the WAL")
        #expect(try ModelContext(outcome.container).fetch(FetchDescriptor<TripRecord>()).map(\.name) == ["Unflushed trip"])
        withExtendedLifetime(container) {}
    }
}
