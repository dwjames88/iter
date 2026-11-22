import Foundation
import IterAI
import IterModel
import IterSources

// Extraction (BLUEPRINT §7 step 4): names are lifted from documents, text only. The model (or the deterministic extractor)
// returns NAMES and a document number; the literal-name rule drops any name the document does not contain; the document's
// citation becomes the name's citation. Nothing here produces a coordinate.

// MARK: Model shapes

/// One place name the model found in one document.
struct ExtractedNameDTO: Codable, Sendable, Hashable {
    var name: String
    var documentIndex: Int
    var featureHint: String?
}

/// What the model returns for a chunk of documents. Strings and integers only.
struct ExtractionDTO: AIGenerable, Hashable {
    var places: [ExtractedNameDTO]

    static let maximumDocumentIndex = 39

    static var aiSchema: AISchema {
        .object(name: "PlaceNames", description: "Place names found in the numbered documents.", properties: [
            AIProperty("places", .array(of: .object(name: "PlaceName", properties: [
                AIProperty("name", .string(description: "The place name exactly as the document writes it.")),
                AIProperty("documentIndex", .integer(description: "The number of the document the name appears in.", range: 0...maximumDocumentIndex)),
                AIProperty("featureHint", .string(description: "What kind of place it is, if the document says.",
                                                   choices: FeatureKind.allCases.map(\.rawValue)), optional: true),
            ]), description: "Named places only; never a town, a person or a general region.", maxCount: 12)),
        ])
    }
}

// MARK: Chunking

struct EvidenceChunk: Sendable {
    /// Documents in the order the model sees them; `documentIndex` is the offset in this array.
    var documents: [EvidenceDocument]
    var prompt: String
}

enum EvidenceChunker {
    static let maxCharactersPerDocument = 700
    static let maxDocumentsPerChunk = 6
    /// About 1,100 tokens of evidence per chunk, leaving room for instructions and the answer in a ~4k context.
    static let maxCharactersPerChunk = 4_200

