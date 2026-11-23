import Foundation
import CoreData
import SwiftData
import IterCore
@testable import IterData

// `IterFixtureGen --dump <storeDir> <out.json>`: the dry-run oracle for a store the tool has never seen (the owner's).
//
// It never opens `<storeDir>` itself. The whole folder (Iter.store, -wal, -shm, anything else) is copied twice into a
// fresh temp folder: one copy is read with the frozen schema of the version that wrote it (no migration), the other is
// opened with the OLD current code (`IterSchema.makeContainer(url:)` + `IterStore`, which migrates to V4 and flattens
// folders) and dumped, including every trip's `plan`.
//
// Output (the `.json` suffix of <out.json> is replaced; same dump format as the fixtures' README):
//   <base>.as-written.json   the store as written, before any migration
//   <base>.expected.json     the oracle: the old code's after-picture (feed this to the new code's dry run)
//   <base>.schema.json       written schema version, raw version identifiers and hashes, how they were matched
// Stdout shows counts only: never a name, note or any other user text.

enum DumpMode {
    static func run(_ args: [String]) -> Int32 {
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("usage: IterFixtureGen --dump <storeDir> <out.json>\n".utf8))
            return 2
        }
        do {
            try MainActor.assumeIsolated { try dump(storeDir: URL(fileURLWithPath: args[0], isDirectory: true), out: URL(fileURLWithPath: args[1])) }
            return 0
        } catch {
            FileHandle.standardError.write(Data("dump failed: \(error)\n".utf8))
            return 1
        }
    }

    /// Entity name to version hash (base64) of a schema's Core Data model.
    static func hashes(of schema: any VersionedSchema.Type) -> [String: String] {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: schema.models) else { return [:] }
        var out: [String: String] = [:]
        for e in model.entities { if let n = e.name { out[n] = e.versionHash.base64EncodedString() } }
        return out
    }

    @MainActor
    static func dump(storeDir: URL, out: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("iter-dump-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // The given folder is only ever read as a copy source, and before anything else happens.
        let metaCopy = work.appendingPathComponent("meta", isDirectory: true)
        let writtenCopy = work.appendingPathComponent("as-written", isDirectory: true)
        let expectedCopy = work.appendingPathComponent("expected", isDirectory: true)
        for c in [metaCopy, writtenCopy, expectedCopy] { try fm.copyItem(at: storeDir, to: c) }
        guard fm.fileExists(atPath: metaCopy.appendingPathComponent("Iter.store").path) else { throw GenError(description: "no Iter.store in the folder") }

        // Schema version: the store's NSStoreModelVersionHashes against each frozen schema's entity hashes.
        let md = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: metaCopy.appendingPathComponent("Iter.store"), options: nil)
        var stored: [String: String] = [:]
        for (k, v) in (md[NSStoreModelVersionHashesKey] as? [String: Data]) ?? [:] { stored[k] = v.base64EncodedString() }
        let ids = ((md[NSStoreModelVersionIdentifiersKey] as? [Any])?.compactMap { $0 as? String } ?? []).sorted()
        let candidates: [(version: Int, schema: any VersionedSchema.Type)] =
            [(1, IterSchemaV1.self), (2, IterSchemaV2.self), (3, IterSchemaV3.self), (4, IterSchemaV4.self)]
        let matched = candidates.filter { hashes(of: $0.schema) == stored }.map(\.version)
        // A V2 and a V3 store share Stop/Trip hashes but differ on Folder/Place, so a full-dictionary match is unique.
        var version = matched.count == 1 ? matched[0] : 0
        var how = matched.count == 1 ? "hashes" : "none"
        if version == 0, ids.count == 1, let v = Int(ids[0].prefix(1)), (1...4).contains(v) { version = v; how = "identifier-only" }
        var schemaInfo: [String: J] = [
            "writtenSchemaVersion": .string(version == 0 ? "unknown" : "\(version).0.0"),
            "matchedBy": .string(how),
            "NSStoreModelVersionIdentifiers": .array(ids.map { .string($0) }),
            "NSStoreModelVersionHashes": .object(stored.mapValues { .string($0) }),
            "hashMatchedSchemas": .array(matched.map { .int($0) }),
            "schemaHashes": .object(Dictionary(uniqueKeysWithValues: candidates.map { ("IterSchemaV\($0.version)", J.object(hashes(of: $0.schema).mapValues { .string($0) })) })),
        ]
        let base = out.deletingPathExtension()
        func path(_ suffix: String) -> URL { base.deletingLastPathComponent().appendingPathComponent(base.lastPathComponent + suffix) }
        try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard version != 0 else {
            try J.encodeData(.object(schemaInfo)).write(to: path(".schema.json"))
            throw GenError(description: "could not tell which schema version wrote the store (see \(path(".schema.json").lastPathComponent))")
        }
        let versionString = "\(version).0.0"

        // as-written: the frozen reader of the version that wrote it, no migration, no flattening.
        let gen = ["Written by IterFixtureGen --dump (old IterData). as-written: read with the frozen schema of the writing version, no migration."]
        let writtenURL = writtenCopy.appendingPathComponent("Iter.store")
        var written: J
        switch version {
        case 1: written = try dumpV1(url: writtenURL, fixture: "dump", generator: gen)
        case 2: written = try dumpV2(url: writtenURL, fixture: "dump", generator: gen)
        case 3: written = try dumpV3(url: writtenURL, fixture: "dump", generator: gen)
        default: written = try dumpV4(url: writtenURL, fixture: "dump", generator: gen)
        }

        // expected: the old current code on its own copy.
        let expGen = ["Written by IterFixtureGen --dump (old IterData). expected: a copy opened with IterSchema.makeContainer(url:) + IterStore(container:), then read back with each trip's plan."]
        var expected = try openWithOldCodeForDump(expectedCopy.appendingPathComponent("Iter.store"), version: versionString, generator: expGen)

        var flattened: [J] = []
        if case .object(let w) = written, case .array(let folders)? = w["folders"] {
            for case .object(let f) in folders { if case .string? = f["parentID"] { flattened.append(f["id"]!) } }
        }
        if case .object(var e) = expected { e["flattenedFolderIDs"] = .array(flattened); expected = .object(e) }
        if case .object(var w) = written { w["flattenedFolderIDs"] = .array(flattened); written = .object(w) }

        schemaInfo["afterOldOpenIdentifiers"] = .array(((try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: expectedCopy.appendingPathComponent("Iter.store"), options: nil))
            .flatMap { ($0[NSStoreModelVersionIdentifiersKey] as? [Any])?.compactMap { $0 as? String } } ?? []).map { .string($0) })
        try J.encodeData(written).write(to: path(".as-written.json"))
        try J.encodeData(expected).write(to: path(".expected.json"))
        try J.encodeData(.object(schemaInfo)).write(to: path(".schema.json"))

        func n(_ d: J, _ k: String) -> Int { if case .object(let o) = d, case .array(let a)? = o[k] { return a.count }; return 0 }
        print("written schema version \(versionString) (matched by \(how))")
        print("as-written: folders \(n(written, "folders")), places \(n(written, "places")), trips \(n(written, "trips")), stops \(n(written, "stops"))")
        print("expected:   folders \(n(expected, "folders")), places \(n(expected, "places")), trips \(n(expected, "trips")), stops \(n(expected, "stops")), flattened \(flattened.count)")
        print("wrote \(path(".as-written.json").path), \(path(".expected.json").path), \(path(".schema.json").path)")
    }

    @MainActor
    static func openWithOldCodeForDump(_ url: URL, version: String, generator: [String]) throws -> J {
        let container = try IterSchema.makeContainer(url: url)
        let store = IterStore(container: container)
        return try dumpLive(store: store, fixture: "dump", writtenVersion: version, generator: generator)
    }
}

