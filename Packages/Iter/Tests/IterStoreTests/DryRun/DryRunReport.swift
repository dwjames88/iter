import Foundation

/// What the real-store dry run found, written as `report.json` and `report.md`. Contains counts, ids, trip names and field
/// names; free-text fields (`notes`, `blurb`, `note`, `driveNote`) only ever appear as "differs (len a -> b)".
struct DryRunReport: Codable {
    struct FileHash: Codable { var name: String; var bytes: Int?; var sha256Before: String?; var sha256After: String? }
    struct Counts: Codable, Equatable { var folders = 0, places = 0, trips = 0, stops = 0
        var text: String { "folders \(folders), places \(places), trips \(trips), stops \(stops)" }
    }
    struct OpenInfo: Codable { var activeURL: String; var recovered: Bool; var backupFolder: String?; var storeIsOriginalURL: Bool }
    struct ComparisonInfo: Codable { var checks: Int; var differences: [StoreDifference]; var skipped: [String] }
    struct BackupInfo: Codable {
        var folder: String?
        var note: String?
        var items: [String] = []
        var rawFiles: [String] = []              // "name: identical to input" / "name: DIFFERENT"
        var iterFiles: Int = 0
        var iterComparison: ComparisonInfo?
        var manifest: [String: String] = [:]
    }
    struct FailureInfo: Codable {
        var note: String?
        var originalFilesUnchanged: Bool?
        var recoveredStore: String?
        var recoveredNameDiffers: Bool?
        var manifestNamesRecovered: Bool?
        var manifestDetails: [String: String] = [:]
        var recoveredCounts: Counts?
        var recoveredTripComparison: ComparisonInfo?
        var reopenUsesRecovered: Bool?
        /// Not in an `.iter` v1 file, so a v1-import recovery cannot carry them. Expected losses, not differences.
        var expectedLosses: [String] = []
    }

    var inputFolderItems: [String] = []
    var inputFiles: [FileHash] = []
    var inputUnchanged = false
    var detectedSchema: String?
    var oldCodeWrittenSchema: String?
    var rawVersionIdentifiers: [String] = []
    var open: OpenInfo?
    var countsBefore: Counts?
    var countsBeforeSource: String?
    var countsExpected: Counts?
    var countsAfter: Counts?
    var comparison: ComparisonInfo?
    var libraryComparison: ComparisonInfo?
    var backup: BackupInfo?
    var failurePath: FailureInfo?
    var migratedFolder: String?
    /// Anything that makes the dry run fail (differences are listed in `comparison`, and also counted here).
    var problems: [String] = []

    var passed: Bool { problems.isEmpty }

    func markdown() -> String {
        var m = "# Real-store dry run\n\nResult: **\(passed ? "PASS, zero differences" : "FAIL")**\n\n"
        if !problems.isEmpty { m += "## Problems\n\n" + problems.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        m += "## Input\n\n"
        m += "- Folder items: \(inputFolderItems.joined(separator: ", "))\n"
        for f in inputFiles { m += "- `\(f.name)`: \(f.bytes.map { "\($0) bytes" } ?? "absent"), SHA-256 before \(f.sha256Before ?? "-"), after \(f.sha256After ?? "-")\n" }
        m += "- Input files unchanged by the run: **\(inputUnchanged ? "yes" : "NO")**\n\n"
        m += "## Schema\n\n- Detected by the new `StoreSchemaDetector`: \(detectedSchema ?? "none")\n"
        m += "- Written version per the old-code dump: \(oldCodeWrittenSchema ?? "unknown")\n"
        m += "- Raw `NSStoreModelVersionIdentifiers`: \(rawVersionIdentifiers.joined(separator: ", "))\n\n"
        if let o = open {
            m += "## Open (as the Mac app does)\n\n- activeURL: `\(o.activeURL)` (the requested store: \(o.storeIsOriginalURL))\n- recovered: \(o.recovered)\n- backupFolder: \(o.backupFolder.map { "`\($0)`" } ?? "none")\n\n"
        }
        m += "## Counts\n\n"
        if let b = countsBefore { m += "- Before (\(countsBeforeSource ?? "?")): \(b.text)\n" }
        if let e = countsExpected { m += "- Expected (old code after its open): \(e.text)\n" }
        if let a = countsAfter { m += "- After (new store): \(a.text)\n" }
        m += "\n"
        for (title, c) in [("Differences: raw V5 records vs expected", comparison), ("Differences: through LibraryStore vs expected", libraryComparison)] {
            guard let c else { continue }
            m += "## \(title)\n\n\(c.checks) checks, **\(c.differences.count) difference(s)**.\n\n"
            m += Self.differenceLines(c.differences)
            if !c.skipped.isEmpty { m += "\nSkipped on purpose:\n" + c.skipped.map { "- \($0)" }.joined(separator: "\n") + "\n" }
            m += "\n"
        }
        if let b = backup {
            m += "## Backup folder\n\n"
            m += "- folder: \(b.folder.map { "`\($0)`" } ?? "none")\n"
            if let n = b.note { m += "- \(n)\n" }
            m += "- items: \(b.items.joined(separator: ", "))\n"
            for r in b.rawFiles { m += "- raw store file \(r)\n" }
            m += "- `.iter` files: \(b.iterFiles)\n"
            if let c = b.iterComparison { m += "- `.iter` plans vs expected: \(c.checks) checks, **\(c.differences.count) difference(s)**\n" + Self.differenceLines(c.differences) }
            for (k, v) in b.manifest.sorted(by: { $0.key < $1.key }) { m += "- backup.json \(k): \(v)\n" }
            m += "\n"
        }
        if let f = failurePath {
            m += "## Failure path (V5 open forced to fail on copy 2)\n\n"
            if let n = f.note { m += "- \(n)\n" }
            if let v = f.originalFilesUnchanged { m += "- Original store files byte-identical afterwards: **\(v ? "yes" : "NO")**\n" }
            if let r = f.recoveredStore { m += "- Recovered store: `\(r)` (different name from the original: \(f.recoveredNameDiffers.map(String.init) ?? "?"))\n" }
            if let v = f.manifestNamesRecovered { m += "- Recovery manifest names the recovered store: **\(v ? "yes" : "NO")**\n" }
            for (k, v) in f.manifestDetails.sorted(by: { $0.key < $1.key }) { m += "- manifest \(k): \(v)\n" }
            if let c = f.recoveredCounts { m += "- Recovered counts: \(c.text)\n" }
            if let c = f.recoveredTripComparison { m += "- Recovered trip plans vs expected: \(c.checks) checks, **\(c.differences.count) difference(s)**\n" + Self.differenceLines(c.differences) }
            if let v = f.reopenUsesRecovered { m += "- A second open uses the recovered store through the manifest (no second recovery): **\(v ? "yes" : "NO")**\n" }
            if !f.expectedLosses.isEmpty { m += "\nExpected losses of a v1-import recovery (not differences):\n" + f.expectedLosses.map { "- \($0)" }.joined(separator: "\n") + "\n" }
            m += "\n"
        }
        if let d = migratedFolder { m += "## Migrated copy\n\nLeft at `\(d)` for renders.\n" }
        return m
    }

    private static func differenceLines(_ list: [StoreDifference]) -> String {
        guard !list.isEmpty else { return "None.\n" }
        let shown = list.prefix(400).map { "- \($0.description)" }.joined(separator: "\n")
        return shown + (list.count > 400 ? "\n- ... \(list.count - 400) more in report.json" : "") + "\n"
    }
}
