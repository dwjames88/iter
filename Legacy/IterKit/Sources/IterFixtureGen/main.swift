import Foundation
import SwiftData
import IterCore
@testable import IterData

// IterFixtureGen: writes the rebuild's test fixtures with the OLD IterData code.
// Usage: swift run --package-path Legacy/IterKit IterFixtureGen <outputDir>
//        swift run --package-path Legacy/IterKit IterFixtureGen --dump <storeDir> <out.json>

struct GenError: Error, CustomStringConvertible { var description: String }

// Dump mode (see Dump.swift): reads a store folder the tool has never seen, through copies only.
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--dump" {
    exit(DumpMode.run(Array(CommandLine.arguments.dropFirst(2))))
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: IterFixtureGen <outputDir>\n".utf8))
    exit(2)
}
let fm = FileManager.default
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
let tmpRoot = fm.temporaryDirectory.appendingPathComponent("iter-fixturegen-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmpRoot) }

@MainActor func copyDir(_ from: URL, _ to: URL) throws {
    try? fm.removeItem(at: to)
    try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.copyItem(at: from, to: to)
}
@MainActor func freshDir(_ name: String) throws -> URL {
    let d = tmpRoot.appendingPathComponent(name, isDirectory: true)
    try fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}
@MainActor func write(_ value: J, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try J.encodeData(value).write(to: url)
}

// Delete and rewrite only what this tool owns.
for owned in ["stores", "documents", "model-hashes.json"] { try? fm.removeItem(at: outDir.appendingPathComponent(owned)) }
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let generatorNotes: [String] = [
    "Written by IterFixtureGen (Legacy/IterKit) with the old IterData module.",
    "expected.json: a copy of the fixture opened with IterSchema.makeContainer(url:) + IterStore(container:) (migrates to V4, runs flattenFolders), then read back.",
    "as-written.json: the fixture read back before any migration (V1-V3 with the frozen schema and no migration plan; V4 with the live code).",
    "Dates are timeIntervalSinceReferenceDate Doubles; UUIDs are uppercase; arrays are sorted by id except stopIDs of a trip (orderedStops order).",
    "flattenFolders sets updatedAt to the time of generation on every flattened folder (listed in flattenedFolderIDs); those values change on regeneration.",
]

var storeHashes: [String: J] = [:]
var counts: [String] = []

@MainActor func openWithOldCode(_ storeURL: URL, fixture: String, writtenVersion: String) throws -> J {
    let container = try IterSchema.makeContainer(url: storeURL)
    let store = IterStore(container: container)
    return try dumpLive(store: store, fixture: fixture, writtenVersion: writtenVersion, generator: generatorNotes)
}

@MainActor func count(_ dump: J, _ key: String) -> Int {
    if case .object(let o) = dump, case .array(let a)? = o[key] { return a.count }
    return 0
}

@MainActor func finish(name: String, version: String, pristineDir: URL, asWritten: (URL) throws -> J) throws {
    // Metadata and as-written dump, each from its own copy of the pristine files.
    let metaBefore = try freshDir("\(name)-meta-before").appendingPathComponent("copy", isDirectory: true)
    try copyDir(pristineDir, metaBefore)
    let before = try storeMetadata(at: metaBefore.appendingPathComponent("Iter.store"))

    let asWrittenDir = try freshDir("\(name)-aswritten").appendingPathComponent("copy", isDirectory: true)
    try copyDir(pristineDir, asWrittenDir)
    var written = try asWritten(asWrittenDir.appendingPathComponent("Iter.store"))

    let migratedDir = try freshDir("\(name)-migrated").appendingPathComponent("copy", isDirectory: true)
    try copyDir(pristineDir, migratedDir)
    var expected = try MainActor.assumeIsolated {
        try openWithOldCode(migratedDir.appendingPathComponent("Iter.store"), fixture: name, writtenVersion: version)
    }
    // Containers are released; read the metadata the old open left behind.
    let after = try storeMetadata(at: migratedDir.appendingPathComponent("Iter.store"))

    // Which folders were nested in the written store (and so flattened by the open)?
    var flattened: [J] = []
    if case .object(let w) = written, case .array(let folders)? = w["folders"] {
        for case .object(let f) in folders { if case .string? = f["parentID"] { flattened.append(f["id"]!) } }
    }
    if case .object(var e) = expected { e["flattenedFolderIDs"] = .array(flattened); expected = .object(e) }
    if case .object(var w) = written { w["flattenedFolderIDs"] = .array(flattened); written = .object(w) }

    let dest = outDir.appendingPathComponent("stores/\(name)", isDirectory: true)
    try copyDir(pristineDir, dest)
    try write(expected, to: dest.appendingPathComponent("expected.json"))
    try write(written, to: dest.appendingPathComponent("as-written.json"))
    storeHashes[name] = .object(["writtenSchemaVersion": .string(version), "beforeMigration": before, "afterOldOpen": after])
    counts.append("\(name): folders \(count(written, "folders"))->\(count(expected, "folders")), places \(count(expected, "places")), trips \(count(expected, "trips")), stops \(count(expected, "stops")), flattened \(flattened.count)")
}

// MARK: V1 - V3

for version in 1...3 {
    let name = "v\(version)"
    let seed = makeSeed(version: version)
    let pristine = try freshDir("\(name)-write")
    let url = pristine.appendingPathComponent("Iter.store")
    do {   // every container and context is released when this scope ends
        switch version {
        case 1: try writeV1(seed: seed, to: url)
        case 2: try writeV2(seed: seed, to: url)
        default: try writeV3(seed: seed, to: url)
        }
    }
    try finish(name: name, version: "\(version).0.0", pristineDir: pristine) { copyURL in
        switch version {
        case 1: return try dumpV1(url: copyURL, fixture: name, generator: generatorNotes)
        case 2: return try dumpV2(url: copyURL, fixture: name, generator: generatorNotes)
        default: return try dumpV3(url: copyURL, fixture: name, generator: generatorNotes)
        }
    }
}

// MARK: V4 realistic, written through the old public API

let exportedAt = Date(timeIntervalSince1970: 1_790_000_000)
let realisticDir = try freshDir("v4-write")
let plans: [(name: String, plan: TripPlan)] = try MainActor.assumeIsolated {
    try buildRealistic(at: realisticDir.appendingPathComponent("Iter.store"), exportedAt: exportedAt)
}
try finish(name: "v4-realistic", version: "4.0.0", pristineDir: realisticDir) { copyURL in
    try MainActor.assumeIsolated { try openWithOldCode(copyURL, fixture: "v4-realistic", writtenVersion: "4.0.0") }
}

// MARK: Documents

let documentFiles = try writeDocuments(plans: plans, exportedAt: exportedAt, to: outDir.appendingPathComponent("documents", isDirectory: true))

// MARK: Model identity evidence

let schemas: [(String, any VersionedSchema.Type)] = [("IterSchemaV1", IterSchemaV1.self), ("IterSchemaV2", IterSchemaV2.self),
                                                      ("IterSchemaV3", IterSchemaV3.self), ("IterSchemaV4", IterSchemaV4.self)]
var schemaInfo: [String: J] = [:]
for (n, s) in schemas { schemaInfo[n] = modelInfo(s) }
try write(.object([
    "generatedBy": .string("IterFixtureGen; old module IterData. Entity data from NSManagedObjectModel.makeManagedObjectModel(for:) over each VersionedSchema's models."),
    "schemas": .object(schemaInfo),
    "stores": .object(storeHashes),
]), to: outDir.appendingPathComponent("model-hashes.json"))

print(counts.joined(separator: "\n"))
print("documents: \(documentFiles.joined(separator: ", "))")
print("wrote fixtures to \(outDir.path)")
