import Foundation
import CoreData
import SwiftData
import Testing
import IterModel
@testable import IterStore

/// The cut-over dry run on a store this repository has never seen (the owner's). Skipped unless the environment names one.
///
///     ITER_DRYRUN_STORE_DIR   a folder holding Iter.store (+ -wal, -shm). Only ever COPIED.
///     ITER_DRYRUN_EXPECTED    the old code's `<out>.expected.json` from `IterFixtureGen --dump` (an `.as-written.json` and
///                             `.schema.json` next to it are used for the "before" counts and the raw version identifiers)
///     ITER_DRYRUN_OUT         an output folder: work-1/, work-2/, migrated/Iter/, after.json, report.md, report.json
///
/// The report holds counts, ids, trip names and field names. `notes`, `blurb`, `note` and `driveNote` values are never
/// written; a difference there reads "differs (len a -> b)".
@Suite(.enabled(if: DryRunEnvironment.isEnabled, "set ITER_DRYRUN_STORE_DIR, ITER_DRYRUN_EXPECTED and ITER_DRYRUN_OUT to run"))
@MainActor
struct RealStoreDryRunTests {
    @Test func dryRunOnACopyOfTheStore() throws {
        let runner = try DryRunner()
        defer { runner.writeReport() }
        try runner.run()
        let report = runner.report
        #expect(report.problems.isEmpty, Comment(rawValue: report.problems.joined(separator: "\n")))
        #expect(report.inputUnchanged)
    }
}

enum DryRunEnvironment {
    static let environment = ProcessInfo.processInfo.environment
    static var isEnabled: Bool { environment["ITER_DRYRUN_STORE_DIR"] != nil }
}

struct DryRunSetupError: Error, CustomStringConvertible { var description: String }

@MainActor
final class DryRunner {
    let input: URL
    let expectedURL: URL
    let out: URL
    let expected: ExpectedStore
    var report = DryRunReport()
    private let fm = FileManager.default
    private let epoch = Date(timeIntervalSince1970: 0)

    init() throws {
        let env = DryRunEnvironment.environment
        guard let dir = env["ITER_DRYRUN_STORE_DIR"], let exp = env["ITER_DRYRUN_EXPECTED"], let out = env["ITER_DRYRUN_OUT"] else {
            throw DryRunSetupError(description: "ITER_DRYRUN_STORE_DIR, ITER_DRYRUN_EXPECTED and ITER_DRYRUN_OUT must all be set")
        }
        input = URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL
        expectedURL = URL(fileURLWithPath: exp)
        self.out = URL(fileURLWithPath: out, isDirectory: true).standardizedFileURL
        guard !self.out.path.hasPrefix(input.path + "/"), self.out != input else {
            throw DryRunSetupError(description: "ITER_DRYRUN_OUT must not be inside the store folder")
        }
        guard fm.fileExists(atPath: input.appending(path: "Iter.store").path) else { throw DryRunSetupError(description: "no Iter.store in ITER_DRYRUN_STORE_DIR") }
        expected = try ExpectedStore.load(contentsOf: expectedURL)
    }

