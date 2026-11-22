// iter-tokens: Design/tokens.json is the single source; this tool generates what is derived from it.
//
//   iter-tokens generate --json <tokens.json> --swift <TokenValues.swift>   write the Swift registry
//   iter-tokens check    --json <tokens.json> --swift <TokenValues.swift>   exit 0 if the file is what generate writes
//   iter-tokens format   --json <tokens.json>                               rewrite tokens.json in canonical layout
//   iter-tokens assets   --json <tokens.json> --out <dir>                   write Tokens/*.colorset and AccentColor.colorset
//
// All paths are arguments; the tool does not look at the working directory otherwise.
import Foundation
import IterUI

let usage = """
usage: iter-tokens generate --json <tokens.json> --swift <TokenValues.swift>
       iter-tokens check --json <tokens.json> --swift <TokenValues.swift>
       iter-tokens format --json <tokens.json>
       iter-tokens assets --json <tokens.json> --out <dir>
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func summary(_ r: TokenRegistry) -> String {
    "\(r.colors.count) colours, \(r.dimensions.count) dimensions, \(r.typography.count) type styles"
}

/// First differing lines of two texts, for the `check` failure message.
func diffSummary(expected: String, actual: String) -> String {
    let e = expected.components(separatedBy: "\n"), a = actual.components(separatedBy: "\n")
    var out: [String] = ["expected \(e.count) lines, found \(a.count) lines"]
    var shown = 0
    for i in 0..<max(e.count, a.count) {
        let (x, y) = (i < e.count ? e[i] : nil, i < a.count ? a[i] : nil)
        if x == y { continue }
        out.append("line \(i + 1):")
        out.append("  generated: \(x.map { String($0.prefix(160)) } ?? "(missing)")")
        out.append("  on disk:   \(y.map { String($0.prefix(160)) } ?? "(missing)")")
        shown += 1
        if shown == 5 { out.append("  ..."); break }
    }
    return out.joined(separator: "\n")
}

func run(_ args: [String]) throws {
    guard let command = args.first else { throw TokenError(usage) }
    var options: [String: String] = [:]
    var i = 1
    while i < args.count {
        guard args[i].hasPrefix("--"), i + 1 < args.count else { throw TokenError("Bad argument \(args[i])\n\(usage)") }
        options[args[i]] = args[i + 1]
        i += 2
    }
    func path(_ key: String) throws -> URL {
        guard let p = options[key] else { throw TokenError("Missing \(key)\n\(usage)") }
        return URL(fileURLWithPath: p)
    }
    func registry() throws -> TokenRegistry {
        try TokenCodec.importJSON(String(contentsOf: try path("--json"), encoding: .utf8))
    }
    switch command {
    case "generate":
        let r = try registry()
        let swift = try path("--swift")
        try FileManager.default.createDirectory(at: swift.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TokenCodec.swiftSource(r).write(to: swift, atomically: true, encoding: .utf8)
        print("generated \(summary(r))")
    case "check":
        let expected = TokenCodec.swiftSource(try registry())
        let swift = try path("--swift")
        let actual = (try? String(contentsOf: swift, encoding: .utf8)) ?? ""
        if expected == actual { print("ok: \(swift.lastPathComponent) matches tokens.json"); return }
        FileHandle.standardError.write(Data("TokenValues is stale: \(swift.path) differs from what tokens.json generates. Run scripts/tokens.sh.\n\(diffSummary(expected: expected, actual: actual))\n".utf8))
        exit(1)
    case "format":
        let json = try path("--json")
        try TokenCodec.exportJSON(try registry()).write(to: json, atomically: true, encoding: .utf8)
        print("formatted \(json.lastPathComponent)")
    case "assets":
        let r = try registry()
        try TokenCodec.writeAssets(r, to: try path("--out"))
        print("wrote \(r.colors.count) colour sets")
    default:
        throw TokenError(usage)
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("iter-tokens: \(error)")
}
