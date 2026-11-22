import Foundation
import FoundationModels
import IterCore

/// Pulls place names out of Reddit and Google text with the on-device model.
///
/// The model may only copy names that appear in the texts: its answer is filtered afterwards, and a name that does
/// not literally occur in the texts (ignoring case and accents) is dropped. It never supplies a coordinate.
public struct FoundationModelsDiscoveryExtractor: DiscoveryExtracting {
    /// The on-device window is 4,096 tokens; this much text plus instructions and answer fits with room to spare.
    public static let maximumTextCharacters = 2_500
    public static let maximumNames = 12

    @Generable
    struct Names {
        @Guide(description: "Specific places named in the texts, at most 12. Empty if none.", .maximumCount(12))
        var places: [Name]
    }

    @Generable
    struct Name {
        @Guide(description: "The place's name copied exactly as written in the texts.")
        var name: String
        @Guide(description: "One short sentence on why a photographer might like it, using only what the texts say.")
        var why: String
    }

    static let instructions = """
        You pull place names out of texts for a landscape photographer. \
        Only output names of specific, real places that appear word for word in the texts. \
        Never add a place from your own memory. Skip people, generic words and the search area itself.
        """

    public init() {}

    public func extractPlaces(from texts: [DiscoveryText], area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        guard !texts.isEmpty else { return [] }
        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable: throw DiscoveryError.unavailable("Apple Intelligence unavailable")
        }
        let prompt = Self.prompt(texts: texts, area: area, feature: feature, settings: settings)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let session = LanguageModelSession(model: .default, instructions: Self.instructions)
                let options = attempt == 1 ? GenerationOptions(maximumResponseTokens: 600) : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 600)
                let names = try await session.respond(to: prompt, generating: Names.self, options: options).content
                return DiscoveryExtractionFilter.apply(candidates: names.places.map { ($0.name, $0.why) }, texts: texts, area: area,
                                                       feature: feature, maximum: Self.maximumNames)
            } catch {
                guard let mapped = ScoutError.map(error) else { throw CancellationError() }
                if attempt < 3, case .failed = mapped { continue }
                switch mapped {
                case .guardrail: throw DiscoveryError.unavailable("Blocked by the model")
                case .contextTooLong: throw DiscoveryError.unavailable("Too much text")
                case .unavailable: throw DiscoveryError.unavailable("Apple Intelligence unavailable")
                default: throw DiscoveryError.unavailable("Extraction failed")
                }
            }
        }
    }

    /// The user's preferences, the request, then the texts, highest-scored first, clipped to `maximumTextCharacters`.
    static func prompt(texts: [DiscoveryText], area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings) -> String {
        let ordered = texts.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
        var body = ""
        for text in ordered {
            var line = "- " + text.title.replacingOccurrences(of: "\n", with: " ")
            let detail = text.body.replacingOccurrences(of: "\n", with: " ").prefix(220)
            if !detail.isEmpty { line += ": " + detail }
            line += "\n"
            if body.count + line.count > maximumTextCharacters { break }
            body += line
        }
        let looking = feature.map { "Looking for: \($0.pluralName)\n" } ?? ""
        let instructions = "Area: \(area.name ?? "this area")\n\(looking)List the places named in these texts.\n\nTexts:\n\(body)"
        return DiscoveryPrompt.prefixed(instructions, settings: settings)
    }
}

/// Keeps only what the texts support. Pure, so it is tested without the model.
public enum DiscoveryExtractionFilter {
    private static let generic: Set<String> = ["park", "national park", "trail", "lake", "mountain", "mountains", "peak", "view", "sunrise", "sunset", "photo", "photos"]

    /// Drops names that do not appear in the texts, are generic or are the area itself; de-duplicates; and fills in
    /// sources, links and a mention count from the texts that contain each name (1 per text, plus 1 per 100 upvotes, up to 4).
    public static func apply(candidates: [(name: String, why: String)], texts: [DiscoveryText], area: DiscoveryArea, feature: FeatureKind?, maximum: Int) -> [DiscoveredPlace] {
        let haystacks = texts.map { (text: $0, normalised: " " + DiscoveryNames.normalise($0.title + " " + $0.body) + " ") }
        let areaName = DiscoveryNames.normalise(area.name ?? "")
        var seen = Set<String>()
        var result: [DiscoveredPlace] = []
        for candidate in candidates {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalised = DiscoveryNames.normalise(name)
            guard name.count >= 2, name.count <= 80, !normalised.isEmpty, !generic.contains(normalised),
                  normalised != areaName, normalised != areaName + " national park", seen.insert(normalised).inserted else { continue }
            let hits = haystacks.filter { $0.normalised.contains(" " + normalised + " ") }
            guard !hits.isEmpty else { continue }
            let mentions = hits.reduce(0) { $0 + 1 + min(4, $1.text.score / 100) }
            var links: [URL] = []
            for hit in hits { if let url = hit.text.url, !links.contains(url), links.count < 3 { links.append(url) } }
            let why = candidate.why.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(DiscoveredPlace(name: name, feature: feature, sources: Set(hits.map(\.text.source)), links: links,
                                          mentions: mentions, why: why.isEmpty ? nil : why))
            if result.count >= maximum { break }
        }
        return result
    }
}
