import Foundation
import IterModel

/// The deterministic query reader used when the on-device model is unavailable, fails or times out ("Basic search").
/// Pure: the same text always gives the same `QueryPlan`. Ported and widened from the old `SearchIntent` and
/// `FeatureAreaQuery` (one feature, one preposition) to several features, light windows, drive limits, "near me" and
/// "this area".
///
///     "viewpoints near Lone Pine, California"  -> features [viewpoint], area "Lone Pine, California"
///     "waterfalls in Yosemite within 2 hours"  -> [waterfall], "Yosemite", 120 minutes
///     "sunrise lakes near Mammoth"             -> [lake], windows [blueMorning, goldenMorning], "Mammoth"
public enum BasicQueryParser {
    /// - Parameter hasMapRegion: whether a visible map region exists, which decides "this area" and an empty area.
    public static func parse(_ text: String, hasMapRegion: Bool = false) -> QueryPlan {
        var words = tokenise(text)

        // 1. Drive time ("within 2 hours", "90 minutes from", "an hour away").
        let maxDrive = extractDriveMinutes(&words)

        // 2. Light windows ("sunrise", "golden hour", "milky way").
        let windows = extractWindows(&words)

        // 3. Date hints ("tomorrow", "this weekend", "in October").
        let dateHint = extractDateHint(&words)

        // 4. Exclusions ("not crowded", "without crowds").
        let exclude = extractExclusions(&words)

        // 5. "near me" / "around here" / "nearby".
        var mode: AreaMode?
        if removePhrase(&words, in: nearMePhrases) { mode = .nearMe }

        // 6. Split "<subject> <preposition> <area>".
        var subject = words
        var areaWords: [Word] = []
        if let split = splitAtPreposition(words) {
            subject = split.subject
            areaWords = split.area
        }

        // 7. Deictic areas ("this area", "here", "the map") and trailing time qualifiers.
        var areaText: String?
        if !areaWords.isEmpty {
            areaWords = stripLeadingArticle(areaWords)
            areaWords = stripTrailingQualifiers(areaWords)
            let joined = areaWords.map(\.raw).joined(separator: " ").trimmingCharacters(in: trimSet)
            let lower = areaWords.map(\.lower).joined(separator: " ")
            if mapAreaPhrases.contains(lower) {
                if mode == nil { mode = hasMapRegion ? .mapArea : .nearMe }
            } else if nearMeAreaPhrases.contains(lower) {
                if mode == nil { mode = .nearMe }
            } else if isNamedArea(joined) {
                areaText = joined
                mode = .named
            }
        }

        // 8. Features from the subject (and keep what is left as keywords).
        var features: [FeatureKind] = []
        subject = extractFeatures(subject, into: &features)

        // No preposition: "Yosemite waterfalls": the leading capitalised run is the area.
        if areaText == nil, mode == nil || mode == .named {
            var rest = subject
            let run = capitalisedRun(&rest)
            if !run.isEmpty {
                areaText = run.map(\.raw).joined(separator: " ").trimmingCharacters(in: trimSet)
                mode = .named
                subject = rest
            }
        }

        let keywords = keywordList(from: subject)
        let resolvedMode = mode ?? (hasMapRegion ? .mapArea : .nearMe)
        return QueryPlan(areaText: resolvedMode == .named ? areaText : nil, areaMode: resolvedMode, features: features,
                         windows: windows, dateHint: dateHint, maxDriveMinutes: maxDrive, keywords: keywords, exclude: exclude)
    }

    // MARK: Words

    struct Word: Hashable {
        var raw: String
        /// Lower case, punctuation and curly quotes removed.
        var lower: String
    }

    private static let trimSet = CharacterSet(charactersIn: " .,;:!?\"'()")

