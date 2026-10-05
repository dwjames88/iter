import Foundation

/// A minimal JSON value that keeps object key order, so exported files are stable and reviewable in a diff.
public indirect enum OrderedJSON: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([OrderedJSON])
    case object([(key: String, value: OrderedJSON)])

    public static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case (.string(let x), .string(let y)): x == y
        case (.number(let x), .number(let y)): x == y
        case (.bool(let x), .bool(let y)): x == y
        case (.null, .null): true
        case (.array(let x), .array(let y)): x == y
        case (.object(let x), .object(let y)):
            x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public subscript(key: String) -> OrderedJSON? {
        if case .object(let pairs) = self { return pairs.first { $0.key == key }?.value }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var pairs: [(key: String, value: OrderedJSON)]? { if case .object(let p) = self { p } else { nil } }

    // MARK: Emit

    /// Two-space indented, one trailing newline. Deterministic.
    public func serialized() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out + "\n"
    }

    public static func formatNumber(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return String(v)
    }

    static func quote(_ s: String) -> String {
        var r = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\t": r += "\\t"
            case "\r": r += "\\r"
            default:
                if u.value < 0x20 { r += String(format: "\\u%04x", u.value) } else { r.unicodeScalars.append(u) }
            }
        }
        return r + "\""
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent + 1)
        let end = String(repeating: "  ", count: indent)
        switch self {
        case .string(let s): out += Self.quote(s)
        case .number(let n): out += Self.formatNumber(n)
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            // Short scalar arrays stay on one line (colour components).
            if items.allSatisfy({ if case .number = $0 { true } else { false } }) {
                out += "[" + items.map { $0.numberValue.map(Self.formatNumber) ?? "" }.joined(separator: ", ") + "]"
                return
            }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indent: indent + 1)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += end + "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, p) in pairs.enumerated() {
                out += pad + Self.quote(p.key) + ": "
                p.value.write(into: &out, indent: indent + 1)
                out += i == pairs.count - 1 ? "\n" : ",\n"
            }
            out += end + "}"
        }
    }

    // MARK: Parse

    public static func parse(_ text: String) throws -> OrderedJSON {
        var p = Parser(Array(text.unicodeScalars))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.i == p.s.count else { throw TokenError("Unexpected trailing characters in JSON at offset \(p.i)") }
        return v
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func skipSpace() { while i < s.count, s[i] == " " || s[i] == "\n" || s[i] == "\t" || s[i] == "\r" { i += 1 } }

        mutating func value() throws -> OrderedJSON {
            guard i < s.count else { throw TokenError("Unexpected end of JSON") }
            switch s[i] {
            case "{":
                i += 1
                var pairs: [(key: String, value: OrderedJSON)] = []
                skipSpace()
                if i < s.count, s[i] == "}" { i += 1; return .object(pairs) }
                while true {
                    skipSpace()
                    let k = try string()
                    skipSpace()
                    try expect(":")
                    skipSpace()
                    pairs.append((k, try value()))
                    skipSpace()
                    if i < s.count, s[i] == "," { i += 1; continue }
                    try expect("}")
                    return .object(pairs)
                }
            case "[":
                i += 1
                var items: [OrderedJSON] = []
                skipSpace()
                if i < s.count, s[i] == "]" { i += 1; return .array(items) }
                while true {
                    skipSpace()
                    items.append(try value())
                    skipSpace()
                    if i < s.count, s[i] == "," { i += 1; continue }
                    try expect("]")
                    return .array(items)
                }
            case "\"": return .string(try string())
            case "t": try word("true"); return .bool(true)
            case "f": try word("false"); return .bool(false)
            case "n": try word("null"); return .null
            default:
                let start = i
                while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
                var str = ""
                str.unicodeScalars.append(contentsOf: s[start..<i])
                guard let d = Double(str) else { throw TokenError("Bad JSON number at offset \(start)") }
                return .number(d)
            }
        }

        mutating func expect(_ c: Unicode.Scalar) throws {
            guard i < s.count, s[i] == c else { throw TokenError("Expected '\(c)' at offset \(i)") }
            i += 1
        }

        mutating func word(_ w: String) throws {
            for c in w.unicodeScalars { try expect(c) }
        }

        mutating func string() throws -> String {
            try expect("\"")
            var r = String.UnicodeScalarView()
            while i < s.count {
                let c = s[i]
                i += 1
                if c == "\"" { return String(r) }
                if c != "\\" { r.append(c); continue }
                guard i < s.count else { break }
                let e = s[i]
                i += 1
                switch e {
                case "n": r.append("\n")
                case "t": r.append("\t")
                case "r": r.append("\r")
                case "b": r.append("\u{8}")
                case "f": r.append("\u{c}")
                case "u":
                    guard i + 4 <= s.count else { throw TokenError("Bad \\u escape") }
                    var hex = ""
                    hex.unicodeScalars.append(contentsOf: s[i..<i + 4])
                    i += 4
                    guard let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) else { throw TokenError("Bad \\u escape") }
                    r.append(u)
                default: r.append(e)
                }
            }
            throw TokenError("Unterminated JSON string")
        }
    }
}

public struct TokenError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