    /// Documents most relevant to the plan first: title hits count triple, geotagged documents a little more.
    static func prioritised(_ docs: [EvidenceDocument], plan: QueryPlan) -> [EvidenceDocument] {
        let terms = Set((plan.searchTerms + plan.features.flatMap(\.synonyms)).map { $0.lowercased() })
        func score(_ d: EvidenceDocument) -> Int {
            let title = d.title.lowercased(), text = d.text.lowercased()
            var s = d.coordinate == nil ? 0 : 1
            for t in terms where !t.isEmpty {
                if title.contains(t) { s += 3 }
                if text.contains(t) { s += 1 }
            }
            return s
        }
        return docs.enumerated().sorted { a, b in
            let sa = score(a.element), sb = score(b.element)
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    static func capped(_ text: String) -> String {
        text.count <= maxCharactersPerDocument ? text : String(text.prefix(maxCharactersPerDocument))
    }

    static func chunks(_ docs: [EvidenceDocument], plan: QueryPlan) -> [EvidenceChunk] {
        var out: [EvidenceChunk] = []
        var current: [EvidenceDocument] = []
        var size = 0
        func flush() {
            guard !current.isEmpty else { return }
            let body = current.enumerated().map { "[\($0.offset)] \($0.element.title)\n\(capped($0.element.text))" }.joined(separator: "\n\n")
            out.append(EvidenceChunk(documents: current, prompt: body))
            current = []; size = 0
        }
        for d in prioritised(docs, plan: plan) {
            let cost = d.title.count + min(d.text.count, maxCharactersPerDocument) + 8
            if !current.isEmpty, current.count >= maxDocumentsPerChunk || size + cost > maxCharactersPerChunk { flush() }
            current.append(d)
            size += cost
        }
        flush()
        return out
    }
}

// MARK: Rules

enum ExtractionFilter {
    /// Keeps the names that occur literally (normalised) in the document they cite, cleans them, drops repeats.
    static func accept(_ raw: [(name: String, document: EvidenceDocument, hint: FeatureKind?)], plan: QueryPlan) -> [ExtractedName] {
        var out: [ExtractedName] = []
        var seen = Set<String>()
        for item in raw {
            guard let name = CandidateVerifier.cleanName(item.name) else { continue }
            let haystack = item.document.title + " " + item.document.text
            guard DiscoveryNames.occursLiterally(name, in: haystack) else { continue }
            if !plan.features.isEmpty, let hint = item.hint, !plan.features.contains(hint) { continue }
            let key = DiscoveryNames.key(name).description
            guard seen.insert(key).inserted else { continue }
            out.append(ExtractedName(name: name, featureHint: item.hint, source: item.document.citation.source, citation: item.document.citation,
                                     snippet: snippet(for: name, in: item.document.text)))
        }
        return out
    }

    /// The sentence of the document that names the place, at most 240 characters.
    static func snippet(for name: String, in text: String) -> String? {
        let needle = name.lowercased()
        for sentence in text.split(whereSeparator: { ".!?\n".contains($0) }) where sentence.lowercased().contains(needle) {
            let s = sentence.trimmingCharacters(in: .whitespaces)
            return s.count <= 240 ? s : String(s.prefix(240))
        }
        return nil
    }
}

/// Documents about a place themselves: a geotagged Wikipedia article titled like a feature is a structured candidate.
enum DocumentCandidates {
    static func candidates(from docs: [EvidenceDocument], plan: QueryPlan, areaName: String?) -> [PlaceCandidate] {
        docs.compactMap { d in
            guard let c = d.coordinate else { return nil }
            if let areaName, DiscoveryNames.matches(areaName, d.title) { return nil }
            let kinds = plan.features.isEmpty ? FeatureKind.allCases.filter { matches(d.title, $0) } : plan.features.filter { matches(d.title, $0) }
            guard !kinds.isEmpty else { return nil }
            let snippet = ExtractionFilter.snippet(for: d.title, in: d.text) ?? String(d.text.prefix(240))
            return PlaceCandidate(name: d.title, coordinate: c, featureKinds: kinds, source: d.citation.source,
                                  externalID: d.url?.absoluteString ?? d.title, citations: [d.citation], mentionCount: 1,
                                  snippet: snippet.isEmpty ? nil : snippet)
        }
    }

    private static func matches(_ title: String, _ kind: FeatureKind) -> Bool {
        let lower = " " + DiscoveryNames.tokens(title).joined(separator: " ") + " "
        return kind.titleKeywords.contains { k in
            let w = DiscoveryNames.tokens(k).joined(separator: " ")
            return !w.isEmpty && (lower.contains(" " + w + " ") || lower.contains(" " + w + "s ") || (w.count >= 4 && lower.contains(w)))
        }
    }
}

// MARK: Deterministic extractor

enum DeterministicExtractor {
    private static let cap = #"[A-Z][\p{L}'’\-]+"#
    private static let suffixes = "Falls?|Arch|Point|Overlook|Lookout|Vista|Viewpoint|Dome|Peak|Lake|Canyon|Gorge|Glacier|Cave|Bridge|Castle|Beach|Lighthouse|Springs|Cascades?|Tarn|Spire|Butte"
    private static let prefixes = "Lake|Mount|Mt\\.?|Point|Cape|Fort|Cascade"
    private static let leadingNoise: Set<String> = [
        "the", "in", "at", "on", "from", "near", "of", "a", "an", "this", "its", "and", "but", "to", "both", "see", "visit", "hike", "walk",
        "climb", "reach", "enjoy", "take", "follow", "above", "below", "beyond", "view", "views", "popular", "famous", "also", "like",
        "such", "as", "with", "for", "by", "after", "before", "toward", "towards", "past", "via", "including", "include", "includes",
    ]

    static func names(in doc: EvidenceDocument, plan: QueryPlan, limit: Int = 8) -> [(name: String, document: EvidenceDocument, hint: FeatureKind?)] {
        var found: [String] = []
        let text = doc.title + ". " + doc.text
        let patterns = [
            "\\b((?:\(cap)\\s+){1,3}(?:\(suffixes)))\\b",
            "\\b((?:\(prefixes))\\s+\(cap)(?:\\s+\(cap))?)",
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for m in re.matches(in: text, range: range) {
                guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { continue }
                if let cleaned = strip(String(text[r])) { found.append(cleaned) }
            }
        }
        var out: [(String, EvidenceDocument, FeatureKind?)] = []
        var seen = Set<String>()
        for n in found where seen.insert(DiscoveryNames.normalise(n)).inserted {
            let hint = hint(for: n)
            if !plan.features.isEmpty, let hint, !plan.features.contains(hint) { continue }
            out.append((n, doc, hint))
            if out.count >= limit { break }
        }
        return out
    }

    static func strip(_ phrase: String) -> String? {
        var words = phrase.split(separator: " ").map(String.init)
        while let first = words.first, leadingNoise.contains(first.lowercased()) { words.removeFirst() }
        guard words.count >= 2 else { return nil }
        return words.joined(separator: " ")
    }

    static func hint(for name: String) -> FeatureKind? {
        let words = DiscoveryNames.tokens(name)
        guard let first = words.first, let last = words.last else { return nil }
        switch last {
        case "fall", "falls", "cascade", "cascades": return .waterfall
        case "arch": return .arch
        case "point", "overlook", "lookout", "vista", "viewpoint": return .viewpoint
        case "dome", "peak", "spire", "butte": return .peak
        case "lake", "tarn": return .lake
        case "canyon", "gorge": return .canyon
        case "glacier": return .glacier
        case "cave": return .cave
        case "bridge": return .bridge
        case "castle": return .castle
        case "beach": return .beach
        case "lighthouse": return .lighthouse
        case "springs": return .hotSpring
        default: break
        }
        switch first {
        case "mount", "mt", "mtn": return .peak
        case "lake": return .lake
        case "point", "cape": return .viewpoint
        case "cascade": return .waterfall
        default: return nil
        }
    }

    static func extract(from docs: [EvidenceDocument], plan: QueryPlan) -> [ExtractedName] {
        ExtractionFilter.accept(docs.flatMap { names(in: $0, plan: plan) }, plan: plan)
    }
}

// MARK: Model extractor

struct ModelExtractor: Sendable {
    var model: any LanguageModeling
    var timeout: Duration

    static let instructions = """
    You read short documents about places and list the named places they mention. Rules:
    - Copy each name exactly as the document writes it. Never invent or complete a name.
    - Give the number of the document the name appears in.
    - Only named photography-worthy places (viewpoints, waterfalls, lakes, peaks, arches, canyons, beaches, lighthouses, and similar).
    - Never give coordinates, distances or any other numbers.
    """

    /// Names from every chunk. A chunk the model fails on falls back to the deterministic extractor for its documents.
    func extract(chunks: [EvidenceChunk], plan: QueryPlan) async -> [ExtractedName] {
        var out: [ExtractedName] = []
        for chunk in chunks {
            if Task.isCancelled { break }
            let wanted = plan.features.isEmpty ? "any named place" : plan.features.map(\.pluralName).joined(separator: ", ")
            let prompt = AIPrompt(instructions: Self.instructions, prompt: "Looking for: \(wanted).\n\nDocuments:\n\n\(chunk.prompt)")
            let model = self.model
            do {
                let dto = try await withDeadline(timeout) {
                    try await model.generate(ExtractionDTO.self, prompt: prompt, options: AICallOptions(timeout: timeout, maxAttempts: 1, temperature: 0))
                }
                let raw: [(name: String, document: EvidenceDocument, hint: FeatureKind?)] = dto.places.compactMap { p in
                    guard chunk.documents.indices.contains(p.documentIndex) else { return nil }
                    return (p.name, chunk.documents[p.documentIndex], p.featureHint.flatMap(FeatureKind.init(rawValue:)))
                }
                out += ExtractionFilter.accept(raw, plan: plan)
            } catch {
                if Task.isCancelled { break }
                out += DeterministicExtractor.extract(from: chunk.documents, plan: plan)
            }
        }
        return out
    }
}
