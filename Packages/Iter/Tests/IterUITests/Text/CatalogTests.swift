import Foundation
import Testing

/// The string catalog is plain JSON: it must parse, and carry the keys the code looks up.
struct CatalogTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { var value: String }
                var stringUnit: Unit
            }
            var comment: String?
            var extractionState: String?
            var localizations: [String: Localization]?
        }
        var sourceLanguage: String
        var version: String
        var strings: [String: Entry]
    }

    private func load() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/IterUI/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test func parsesAndHasKnownKeys() throws {
        let c = try load()
        #expect(c.sourceLanguage == "en")
        #expect(c.version == "1.0")
        #expect(c.strings.count > 100)
        for key in ["Updated just now", "Updated %@ ago", "Leave by %@", "Late by %@", "Day %lld", "Find hotels",
                    "Arrive %@ · %@ after the light starts", "^[%lld stop](inflect: true)", "Morning Blue Hour"] {
            #expect(c.strings[key] != nil, "missing \(key)")
        }
    }

    @Test func everyEntryHasEnglishValueAndComment() throws {
        let c = try load()
        for (key, entry) in c.strings {
            #expect(entry.extractionState == "extracted_with_value", "\(key)")
            #expect(entry.localizations?["en"]?.stringUnit.value == key, "\(key)")
            #expect(entry.comment?.isEmpty == false, "\(key)")
        }
    }
}
