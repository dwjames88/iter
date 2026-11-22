import Foundation
import IterAI
import IterModel

// The model's view of a query. Strings, integers and arrays of them only: it cannot express a coordinate.

/// What the model returns for a query. Mapped to `QueryPlan` by `QueryPlanValidator`, which drops anything unknown.
struct QueryPlanDTO: AIGenerable, Hashable {
    var areaMode: String
    var areaText: String?
    var features: [String]
    var windows: [String]
    var dateHint: String?
    var maxDriveMinutes: Int?
    var keywords: [String]
    var exclude: [String]

    static var aiSchema: AISchema {
        .object(name: "QueryPlan", description: "What a photographer wants to find.", properties: [
            AIProperty("areaMode", .string(description: "named when the user names a place, nearMe for around the user, mapArea for the visible map.",
                                           choices: AreaMode.allCases.map(\.rawValue))),
            AIProperty("areaText", .string(description: "The place the user named, copied from their words. Omit unless areaMode is named."), optional: true),
            AIProperty("features", .array(of: .string(choices: FeatureKind.allCases.map(\.rawValue)),
                                          description: "The kinds of place wanted.", maxCount: 6)),
            AIProperty("windows", .array(of: .string(choices: LightWindowKind.allCases.map(\.rawValue)),
                                         description: "The light the user wants.", maxCount: 5)),
            AIProperty("dateHint", .string(description: "A date phrase the user used, such as 'this weekend'."), optional: true),
            AIProperty("maxDriveMinutes", .integer(description: "Longest drive the user accepts, in minutes.", range: 5...720), optional: true),
            AIProperty("keywords", .array(of: .string(), description: "Up to six extra search words from the user's text.", maxCount: QueryPlan.maximumKeywords)),
            AIProperty("exclude", .array(of: .string(), description: "Things the user does not want.", maxCount: 6)),
        ])
    }
}

enum QueryPlanValidator {
    /// The plan the DTO describes, with unknown choices dropped and lists clamped. `basic` (the deterministic reading of the
    /// same text) fills what the model leaves out or gets wrong: an area name that is not in the user's words, a missing
    /// drive time.
    static func plan(from dto: QueryPlanDTO, userText: String, basic: QueryPlan) -> QueryPlan {
        var mode = AreaMode(rawValue: dto.areaMode) ?? basic.areaMode
        var areaText = dto.areaText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if mode == .named {
            // The area must be words the user wrote; otherwise take the deterministic reading.
            if let a = areaText, DiscoveryNames.occursLiterally(a, in: userText) {
                // keep
            } else if let b = basic.areaText {
                areaText = b
            } else {
                areaText = nil
                mode = basic.areaMode == .named ? .named : basic.areaMode
            }
        } else {
            areaText = nil
        }
        let features = unique(dto.features.compactMap(FeatureKind.init(rawValue:)))
        let windows = unique(dto.windows.compactMap(LightWindowKind.init(rawValue:)))
        // A drive limit only when the user spoke of one: the model must not invent a radius (live run 2026-11-22: it
        // added 60 minutes to "waterfalls in Yosemite National Park", which replaced the park's own area).
        let drive = basic.maxDriveMinutes
            ?? (QueryPlanner.mentionsDriveTime(userText) ? dto.maxDriveMinutes.map { min(720, max(5, $0)) } : nil)
        return QueryPlan(areaText: mode == .named ? areaText : nil, areaMode: mode, features: features.isEmpty ? basic.features : features,
                         windows: windows, dateHint: dto.dateHint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { String($0.prefix(40)) },
                         maxDriveMinutes: drive, keywords: cleanWords(dto.keywords), exclude: cleanWords(dto.exclude))
    }

    /// Trimmed, de-duplicated, at most six, and never a number that could pass as a coordinate.
    static func cleanWords(_ words: [String]) -> [String] {
        var out: [String] = []
        for w in words {
            let t = w.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard t.count >= 2, t.count <= 40, t.contains(where: \.isLetter), t.firstMatch(of: /\d+[.,]\d+/) == nil, !out.contains(t) else { continue }
            out.append(t)
        }
        return Array(out.prefix(QueryPlan.maximumKeywords))
    }

    private static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Reads a query with the model when it is there, and with `BasicQueryParser` when it is not or fails.
struct QueryPlanner: Sendable {
    var model: (any LanguageModeling)?
    var timeout: Duration

    /// True when the words talk about travel time or distance ("within 2 hours", "a short drive", "45 min").
    static func mentionsDriveTime(_ text: String) -> Bool {
        let t = text.lowercased()
        let words = ["hour", "hours", "hr", "hrs", "minute", "minutes", "min", "mins", "drive", "driving", "miles", "km"]
        let tokens = Set(t.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !tokens.isDisjoint(with: words)
    }

    static let instructions = """
    You turn a photographer's search into a plan. Fields: areaMode, areaText, features, windows, dateHint, maxDriveMinutes, \
    keywords, exclude. Rules:
    - areaText is a place name copied from the user's words. If the user said "near me" use nearMe; if "this area" or "here" use mapArea.
    - features and windows must be chosen from the allowed values only.
    - Never output coordinates, latitudes, longitudes or distances. Only a drive time in minutes if the user gave one.
    """

    func plan(for text: String, hasMapRegion: Bool) async -> (QueryPlan, PlanOrigin) {
        let basic = BasicQueryParser.parse(text, hasMapRegion: hasMapRegion)
        guard let model else { return (basic, .basicNoModel) }
        switch await model.availability() {
        case .unavailable(let reason): return (basic, .basic(reason: reason))
        case .available: break
        }
        let prompt = AIPrompt(instructions: Self.instructions, prompt: "Search: \(text)\nA map region is \(hasMapRegion ? "visible" : "not visible").")
        let limit = timeout
        do {
            let dto = try await withDeadline(limit) {
                try await model.generate(QueryPlanDTO.self, prompt: prompt, options: AICallOptions(timeout: limit, maxAttempts: 1, temperature: 0))
            }
            return (QueryPlanValidator.plan(from: dto, userText: text, basic: basic), .ai)
        } catch let e as AIError {
            if case .unavailable(let r) = e { return (basic, .basic(reason: r)) }
            return (basic, .basic(reason: nil))
        } catch {
            return (basic, .basic(reason: nil))
        }
    }
}
