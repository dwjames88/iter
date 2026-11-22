#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// `AISchema` to Foundation Models' dynamic schema.
enum FoundationModelsSchema {
    static func generationSchema(for schema: AISchema) throws -> GenerationSchema {
        var converter = Converter()
        let root = converter.convert(schema)
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Exposed for tests.
    static func dynamicSchema(for schema: AISchema) -> DynamicGenerationSchema {
        var converter = Converter()
        return converter.convert(schema)
    }

    private struct Converter {
        /// Object names must be unique within one schema; a repeated name gets a numeric suffix.
        private var usedNames: [String: Int] = [:]
        private var choiceCount = 0

        mutating func uniqueName(_ name: String) -> String {
            let n = usedNames[name, default: 0]
            usedNames[name] = n + 1
            return n == 0 ? name : "\(name)\(n + 1)"
        }

        mutating func convert(_ schema: AISchema) -> DynamicGenerationSchema {
            switch schema {
            case .string(let description, let choices):
                if let choices, !choices.isEmpty {
                    choiceCount += 1
                    return DynamicGenerationSchema(name: uniqueName("Choice"), description: description, anyOf: choices)
                }
                return DynamicGenerationSchema(type: String.self)
            case .integer(_, let range):
                return DynamicGenerationSchema(type: Int.self, guides: range.map { [.range($0)] } ?? [])
            case .boolean:
                return DynamicGenerationSchema(type: Bool.self)
            case .array(let element, _, let maxCount):
                return DynamicGenerationSchema(arrayOf: convert(element), maximumElements: maxCount)
            case .object(let name, let description, let properties):
                let unique = uniqueName(name)
                let props = properties.map { p in
                    DynamicGenerationSchema.Property(name: p.name, description: p.description ?? Self.description(of: p.schema),
                                                     schema: convert(p.schema), isOptional: p.isOptional)
                }
                return DynamicGenerationSchema(name: unique, description: description, properties: props)
            }
        }

        static func description(of schema: AISchema) -> String? {
            switch schema {
            case .string(let d, _), .integer(let d, _), .boolean(let d), .array(_, let d, _), .object(_, let d, _): d
            }
        }
    }
}
#endif
