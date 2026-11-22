import Foundation
import SwiftData
import IterModel

/// The safety copy made before the first V5 open (blueprint §5.3 step 3): the raw store files, plus every trip as an
/// `.iter` v1 file read through the frozen V4 classes from a SCRATCH copy, so the real store is never opened by it.
struct StoreBackup {
    static let pendingMarkerName = ".migration-pending"

    var storeURL: URL
    var backupsDirectory: URL
    var scratchDirectory: URL
    var files: any StoreFileOperations
    var containers: StoreContainerFactory
    var exportTrip: @Sendable (Trip, Date) throws -> Data
    var now: Date

    /// "pre-v5-2026-11-22-141500" (local time).
    static func folderName(for date: Date, prefix: String = "pre-v5-") -> String {
        prefix + timestamp(date)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// The store file, its side files and its external-data folder, by file name, in copy order.
    static func storeItemNames(for storeURL: URL) -> [String] {
        let name = storeURL.lastPathComponent
        let base = storeURL.deletingPathExtension().lastPathComponent
        return [name, name + "-wal", name + "-shm", ".\(base)_SUPPORT"]
    }

    private var existingItems: [URL] {
        let directory = storeURL.deletingLastPathComponent()
        return Self.storeItemNames(for: storeURL).map { directory.appending(path: $0) }.filter { files.fileExists(at: $0) }
    }

    /// Makes the backup and returns its folder. On any failure removes what it made and throws; the store is never
    /// opened, moved or changed by this.
    func make(foundVersion: StoreSchemaVersion) throws -> URL {
        // Cleanup uses FileManager directly: it must work even when the injected operations are the thing failing.
        let fm = FileManager.default
        var folder = backupsDirectory.appending(path: Self.folderName(for: now), directoryHint: .isDirectory)
        var scratch: URL?
        do {
            try files.createDirectory(at: backupsDirectory)
            Self.removeStalePending(in: backupsDirectory)
            var n = 2
            while files.fileExists(at: folder) {
                folder = backupsDirectory.appending(path: Self.folderName(for: now) + "-\(n)", directoryHint: .isDirectory)
                n += 1
            }
            try files.createDirectory(at: folder)
            let marker = folder.appending(path: Self.pendingMarkerName)
            try files.write(Data(), to: marker)

            // 1. The raw files, through temporary names, then renamed.
            let sources = existingItems
            for source in sources {
                let temp = folder.appending(path: source.lastPathComponent + ".copying-\(UUID().uuidString)")
                try files.copyItem(at: source, to: temp)
                let final = folder.appending(path: source.lastPathComponent)
                try files.moveItem(at: temp, to: final)
                if !Self.isDirectory(source) {
                    guard try files.fileSize(at: source) == files.fileSize(at: final) else { throw BackupError.sizeMismatch(source.lastPathComponent) }
                }
            }

            // 2. A scratch copy, opened on the frozen V4 schema; every trip written as an .iter v1 file.
            let scratchDir = scratchDirectory.appending(path: "iter-backup-scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
            scratch = scratchDir
            try files.createDirectory(at: scratchDir)
            for source in sources {
                try files.copyItem(at: source, to: scratchDir.appending(path: source.lastPathComponent))
            }
            let snapshot = try Self.readLegacySnapshot(scratchStore: scratchDir.appending(path: storeURL.lastPathComponent),
                                                       containers: containers)
            var used = Set<String>()
            var tripFiles: [String] = []
            for trip in snapshot.trips {
                let name = Self.uniqueName(ITERFileInfo.suggestedFileName(forTripNamed: trip.name), used: &used)
                let data = try exportTrip(trip, now)
                let temp = folder.appending(path: name + ".writing-\(UUID().uuidString)")
                try files.write(data, to: temp)
                try files.moveItem(at: temp, to: folder.appending(path: name))
                tripFiles.append(name)
            }

            // 3. backup.json
            let info = BackupManifest(
                createdAt: now, schemaVersionFound: foundVersion.versionString, sourceStore: storeURL.path,
                sourceFiles: sources.map(\.lastPathComponent),
                counts: .init(trips: snapshot.trips.count, stops: snapshot.stopCount, places: snapshot.placeCount,
                              folders: snapshot.folderCount),
                tripFiles: tripFiles)
            try files.write(try BackupInfoCoding.encode(info), to: folder.appending(path: BackupManifest.fileName))

            // 4. The scratch copy goes; the marker goes last, only when everything above succeeded.
            try files.removeItem(at: scratchDir)
            scratch = nil
            try files.removeItem(at: marker)
            return folder
        } catch {
            if let scratch { try? fm.removeItem(at: scratch) }
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    enum BackupError: Error { case sizeMismatch(String) }

    struct LegacySnapshot {
        var trips: [Trip]
        var stopCount: Int
        var placeCount: Int
        var folderCount: Int
    }

    /// Opens the scratch store on frozen V4 (migrating V1 to V3 up to V4), reads every trip, and lets the container go.
    static func readLegacySnapshot(scratchStore: URL, containers: StoreContainerFactory) throws -> LegacySnapshot {
        let container = try containers.openLegacyV4(scratchStore)
        let context = ModelContext(container)
        let trips = try context.fetch(FetchDescriptor<IterSchemaV4.TripRecord>())
        let places = try context.fetchCount(FetchDescriptor<IterSchemaV4.PlaceRecord>())
        let folders = try context.fetchCount(FetchDescriptor<IterSchemaV4.FolderRecord>())
        let stops = try context.fetchCount(FetchDescriptor<IterSchemaV4.StopRecord>())
        let values = trips.map { $0.value() }.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
        return LegacySnapshot(trips: values, stopCount: stops, placeCount: places, folderCount: folders)
    }

    /// "Name.iter", then "Name 2.iter", "Name 3.iter"... for names that clash (case-insensitively).
    static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        let ext = "." + ITERFileInfo.fileExtension
        let stem = name.hasSuffix(ext) ? String(name.dropLast(ext.count)) : name
        var candidate = stem + ext
        var n = 2
        while !used.insert(candidate.lowercased()).inserted {
            candidate = "\(stem) \(n)\(ext)"
            n += 1
        }
        return candidate
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// A backup folder still carrying the marker is an earlier attempt that never finished; nothing opened the store
    /// after it, so it is safe to remove.
    private static func removeStalePending(in directory: URL) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for child in children where fm.fileExists(atPath: child.appending(path: pendingMarkerName).path) {
            try? fm.removeItem(at: child)
        }
    }
}

enum BackupInfoCoding {
    static func encode(_ info: BackupManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(info)
    }
}
