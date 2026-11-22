import Foundation

// Pure checks on an `AISchema`: that a JSON answer conforms to it (used before decoding, by the on-device adapter and
// by the fake, so a fake answering outside the schema fails exactly like the real model would), and that a schema never
// mentions coordinates.

/// A parsed JSON value, with integers kept apart from other numbers so the validator can reject `1.5` for an integer.
enum AIJSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AIJSONValue])
    case object([String: AIJSONValue])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([AIJSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: AIJSONValue].self)) }
    }

    var kindName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .int: "integer"
        case .double: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }
}

public enum AISchemaValidation {
    /// Checks that `json` parses and conforms to `schema`. Unknown object keys are rejected (the real model cannot
    /// produce them). Throws `AIError.decoding` listing the first problem.
    public static func validate(json: Data, against schema: AISchema) throws(AIError) {
        let value: AIJSONValue
        do { value = try JSONDecoder().decode(AIJSONValue.self, from: json) }
        catch { throw .decoding("not valid JSON: \(error.localizedDescription)") }
        if let problem = firstProblem(in: value, against: schema, path: "$") { throw .decoding(problem) }
    }

    /// The problems found, empty when `json` conforms. Convenience for tests.
    public static func problems(json: Data, against schema: AISchema) -> [String] {
        do { try validate(json: json, against: schema); return [] }
        catch { return [error.description] }
    }

    /// Validates against `Output.aiSchema` and decodes. The single decode path for every adapter.
    static func decode<Output: AIGenerable>(_ type: Output.Type, from json: Data) throws(AIError) -> Output {
        try validate(json: json, against: Output.aiSchema)
        do { return try JSONDecoder().decode(Output.self, from: json) }
        catch { throw .decoding("\(Output.self): \(error.localizedDescription)") }
    }

    static func firstProblem(in value: AIJSONValue, against schema: AISchema, path: String) -> String? {
        switch schema {
        case .string(_, let choices):
            guard case .string(let s) = value else { return "\(path): expected string, got \(value.kindName)" }
            if let choices, !choices.contains(s) { return "\(path): \"\(s)\" is not one of \(choices)" }
        case .integer(_, let range):
            guard case .int(let n) = value else { return "\(path): expected integer, got \(value.kindName)" }
            if let range, !range.contains(n) { return "\(path): \(n) outside \(range)" }
        case .boolean:
            guard case .bool = value else { return "\(path): expected boolean, got \(value.kindName)" }
        case .array(let element, _, let maxCount):
            guard case .array(let items) = value else { return "\(path): expected array, got \(value.kindName)" }
            if let maxCount, items.count > maxCount { return "\(path): \(items.count) items, at most \(maxCount)" }
            for (i, item) in items.enumerated() {
                if let p = firstProblem(in: item, against: element, path: "\(path)[\(i)]") { return p }
            }
        case .object(let name, _, let properties):
            guard case .object(let dict) = value else { return "\(path): expected object \(name), got \(value.kindName)" }
            let known = Set(properties.map(\.name))
            if let extra = dict.keys.filter({ !known.contains($0) }).sorted().first { return "\(path): unexpected property \"\(extra)\"" }
            for property in properties {
                let child = dict[property.name]
                if child == nil || child == .null {
                    if property.isOptional { continue }
                    return "\(path): missing required property \"\(property.name)\""
                }
                if let child, let p = firstProblem(in: child, against: property.schema, path: "\(path).\(property.name)") { return p }
            }
        }
        return nil
    }
}

extension AISchema {
    /// True when any object name or property name reads like a coordinate (`lat`, `latitude`, `lon`, `lng`,
    /// `longitude`, `coordinate(s)`, `coord(s)`). Matches whole words after splitting camelCase, snake_case and
    /// kebab-case, so "template" does not match. Discovery's tests assert this is false for every schema it uses.
    public var mentionsCoordinates: Bool {
        switch self {
        case .string, .integer, .boolean: false
        case .array(let element, _, _): element.mentionsCoordinates
        case .object(let name, _, let properties):
            Self.looksLikeCoordinate(name) || properties.contains { Self.looksLikeCoordinate($0.name) || $0.schema.mentionsCoordinates }
        }
    }

    private static let coordinateWords: Set<String> = [
        "lat", "latitude", "lon", "lng", "longitude", "coordinate", "coordinates", "coord", "coords", "latlng", "latlon",
    ]

    static func looksLikeCoordinate(_ identifier: String) -> Bool {
        var words: [String] = []
        var current = ""
        var previousLower = false
        for ch in identifier {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase && previousLower { words.append(current); current = "" }
                current.append(ch)
                previousLower = ch.isLowercase
            } else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousLower = false
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.contains { coordinateWords.contains($0.lowercased()) }
    }
}
