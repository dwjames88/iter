#if canImport(AppKit)
import AppKit
import Foundation
import Testing

/// Every SF Symbol name the app and the package use must exist on the macOS this runs on.
/// A name that does not exist draws nothing, with no error, so this scans the sources and checks each one.
///
/// This runs under `swift test` (not sandboxed), because it reads the repository. The scanner collects string
/// literals in these places:
///   * the argument of `systemImage:` and `systemName:` (every literal in it, so ternaries are covered);
///   * a bare literal or ternary of literals after `symbol:`, `symbolName:` or `symbol =`;
///   * the first argument of `fact(` in SpotFactsView;
///   * every literal in the body of a function whose name contains "symbol" (`LightText.symbol`, `moonSymbol`).
/// A `systemImage:` / `systemName:` argument with no literal in it must be one of the known dynamic sources
/// in `knownDynamicSources`, whose literals the rules above already cover. Anything else fails the test, so a
/// new indirection cannot silently escape the scan.
///
/// Out of scope: WeatherKit's runtime `symbolName` (Apple supplies and owns those names).
@Suite("SF Symbol names")
struct SymbolNameTests {
    /// Argument expressions that are not literals but are fed only by literals the scan already collects.
    static let knownDynamicSources = [
        "LightText.symbol(",      // function body scanned
        "LightText.moonSymbol(",  // function body scanned
        "WeatherStatusText.symbol(", // function body scanned
        "notice.symbol",          // ScoutNotice(symbol: "…") literals scanned
        "h.symbolName",           // WeatherKit / SampleWeatherService hourly symbol; `symbol = …` scanned
        "symbol",                 // SpotFactsView.fact(_ symbol:), call-site literals scanned
    ]

    struct Use { let name: String; let file: String; let line: Int }
    struct Gap { let expression: String; let file: String; let line: Int }

    /// The five window symbols (`LightText.symbol(_ kind:)`), fixed by the owner on 2026-10-07.
    static let windowSymbols = ["sun.haze.fill", "sunrise.fill", "sunset.fill", "moon.haze.fill", "moon.stars.fill"]

    @Test func windowSymbolsResolve() throws {
        for name in Self.windowSymbols {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "Window symbol \"\(name)\" does not exist on this macOS.")
        }
        // The mapping itself must still use all five, so a rename in LightText cannot drift from this list.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/Sources/Text/LightText.swift"), encoding: .utf8)
        for name in Self.windowSymbols {
            #expect(source.contains("\"\(name)\""), "LightText.swift no longer maps \"\(name)\".")
        }
    }

    @Test func everySymbolNameResolves() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()   // IterDesignTests, Tests
            .deletingLastPathComponent().deletingLastPathComponent()   // IterKit, Packages
            .deletingLastPathComponent()                               // repository root
        var uses: [Use] = []
        var gaps: [Gap] = []
        for dir in ["App/Sources", "Packages/IterKit/Sources"] {
            let base = root.appendingPathComponent(dir)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            for url in files.sorted(by: { $0.path < $1.path }) {
                let text = try String(contentsOf: url, encoding: .utf8)
                let rel = String(url.path.dropFirst(root.path.count + 1))
                Self.scan(text, file: rel, uses: &uses, gaps: &gaps)
            }
        }

        let unique = Set(uses.map(\.name))
        print("SymbolNameTests: \(unique.count) unique names, \(uses.count) uses")
        #expect(unique.count > 60, "Scanner found only \(unique.count) names; it is probably broken.")

        for gap in gaps {
            Issue.record("\(gap.file):\(gap.line): `\(gap.expression)` is not a literal and not a known dynamic source. Add the source's literals to the scan (see SymbolNameTests) and to knownDynamicSources.")
        }
        for use in uses where NSImage(systemSymbolName: use.name, accessibilityDescription: nil) == nil {
            Issue.record("\(use.file):\(use.line): SF Symbol \"\(use.name)\" does not exist on this macOS.")
        }
    }

    // MARK: Scanner

    private static let literal = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    private static let strongLabel = try! NSRegularExpression(pattern: #"\b(?:systemImage|systemName)\s*:\s*"#)
    private static let weakLabel = try! NSRegularExpression(pattern: #"\b(?:symbolName|symbol)\s*(?::|=(?!=))\s*"#)
    private static let factCall = try! NSRegularExpression(pattern: #"\bfact\(\s*"#)
    private static let symbolFunc = try! NSRegularExpression(pattern: #"\bfunc\s+\w*[sS]ymbol\w*\s*\("#)
    /// A bare literal, or `cond ? "a" : "b"`.
    private static let literalShape = try! NSRegularExpression(pattern: #"^(?:.*\?\s*)?"[^"]*"(?:\s*:\s*"[^"]*")?$"#)

    static func scan(_ text: String, file: String, uses: inout [Use], gaps: inout [Gap]) {
        let lines = text.components(separatedBy: "\n").map(stripComment)
        var bodyDepth = 0          // > 0 while inside a symbol function's body
        var pendingBody = false    // saw the signature, waiting for its opening brace

        for (index, line) in lines.enumerated() {
            let number = index + 1
            func add(_ expr: String) {
                for name in literals(in: expr) { uses.append(Use(name: name, file: file, line: number)) }
            }

            if bodyDepth == 0 && !pendingBody && matches(symbolFunc, line) { pendingBody = true }
            if bodyDepth > 0 || pendingBody {
                add(line)
                for ch in line {
                    if ch == "{" { bodyDepth += 1; pendingBody = false }
                    if ch == "}" { bodyDepth -= 1 }
                }
                continue
            }

            for expr in expressions(after: strongLabel, in: line) {
                if expr.contains("\"") {
                    add(expr)
                } else if !knownDynamicSources.contains(where: { expr.hasPrefix($0) && ($0 != "symbol" || expr == "symbol") }) {
                    gaps.append(Gap(expression: expr, file: file, line: number))
                }
            }
            for expr in expressions(after: weakLabel, in: line) where matches(literalShape, expr) { add(expr) }
            for expr in expressions(after: factCall, in: line) where expr.hasPrefix("\"") { add(expr) }
        }
    }

    /// The argument expressions that follow each match of `label`, up to a depth-0 comma or the closing parenthesis.
    private static func expressions(after label: NSRegularExpression, in line: String) -> [String] {
        let ns = line as NSString
        return label.matches(in: line, range: NSRange(location: 0, length: ns.length)).map { m in
            let chars = Array(ns.substring(from: m.range.upperBound))
            var depth = 0, inString = false, end = chars.count, i = 0
            while i < chars.count {
                let c = chars[i]
                if inString {
                    if c == "\\" { i += 1 } else if c == "\"" { inString = false }
                } else if c == "\"" { inString = true }
                else if "([{".contains(c) { depth += 1 }
                else if ")]}".contains(c) {
                    if depth == 0 { end = i; break }
                    depth -= 1
                } else if c == ",", depth == 0 { end = i; break }
                i += 1
            }
            return String(chars[0..<end]).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func literals(in text: String) -> [String] {
        let ns = text as NSString
        return literal.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Removes a `//` comment, ignoring `//` inside a string literal.
    private static func stripComment(_ line: String) -> String {
        let chars = Array(line)
        var inString = false, i = 0
        while i < chars.count {
            if inString {
                if chars[i] == "\\" { i += 1 } else if chars[i] == "\"" { inString = false }
            } else if chars[i] == "\"" { inString = true }
            else if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" { return String(chars[0..<i]) }
            i += 1
        }
        return line
    }
}
#endif
