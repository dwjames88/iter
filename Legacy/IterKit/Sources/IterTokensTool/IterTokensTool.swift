import Foundation
import IterDesign

/// `iter-tokens export --json <tokens.json> --assets <Assets.xcassets>`
/// `iter-tokens import --json <tokens.json> --swift <TokenValues.swift>`
/// All paths are arguments; the tool does not look at the working directory otherwise.
@main
struct IterTokensTool {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("iter-tokens: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(_ args: [String]) throws {
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
        switch command {
        case "export":
            let registry = TokenRegistry.current
            let json = try path("--json")
            try FileManager.default.createDirectory(at: json.deletingLastPathComponent(), withIntermediateDirectories: true)
            try TokenCodec.exportJSON(registry).write(to: json, atomically: true, encoding: .utf8)
            try TokenCodec.writeAssets(registry, to: try path("--assets"))
            print("exported \(registry.colors.count) colours, \(registry.dimensions.count) dimensions, \(registry.typography.count) type styles")
        case "import":
            let text = try String(contentsOf: try path("--json"), encoding: .utf8)
            let registry = try TokenCodec.importJSON(text)
            try TokenCodec.swiftSource(registry).write(to: try path("--swift"), atomically: true, encoding: .utf8)
            print("imported \(registry.colors.count) colours, \(registry.dimensions.count) dimensions, \(registry.typography.count) type styles")
        default:
            throw TokenError(usage)
        }
    }

    static let usage = """
    usage: iter-tokens export --json <tokens.json> --assets <Assets.xcassets>
           iter-tokens import --json <tokens.json> --swift <TokenValues.swift>
    """
}
