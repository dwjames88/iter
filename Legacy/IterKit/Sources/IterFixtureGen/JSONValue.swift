import Foundation

/// A tiny JSON tree so dumps can distinguish an absent key from an explicit null, and embed a decoded document.
enum J: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([J])
    case object([String: J])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([J].self) { self = .array(v) }
        else { self = .object(try c.decode([String: J].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// A Date as `timeIntervalSinceReferenceDate`, full Double precision.
    static func date(_ d: Date) -> J { .double(d.timeIntervalSinceReferenceDate) }
    static func date(_ d: Date?) -> J { d.map { .double($0.timeIntervalSinceReferenceDate) } ?? .null }
    static func uuid(_ u: UUID) -> J { .string(u.uuidString.uppercased()) }
    static func uuid(_ u: UUID?) -> J { u.map { .string($0.uuidString.uppercased()) } ?? .null }
    static func uuids(_ u: [UUID]) -> J { .array(u.map { .string($0.uuidString.uppercased()) }) }
    static func sortedUUIDs(_ u: [UUID]) -> J { .array(u.map { $0.uuidString.uppercased() }.sorted().map { .string($0) }) }
    static func opt(_ v: Double?) -> J { v.map { .double($0) } ?? .null }
    static func opt(_ v: Int?) -> J { v.map { .int($0) } ?? .null }
    static func opt(_ v: String?) -> J { v.map { .string($0) } ?? .null }

    /// Dump files: sorted keys, pretty, a trailing newline.
    static func encodeData(_ value: J) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(value) + Data("\n".utf8)
    }

    /// Exactly the options and bytes `TripDocument.encoded()` uses (no trailing newline).
    static func encodeDocumentData(_ value: J) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(value)
    }
}