    func writeReport() {
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: out.appending(path: "report.json"))
        try? Data(report.markdown().utf8).write(to: out.appending(path: "report.md"))
        // Counts only on stdout.
        print("dry run \(report.passed ? "PASS" : "FAIL"): \(report.comparison?.differences.count ?? -1) difference(s), \(report.problems.count) problem(s); report in \(out.path)")
    }

    // MARK: - Helpers

    private func problem(_ text: String) { report.problems.append(text) }

    private func counts(of dump: ExpectedStore) -> DryRunReport.Counts {
        .init(folders: dump.folders.count, places: dump.places.count, trips: dump.trips.count, stops: dump.stops.count)
    }

    private func info(_ r: ComparisonResult) -> DryRunReport.ComparisonInfo {
        .init(checks: r.checkCount, differences: r.differences, skipped: r.skipped)
    }

    private func sha(_ url: URL) -> String? { fm.fileExists(atPath: url.path) ? try? TestSupport.sha256(url) : nil }

    private static let storeFiles = ["Iter.store", "Iter.store-wal", "Iter.store-shm"]

    /// A copy of the store files (and the external-data folder if any) in `dest`. Nothing else from the input folder.
    private func copyStore(to dest: URL) throws {
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in Self.storeFiles + [".Iter_SUPPORT"] {
            let from = input.appending(path: name)
            if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: dest.appending(path: name)) }
        }
    }

    private func fileHashes(_ dir: URL) -> [String: String?] { Dictionary(uniqueKeysWithValues: Self.storeFiles.map { ($0, sha(dir.appending(path: $0))) }) }

    private func sibling(_ suffix: String) -> URL? {
        let path = expectedURL.path
        guard path.hasSuffix(".expected.json") else { return nil }
        let url = URL(fileURLWithPath: String(path.dropLast(".expected.json".count)) + suffix)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - The run

    func run() throws {
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        for stale in ["work-1", "work-2", "migrated"] { try? fm.removeItem(at: out.appending(path: stale)) }

        // 0. The input: hashes before; the old code's version of events.
        report.inputFolderItems = ((try? fm.contentsOfDirectory(atPath: input.path)) ?? []).sorted()
        let before = fileHashes(input)
        report.inputFiles = Self.storeFiles.map { name in
            let url = input.appending(path: name)
            return .init(name: name, bytes: (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil, sha256Before: before[name] ?? nil, sha256After: nil)
        }
        report.oldCodeWrittenSchema = expected.writtenSchemaVersion
        report.countsExpected = counts(of: expected)
        if let url = sibling(".as-written.json"), let written = try? ExpectedStore.load(contentsOf: url) {
            report.countsBefore = counts(of: written)
            report.countsBeforeSource = "old-code as-written dump"
        }
        if let url = sibling(".schema.json"), let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            report.rawVersionIdentifiers = (json["NSStoreModelVersionIdentifiers"] as? [String]) ?? []
        }
        if expected.trips.contains(where: { $0.plan == nil }) { problem("the expected dump has trips without a plan (was it made by IterFixtureGen --dump?)") }

        // Copy 1 (the migration) and copy 2 (the failure path), made before anything is opened.
        let work1 = out.appending(path: "work-1/Iter", directoryHint: .isDirectory)
        let work2 = out.appending(path: "work-2/Iter", directoryHint: .isDirectory)
        try copyStore(to: work1)
        try copyStore(to: work2)
        if report.rawVersionIdentifiers.isEmpty { report.rawVersionIdentifiers = try rawIdentifiers(of: work1) }

        // The schema, from the new detector on a scratch copy.
        let scratch = try TestSupport.makeTempDirectory("iter-dryrun-scratch")
        defer { try? fm.removeItem(at: scratch) }
        let detected = try StoreSchemaDetector.detectOnCopy(storeURL: work1.appending(path: "Iter.store"), scratchDirectory: scratch)
        report.detectedSchema = detected?.versionString
        if detected == nil { problem("StoreSchemaDetector does not recognise the store's schema") }
        if let detected, detected.versionString != expected.writtenSchemaVersion {
            problem("detector says \(detected.versionString), the old-code dump says \(expected.writtenSchemaVersion)")
        }

        try migrate(work1, detected: detected)
        if let detected, detected < .v5 { try failurePath(work2) } else {
            report.failurePath = .init(note: "skipped: the store is already V5, so there is no backup to recover from")
        }

        // 7. Copy 1 stays for the lead's renders.
        let migrated = out.appending(path: "migrated/Iter", directoryHint: .isDirectory)
        try fm.createDirectory(at: migrated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: work1, to: migrated)
        report.migratedFolder = migrated.path

        // 1 (again). The input must be byte-identical.
        let after = fileHashes(input)
        for i in report.inputFiles.indices { report.inputFiles[i].sha256After = after[report.inputFiles[i].name] ?? nil }
        report.inputUnchanged = (before == after)
        if !report.inputUnchanged { problem("the input store files changed during the run") }
        report.inputFolderItems = ((try? fm.contentsOfDirectory(atPath: input.path)) ?? []).sorted()
    }

    /// The version identifiers in the store's metadata, read on a scratch copy.
    private func rawIdentifiers(of dir: URL) throws -> [String] {
        let scratch = try TestSupport.makeTempDirectory("iter-dryrun-meta")
        defer { try? fm.removeItem(at: scratch) }
        for name in Self.storeFiles where fm.fileExists(atPath: dir.appending(path: name).path) {
            try fm.copyItem(at: dir.appending(path: name), to: scratch.appending(path: name))
        }
        let md = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: scratch.appending(path: "Iter.store"), options: nil)
        return ((md[NSStoreModelVersionIdentifiersKey] as? [Any])?.compactMap { $0 as? String } ?? []).sorted()
    }

    // MARK: - Copy 1: open like the Mac app, dump, compare, check the backup

    private func migrate(_ dir: URL, detected: StoreSchemaVersion?) throws {
        let storeURL = dir.appending(path: "Iter.store")
        var backupFolder: URL?
        do {
            // As StoreBuilder does for a real store: backups next to the store, the same call, a LibraryStore on the container.
            let opener = StoreOpener(storeURL: storeURL, backupsDirectory: dir.appending(path: "Backups", directoryHint: .isDirectory),
                                     clock: { Date() })
            let outcome = try opener.open()
            let library = LibraryStore(container: outcome.container, clock: { Date() })
            backupFolder = outcome.backupFolder
            report.open = .init(activeURL: outcome.activeURL.path, recovered: outcome.recovered != nil,
                                backupFolder: outcome.backupFolder?.path, storeIsOriginalURL: outcome.activeURL == storeURL)
            if outcome.recovered != nil { problem("the migration open fell back to recovery") }
            if outcome.activeURL != storeURL { problem("the open did not use the requested store file") }

            // After-picture by raw fetches of the V5 records, in the fixtures' shape.
            let raw = try ExpectedStore.read(from: ModelContext(outcome.container), fixture: "dry-run-after",
                                             writtenSchemaVersion: "5.0.0", flattenedFolderIDs: expected.flattenedFolderIDs)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(raw).write(to: out.appending(path: "after.json"))
            report.countsAfter = counts(of: raw)

            let result = try StoreComparison.compare(context: ModelContext(outcome.container), expected: expected)
            report.comparison = info(result)
            if !result.differences.isEmpty { problem("\(result.differences.count) difference(s) between the new store and the old code's dump") }
            let libraryResult = try StoreComparison.compareLibrary(library, expected: expected)
            report.libraryComparison = info(libraryResult)
            if !libraryResult.differences.isEmpty { problem("\(libraryResult.differences.count) difference(s) through LibraryStore") }
            if report.countsExpected != report.countsAfter { problem("counts after (\(report.countsAfter?.text ?? "?")) differ from expected") }
            library.flush()
        }   // container and library released here, before anything is copied or hashed
        try checkBackup(backupFolder, detected: detected)
    }

    private func checkBackup(_ folder: URL?, detected: StoreSchemaVersion?) throws {
        var b = DryRunReport.BackupInfo(folder: folder?.path)
        defer { report.backup = b }
        guard let folder else {
            b.note = detected == .v5 ? "no backup: the store was already V5" : "no backup folder was reported"
            if detected != .v5 { problem("an older store was opened but no backup folder was reported") }
            return
        }
        b.items = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        if b.items.contains(StoreBackup.pendingMarkerName) { problem("the backup still carries the .migration-pending marker") }

        // Raw files: byte-identical to the input.
        for name in Self.storeFiles {
            let original = sha(input.appending(path: name)), copy = sha(folder.appending(path: name))
            switch (original, copy) {
            case (nil, nil): b.rawFiles.append("`\(name)`: absent in both")
            case let (o?, c?) where o == c: b.rawFiles.append("`\(name)`: identical to the input (\(o.prefix(12))...)")
            default:
                b.rawFiles.append("`\(name)`: DIFFERENT from the input (backup \(copy.map { String($0.prefix(12)) } ?? "absent"), input \(original.map { String($0.prefix(12)) } ?? "absent"))")
                problem("backup copy of \(name) is not byte-identical to the input")
            }
        }

        // One `.iter` per trip, decoded with the v1 reader, against the expected plans.
        let iterNames = b.items.filter { $0.hasSuffix(".iter") }
        b.iterFiles = iterNames.count
        var rec = ComparisonRecorder()
        var seen = Set<UUID>()
        for name in iterNames {
            guard let data = try? Data(contentsOf: folder.appending(path: name)), let file = try? ITERFileV1.decode(data) else {
                problem("a backup .iter file does not decode with the v1 reader"); continue
            }
            guard let want = expected.trips.first(where: { $0.id == file.plan.id }), let plan = want.plan else {
                problem("a backup .iter file is for a trip that is not in the expected dump"); continue
            }
            if !seen.insert(file.plan.id).inserted { problem("two backup .iter files for the trip \(want.name)") }
            try StoreComparison.planDifferences(expected: plan, actual: file.plan, entity: "backupIter", id: want.id, label: want.name, into: &rec)
        }
        rec.check("backupIter", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "trip ids covered", expected: Set(expected.trips.map(\.id)), actual: seen)
        b.iterComparison = info(ComparisonResult(differences: rec.differences, skipped: rec.skipped, checkCount: rec.checkCount))
        if !rec.differences.isEmpty { problem("\(rec.differences.count) difference(s) in the backup .iter files") }

        // backup.json
        if let data = try? Data(contentsOf: folder.appending(path: BackupManifest.fileName)) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let m = try? decoder.decode(BackupManifest.self, from: data) {
                b.manifest = [
                    "schemaVersionFound": m.schemaVersionFound, "createdAt": ISO8601DateFormatter().string(from: m.createdAt),
                    "sourceFiles": m.sourceFiles.joined(separator: ", "),
                    "counts": "folders \(m.counts.folders), places \(m.counts.places), trips \(m.counts.trips), stops \(m.counts.stops)",
                    "tripFiles": "\(m.tripFiles.count)",
                ]
                if m.schemaVersionFound != expected.writtenSchemaVersion { problem("backup.json schemaVersionFound \(m.schemaVersionFound) differs from the old-code dump") }
                let c = DryRunReport.Counts(folders: m.counts.folders, places: m.counts.places, trips: m.counts.trips, stops: m.counts.stops)
                if c != report.countsExpected { problem("backup.json counts (\(c.text)) differ from the expected counts") }
                if m.tripFiles.count != expected.trips.count { problem("backup.json lists \(m.tripFiles.count) trip files, expected \(expected.trips.count)") }
            } else { problem("backup.json does not decode") }
        } else { problem("backup.json is missing") }
    }

    // MARK: - Copy 2: the V5 open fails

    private func failurePath(_ dir: URL) throws {
        var f = DryRunReport.FailureInfo()
        defer { report.failurePath = f }
        let storeURL = dir.appending(path: "Iter.store")
        let originalBefore = fileHashes(dir)
        let backups = dir.appending(path: "Backups", directoryHint: .isDirectory)

        var recoveredURL: URL?
        do {
            let opener = StoreOpener(storeURL: storeURL, backupsDirectory: backups, clock: { Date() },
                                     containers: .failingCurrent(for: storeURL))
            let outcome = try opener.open()
            recoveredURL = outcome.activeURL
            f.recoveredStore = outcome.activeURL.lastPathComponent
            f.recoveredNameDiffers = outcome.activeURL.lastPathComponent != storeURL.lastPathComponent
            if outcome.recovered == nil { problem("failure path: no recovery was reported") }
            if f.recoveredNameDiffers != true { problem("failure path: the recovered store has the original's name") }

            // The recovered store's trips against the expected plans.
            let context = ModelContext(outcome.container)
            let trips = try context.fetch(FetchDescriptor<TripRecord>())
            f.recoveredCounts = .init(folders: try context.fetchCount(FetchDescriptor<FolderRecord>()), places: try context.fetchCount(FetchDescriptor<PlaceRecord>()),
                                      trips: trips.count, stops: try context.fetchCount(FetchDescriptor<StopRecord>()))
            var rec = ComparisonRecorder()
            rec.check("recoveredTrips", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "trip ids", expected: Set(expected.trips.map(\.id)), actual: Set(trips.map(\.id)))
            for want in expected.trips {
                guard let plan = want.plan, let got = trips.first(where: { $0.id == want.id }) else { continue }
                try StoreComparison.planDifferences(expected: plan, actual: ITERFileV1(trip: got.value(), exportedAt: epoch).plan,
                                                    entity: "recoveredTrip", id: want.id, label: want.name, into: &rec)
            }
            f.recoveredTripComparison = info(ComparisonResult(differences: rec.differences, skipped: rec.skipped, checkCount: rec.checkCount))
            if !rec.differences.isEmpty { problem("failure path: \(rec.differences.count) difference(s) in the recovered trips") }

            // What a v1-import recovery cannot carry (counts of what the expected store has).
            let savedPlaces = expected.places.filter { $0.isSaved || $0.originRaw == "user" }.count
            let recoveredSaved = try context.fetch(FetchDescriptor<PlaceRecord>()).filter(\.isSaved).count
            f.expectedLosses = [
                "folders: \(expected.folders.count) in the library, \(f.recoveredCounts?.folders ?? 0) recovered; trips filed in a folder: \(expected.trips.filter { $0.folderID != nil }.count)",
                "pinned trips: \(expected.trips.filter(\.isPinned).count) in the library, \(trips.filter(\.isPinned).count) recovered",
                "pinned folders: \(expected.folders.filter(\.isPinned).count); pinned places: \(expected.places.filter(\.isPinned).count)",
                "saved or own places: \(savedPlaces) in the library, \(recoveredSaved) saved after recovery; places in the recovered store are only those used by a stop (\(expected.places.count) in the library)",
                "sort order of trips and places",
            ]
        }   // container released

        // The original is untouched; a manifest names the recovered store.
        f.originalFilesUnchanged = (fileHashes(dir) == originalBefore) && (fileHashes(dir) == fileHashes(input))
        if f.originalFilesUnchanged != true { problem("failure path: the original store files changed") }
        let manifestURL = dir.appending(path: RecoveryManifest.fileName)
        if let data = try? Data(contentsOf: manifestURL), let m = try? RecoveryManifest.decoder().decode(RecoveryManifest.self, from: data) {
            f.manifestNamesRecovered = m.activeFileName == recoveredURL?.lastPathComponent && fm.fileExists(atPath: dir.appending(path: m.activeFileName).path)
            f.manifestDetails = ["activeFileName": m.activeFileName, "originalFileName": m.originalFileName, "backupFolder": m.backupFolder,
                                 "noticeShown": "\(m.noticeShown)", "skippedFiles": "\(m.skippedFiles.count)"]
            if !m.skippedFiles.isEmpty { problem("failure path: \(m.skippedFiles.count) backup file(s) were skipped by the recovery") }
        } else {
            f.manifestNamesRecovered = false
        }
        if f.manifestNamesRecovered != true { problem("failure path: the recovery manifest does not name the recovered store") }

        // A second open (live containers) must use the recovered store, not recover again.
        do {
            let again = try StoreOpener(storeURL: storeURL, backupsDirectory: backups, clock: { Date() }).open()
            f.reopenUsesRecovered = again.activeURL == recoveredURL && again.recovered != nil
        } catch { f.reopenUsesRecovered = false }
        if f.reopenUsesRecovered != true { problem("failure path: a second open did not use the recovered store") }
        if fileHashes(dir) != originalBefore { f.originalFilesUnchanged = false; problem("failure path: the original changed during the second open") }
    }
}