/// A V4 store read with the live classes straight from a plain container: no migration plan and no `IterStore` (so
/// nothing is flattened). Same shape as `dumpV3`, plus `transferTimingsRaw` / `driveNote` through the scalar readers.
func dumpV4(url: URL, fixture: String, generator: [String]) throws -> J {
    let schema = Schema(versionedSchema: IterSchemaV4.self)
    let c = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    let ctx = ModelContext(c)
    let folders = try ctx.fetch(FetchDescriptor<FolderRecord>()), places = try ctx.fetch(FetchDescriptor<PlaceRecord>())
    let trips = try ctx.fetch(FetchDescriptor<TripRecord>()), stops = try ctx.fetch(FetchDescriptor<StopRecord>())
    var o: [String: J] = ["fixture": .string(fixture), "writtenSchemaVersion": .string("4.0.0"), "generator": .array(generator.map { .string($0) })]
    o["folders"] = sortedByID(folders.map { folderScalars($0).merging(["parentID": .uuid($0.parent?.id),
        "tripIDs": .sortedUUIDs(($0.trips ?? []).map(\.id)), "placeIDs": .sortedUUIDs(($0.places ?? []).map(\.id))]) { a, _ in a } })
    o["places"] = sortedByID(places.map { placeScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .sortedUUIDs(($0.stops ?? []).map(\.id))]) { a, _ in a } })
    o["trips"] = sortedByID(trips.map { tripScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .uuids(orderedStopIDs($0.stops ?? []))]) { a, _ in a } })
    o["stops"] = sortedByID(stops.map { stopScalars($0).merging(["tripID": .uuid($0.trip?.id), "placeID": .uuid($0.place?.id)]) { a, _ in a } })
    return .object(o)
}