    static func tokenise(_ text: String) -> [Word] {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .map { Word(raw: String($0), lower: clean(String($0))) }
            .filter { !$0.raw.isEmpty }
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: trimSet).lowercased()
    }

    /// Removes the first run of words equal to one of `phrases` (each a lower-case space-separated phrase), returning whether one was found.
    @discardableResult
    private static func removePhrase(_ words: inout [Word], in phrases: [String]) -> Bool {
        let sorted = phrases.sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }
        for phrase in sorted {
            let parts = phrase.split(separator: " ").map(String.init)
            if let i = indexOf(parts, in: words) {
                words.removeSubrange(i..<(i + parts.count))
                return true
            }
        }
        return false
    }

    private static func indexOf(_ parts: [String], in words: [Word]) -> Int? {
        guard !parts.isEmpty, words.count >= parts.count else { return nil }
        for i in 0...(words.count - parts.count) where (0..<parts.count).allSatisfy({ words[i + $0].lower == parts[$0] }) { return i }
        return nil
    }

    // MARK: Drive time

    private static let numberWords: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                                         "half": 0.5, "ninety": 90, "sixty": 60, "thirty": 30, "forty-five": 45, "fortyfive": 45]

    private static func minutes(from number: String, unit: String) -> Int? {
        let n = Double(number) ?? numberWords[number]
        guard let n, n > 0 else { return nil }
        let perUnit: Double = unit.hasPrefix("h") ? 60 : 1
        let value = Int((n * perUnit).rounded())
        return value > 0 && value <= 24 * 60 ? value : nil
    }

    private static func extractDriveMinutes(_ words: inout [Word]) -> Int? {
        let units: Set<String> = ["hour", "hours", "hr", "hrs", "h", "minute", "minutes", "min", "mins"]
        var i = 0
        while i < words.count {
            var j = i
            let isWithin = words[i].lower == "within" || (words[i].lower == "under") || (words[i].lower == "less" && i + 1 < words.count && words[i + 1].lower == "than")
            if isWithin { j = words[i].lower == "less" ? i + 2 : i + 1 }
            // "half an hour"
            if j + 2 < words.count, words[j].lower == "half", words[j + 1].lower == "an", units.contains(words[j + 2].lower) {
                var end = j + 3
                end = skipDriveTail(words, end)
                words.removeSubrange(i..<end)
                return 30
            }
            if j + 1 < words.count, let n = Optional(words[j].lower), units.contains(words[j + 1].lower) {
                // A bare "2 hours" needs "within" or a drive word after it; "a" and "an" always need one of those.
                var end = j + 2
                let tail = skipDriveTail(words, end)
                let hasDriveWord = tail != end
                if isWithin || hasDriveWord, let m = minutes(from: n, unit: words[j + 1].lower) {
                    end = tail
                    words.removeSubrange(i..<end)
                    return m
                }
            }
            // "2h30" style is not supported; "2-hour drive" is.
            if let hyphen = words[i].lower.firstMatch(of: /^(\d+(?:\.\d+)?)-(hour|hours|minute|minutes|min|hr)$/),
               i + 1 < words.count, ["drive", "radius", "away", "trip"].contains(words[i + 1].lower),
               let m = minutes(from: String(hyphen.1), unit: String(hyphen.2)) {
                words.removeSubrange(i..<(i + 2))
                return m
            }
            i += 1
        }
        return nil
    }

    /// Skips "drive", "away", "of driving", "drive from" after a duration; returns the new end index.
    private static func skipDriveTail(_ words: [Word], _ start: Int) -> Int {
        var k = start
        let tail: Set<String> = ["drive", "driving", "away", "of", "radius"]
        while k < words.count, tail.contains(words[k].lower) { k += 1 }
        return k
    }

    // MARK: Windows

    private static let windowPhrases: [(phrase: String, windows: [LightWindowKind])] = [
        ("golden hour", [.goldenMorning, .goldenEvening]),
        ("blue hour", [.blueMorning, .blueEvening]),
        ("sunrise", [.blueMorning, .goldenMorning]), ("sunrises", [.blueMorning, .goldenMorning]),
        ("sunset", [.goldenEvening, .blueEvening]), ("sunsets", [.goldenEvening, .blueEvening]),
        ("dawn", [.blueMorning, .goldenMorning]), ("dusk", [.goldenEvening, .blueEvening]), ("twilight", [.blueEvening]),
        ("milky way", [.night]), ("night sky", [.night]), ("astrophotography", [.night]), ("stargazing", [.night]),
        ("star trails", [.night]), ("at night", [.night]), ("night", [.night]),
    ]

    private static func extractWindows(_ words: inout [Word]) -> [LightWindowKind] {
        var found: Set<LightWindowKind> = []
        for (phrase, windows) in windowPhrases.sorted(by: { $0.phrase.split(separator: " ").count > $1.phrase.split(separator: " ").count }) {
            let parts = phrase.split(separator: " ").map(String.init)
            while let i = indexOf(parts, in: words) {
                // "tonight" is a date, not a window; "night" inside "night sky" is consumed by the longer phrase first.
                var start = i
                if start > 0, ["for", "at", "during", "in", "the"].contains(words[start - 1].lower) { start -= 1 }
                if start > 0, ["for", "at", "during", "in"].contains(words[start - 1].lower), words[start].lower == "the" { start -= 1 }
                words.removeSubrange(start..<(i + parts.count))
                found.formUnion(windows)
            }
        }
        return LightWindowKind.allCases.filter(found.contains)
    }

    // MARK: Dates

    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                                 "november", "december"]
    private static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    private static func extractDateHint(_ words: inout [Word]) -> String? {
        let fixed = ["this weekend", "next weekend", "this evening", "this morning", "tomorrow morning", "tomorrow night",
                     "tomorrow evening", "next week", "this week", "tonight", "tomorrow", "today"]
        for phrase in fixed.sorted(by: { $0.split(separator: " ").count > $1.split(separator: " ").count }) {
            let parts = phrase.split(separator: " ").map(String.init)
            if let i = indexOf(parts, in: words) {
                words.removeSubrange(i..<(i + parts.count))
                return phrase
            }
        }
        for (i, w) in words.enumerated() {
            if weekdays.contains(w.lower) {
                let hasOn = i > 0 && (words[i - 1].lower == "on" || words[i - 1].lower == "this" || words[i - 1].lower == "next")
                let start = hasOn ? i - 1 : i
                let hint = words[start...i].map(\.lower).joined(separator: " ")
                words.removeSubrange(start...i)
                return hint
            }
            if months.contains(w.lower), i > 0, ["in", "during", "this", "next", "late", "early", "mid"].contains(words[i - 1].lower) {
                words.removeSubrange((i - 1)...i)
                return w.lower
            }
        }
        return nil
    }

    // MARK: Exclusions

    private static func extractExclusions(_ words: inout [Word]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < words.count {
            if ["not", "without", "except", "excluding", "no"].contains(words[i].lower), i + 1 < words.count {
                var end = i + 2
                var term = words[i + 1].lower
                // "without crowds" / "not too crowded": drop a softener
                if ["too", "very", "so"].contains(term), i + 2 < words.count { term = words[i + 2].lower; end = i + 3 }
                if !term.isEmpty, !stopwords.contains(term) { out.append(term) }
                words.removeSubrange(i..<end)
                continue
            }
            i += 1
        }
        return Array(out.prefix(6))
    }

    // MARK: Area

    private static let nearMePhrases = ["near me", "around me", "close to me", "closest to me", "next to me", "around here", "near here",
                                        "near by", "nearby", "close by", "around my location", "near my location", "where i am"]
    private static let nearMeAreaPhrases: Set<String> = ["me", "my location", "my area", "my current location", "where i am", "where we are"]
    private static let mapAreaPhrases: Set<String> = ["here", "this area", "the area", "this map", "the map", "map area", "the map area",
                                                      "this region", "this place", "view", "in view", "the visible map", "visible map"]

    private static let prepositions: Set<String> = ["in", "near", "around", "at", "by", "along", "of", "on", "across", "throughout",
                                                    "inside", "from", "within", "outside", "close", "next", "to", "around"]

    /// First preposition run followed by something: everything before is the subject, after is the area.
    private static func splitAtPreposition(_ words: [Word]) -> (subject: [Word], area: [Word])? {
        guard let start = words.firstIndex(where: { prepositions.contains($0.lower) && $0.lower != "to" }) else { return nil }
        var end = start
        while end + 1 < words.count, prepositions.contains(words[end + 1].lower) { end += 1 }
        guard end + 1 < words.count else {
            // A dangling preposition: drop it.
            return (Array(words[..<start]), [])
        }
        return (Array(words[..<start]), Array(words[(end + 1)...]))
    }

    private static func stripLeadingArticle(_ words: [Word]) -> [Word] {
        if words.count > 1, words[0].lower == "the" { return Array(words.dropFirst()) }
        return words
    }

    private static let qualifiers: [String] = [
        "for sunrise", "for sunset", "at sunrise", "at sunset", "at golden hour", "at blue hour", "for photography",
        "for photos", "for landscape photography", "to shoot", "to photograph", "tonight", "tomorrow", "today", "this weekend",
    ]

    private static func stripTrailingQualifiers(_ words: [Word]) -> [Word] {
        var current = words
        var changed = true
        while changed, !current.isEmpty {
            changed = false
            for q in qualifiers {
                let parts = q.split(separator: " ").map(String.init)
                if current.count > parts.count, current.suffix(parts.count).map(\.lower) == parts {
                    current.removeLast(parts.count)
                    changed = true
                    break
                }
            }
        }
        return current
    }

    private static func isNamedArea(_ area: String) -> Bool {
        guard area.count >= 2, area.count <= 80, area.contains(where: \.isLetter) else { return false }
        let lower = area.lowercased()
        if ["anywhere", "everywhere", "the world", "nearby", "there"].contains(lower) { return false }
        return true
    }

    /// The leading run of capitalised words ("Yosemite Valley"), removed from `words`; used when there is no preposition.
    private static func capitalisedRun(_ words: inout [Word]) -> [Word] {
        var run: [Word] = []
        var start: Int?
        for (i, w) in words.enumerated() {
            let first = w.raw.unicodeScalars.first
            let isCap = first.map { CharacterSet.uppercaseLetters.contains($0) } ?? false
            if isCap, !stopwords.contains(w.lower), !wordIsGeneric(w.lower) {
                if start == nil { start = i }
                run.append(w)
            } else if start != nil {
                break
            }
        }
        guard let start, !run.isEmpty else { return [] }
        words.removeSubrange(start..<(start + run.count))
        return run
    }

    private static func wordIsGeneric(_ w: String) -> Bool { genericWords.contains(w) }
    private static let genericWords: Set<String> = ["best", "top", "good", "great", "find", "show", "places", "spots", "photo", "photos"]

    // MARK: Features and keywords

    /// Removes every feature phrase from `words` (two-word phrases first), appending kinds in order of appearance.
    private static func extractFeatures(_ words: [Word], into features: inout [FeatureKind]) -> [Word] {
        var out: [Word] = []
        var i = 0
        while i < words.count {
            var matched = false
            for length in [2, 1] where i + length <= words.count {
                let phrase = words[i..<(i + length)].map(\.lower).joined(separator: " ")
                if let kind = FeatureKind.from(phrase: phrase) {
                    if !features.contains(kind) { features.append(kind) }
                    i += length
                    matched = true
                    break
                }
            }
            if !matched { out.append(words[i]); i += 1 }
        }
        return out
    }

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "in", "on", "at", "to", "for", "with", "from", "by", "near", "around", "within", "that",
        "which", "are", "is", "be", "i", "me", "my", "we", "us", "our", "you", "some", "any", "all", "best", "top", "good", "great",
        "find", "show", "give", "get", "want", "need", "looking", "look", "spots", "spot", "places", "place", "locations", "location",
        "photo", "photos", "photograph", "photography", "shoot", "shooting", "take", "go", "visit", "see", "where", "what", "can",
        "please", "like", "would", "should", "about", "good", "nice", "cool", "really", "more", "most", "also", "there", "here", "it",
        "has", "have", "do", "does", "this", "these", "those", "over", "up", "out", "into", "around", "so", "too", "very", "than", "less",
    ]

    private static func keywordList(from words: [Word]) -> [String] {
        var out: [String] = []
        for w in words {
            let k = w.lower
            guard k.count >= 3, !stopwords.contains(k), k.contains(where: \.isLetter), !out.contains(k) else { continue }
            out.append(k)
        }
        return Array(out.prefix(QueryPlan.maximumKeywords))
    }
}
