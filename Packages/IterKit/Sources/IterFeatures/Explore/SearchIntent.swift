import Foundation
import IterCore

/// Whether the text in Explore's search field reads like a request for the ask engine (the scout), or like a place
/// name. Return always runs the local search (curated places and Apple Maps); this only decides whether an "Ask Iter"
/// suggestion is offered beside it. Pure and deterministic; word count plays no part.
///
/// `.ask` when the text
/// - contains a question mark; or
/// - starts with a request phrase ("show me", "where", "what", "which", "looking for", "i want", "i'd like",
///   "somewhere", "anywhere", "best place(s)", "good place(s)", "places", "spots", ...); or
/// - starts with a request verb ("find", "show", "take", "help", "give", "suggest", "recommend", "plan", "shoot",
///   "photograph", "see", "watch", "catch", "explore", "visit", "hike", "go", "get", "want", "need", "chase", ...); or
/// - contains, as whole words anywhere, one of "near", "within", "for", "with", "sunrise", "sunset", "fog", "foggy",
///   "misty", "forest", "coast", "hours", "drive", "golden hour", "blue hour", "milky way", or a constraint marker
///   (" hour of ", " minutes of ", " miles of ", " km of ", " drive from ", " near me", ...).
///
/// Matching is on whole words, so "Nearby Lake", "Fortress Rock", "Withrow", "Finder Point", "Whatcom Falls" and
/// "Spotsylvania" are places. Anything else is `.place` ("Portland", "Mesa Arch", "Great Smoky Mountains National
/// Park"). Some place names do carry a keyword ("Hoh Rain Forest"); that only adds the Ask row, and the local search
/// still runs first. Case, diacritics, punctuation and curly apostrophes do not matter.
public enum SearchIntent: Equatable, Sendable {
    case place
    case ask

    static let requestOpeners = [
        "show me", "where", "what", "which", "looking for", "i want", "i'd like", "somewhere", "anywhere", "take me",
        "help me", "give me", "best place", "best places", "good place", "good places", "places", "spots",
    ]

    /// Imperative and request verbs; only the first word of the text is checked.
    static let verbOpeners: Set<String> = [
        "find", "show", "take", "help", "give", "suggest", "recommend", "plan", "shoot", "photograph", "see", "watch",
        "catch", "explore", "visit", "hike", "go", "get", "want", "need", "chase",
    ]

    /// Single words that mark a request wherever they stand.
    static let keywords: Set<String> = [
        "near", "within", "for", "with", "sunrise", "sunset", "fog", "foggy", "misty", "forest", "coast", "hours",
        "drive",
    ]

    /// Phrases that mark a request wherever they stand (matched on whole words).
    static let constraintMarkers = [
        "hour of", "minutes of", "miles of", "km of", "drive from", "near me", "golden hour", "blue hour", "milky way",
    ]

    /// "mountains in Glacier National Park" as a feature and an area; nil for any other text. Independent of
    /// `classify`: such a text may also read like a request (it can show both rows).
    public static func featureQuery(_ query: String) -> FeatureAreaQuery? {
        FeatureAreaQuery.parse(query)
    }

    public static func classify(_ query: String) -> SearchIntent {
        let folded = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        if folded.contains("?") { return .ask }

        // Words and apostrophes only; everything else separates.
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted
        let words = folded.components(separatedBy: separators).filter { !$0.isEmpty }.map { $0.lowercased() }
        guard !words.isEmpty else { return .place }
        if verbOpeners.contains(words[0]) { return .ask }
        if words.contains(where: keywords.contains) { return .ask }

        let text = words.joined(separator: " ")
        for opener in requestOpeners where text == opener || text.hasPrefix(opener + " ") { return .ask }
        let padded = " " + text + " "
        for marker in constraintMarkers where padded.contains(" " + marker + " ") { return .ask }
        return .place
    }
}
