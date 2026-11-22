import Foundation
import IterCore
@testable import IterData

struct DocumentsError: Error, CustomStringConvertible { var description: String }

/// Writes `documents/` (current-shape `.iter` files) and `documents/older-shape/` (driveNote / transferTimings keys removed).
func writeDocuments(plans: [(name: String, plan: TripPlan)], exportedAt: Date, to dir: URL) throws -> [String] {
    let fm = FileManager.default
    let older = dir.appendingPathComponent("older-shape", isDirectory: true)
    try fm.createDirectory(at: older, withIntermediateDirectories: true)
    var written: [String] = []
    var names = Set<String>()
    for (name, plan) in plans {
        let doc = TripDocument(trip: plan, exportedAt: exportedAt)
        let data = try doc.encoded()
        let file = TripDocument.suggestedFileName(forTripNamed: name)
        guard names.insert(file).inserted else { throw DocumentsError(description: "duplicate file name \(file)") }
        try data.write(to: dir.appendingPathComponent(file))
        written.append(file)
        // Verify: decodes and equals the plan it came from.
        let back = try TripDocument.decode(data)
        guard back == doc, back.trip == plan else { throw DocumentsError(description: "\(file) does not round-trip") }
    }
    // Older shape: JSON-level removal of exactly the `driveNote` (per stop) and `transferTimings` (trip) keys.
    let olderCandidates = plans.filter { $0.plan.dayCount >= 3 && $0.plan.stops.contains(where: { !$0.driveNote.isEmpty }) }
        .sorted { $0.name < $1.name }.prefix(2)
    for (name, plan) in olderCandidates {
        let file = TripDocument.suggestedFileName(forTripNamed: name)
        let original = try Data(contentsOf: dir.appendingPathComponent(file))
        var tree = try JSONDecoder().decode(J.self, from: original)
        // Sanity: the JSON tree re-encodes to the exact bytes the old encoder wrote, so only the removed keys differ.
        guard try J.encodeDocumentData(tree) == original else { throw DocumentsError(description: "JSON tree changes the formatting of \(file)") }
        tree = try strip(tree)
        try finishOlder(tree, plan: plan, doc: TripDocument(trip: plan, exportedAt: exportedAt), file: file, older: older)
        written.append("older-shape/" + file)
    }
    return written
}

private func strip(_ tree: J) throws -> J {
    guard case .object(var root) = tree, case .object(var trip)? = root["trip"], case .array(let stops)? = trip["stops"] else {
        throw DocumentsError(description: "unexpected document shape")
    }
    trip["transferTimings"] = nil
    trip["stops"] = .array(try stops.map { s in
        guard case .object(var o) = s else { throw DocumentsError(description: "unexpected stop shape") }
        o["driveNote"] = nil
        return .object(o)
    })
    root["trip"] = .object(trip)
    return .object(root)
}

private func finishOlder(_ tree: J, plan: TripPlan, doc: TripDocument, file: String, older: URL) throws {
    let data = try J.encodeDocumentData(tree)
    let text = String(decoding: data, as: UTF8.self)
    guard !text.contains("\"driveNote\""), !text.contains("\"transferTimings\"") else { throw DocumentsError(description: "key left in \(file)") }
    try data.write(to: older.appendingPathComponent(file))
    // The old decoder reads it, with the missing fields defaulted.
    var expected = plan
    expected.transferTimings = [:]
    expected.stops = expected.stops.map { var s = $0; s.driveNote = ""; return s }
    let back = try TripDocument.decode(data)
    guard back.trip == expected, back.exportedAt == doc.exportedAt, back.formatVersion == 1 else {
        throw DocumentsError(description: "older-shape \(file) does not decode to the stripped plan")
    }
}
