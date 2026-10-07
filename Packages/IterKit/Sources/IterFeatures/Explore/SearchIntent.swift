import Foundation

/// What the text in Explore's search field is: a place name to look up on Apple Maps, or a request to put to the
/// ask engine (the scout). Pure and deterministic; the rule is deliberately simple and explainable:
///
/// `.ask` when the text
/// - has five or more words, or contains a question mark; or
/// - starts with a request word or phrase ("find", "show me", "where", "what", "which", "suggest", "recommend",
///   "looking for", "i want", "i'd like", "somewhere", "anywhere", "take me", "help me", "give me", "best place(s)",
///   "good place(s)", "places", "spots"); or
/// - contains a constraint marker (" within ", " hours of ", " hour of ", " minutes of ", " miles of ", " km of ",
///   " drive from ", " near me", " for sunrise", " for sunset", " for golden hour", " for blue hour", " for night",
///   " for the milky way").
///
/// Anything else is `.place` ("Portland", "Mesa Arch", "Cannon Beach Oregon"). Case, diacritics, punctuation and
/// curly apostrophes do not matter. `SearchSuggestions` uses it to rank the Apple Maps and Ask suggestions.
public enum SearchIntent: Equatable, Sendable {
    case place
    case ask

    public static let wordLimit = 5

    static let requestOpeners = [
        "find", "show me", "where", "what", "which", "suggest", "recommend", "looking for", "i want", "i'd like",
        "somewhere", "anywhere", "take me", "help me", "give me", "best place", "best places", "good place",
        "good places", "places", "spots",
    ]

    static let constraintMarkers = [
        " within ", " hours of ", " hour of ", " minutes of ", " miles of ", " km of ", " drive from ", " near me",
        " for sunrise", " for sunset", " for golden hour", " for blue hour", " for night", " for the milky way",
    ]

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
        if words.count >= wordLimit { return .ask }

        let text = words.joined(separator: " ")
        for opener in requestOpeners where text == opener || text.hasPrefix(opener + " ") { return .ask }
        let padded = " " + text + " "
        for marker in constraintMarkers {
            // A marker ending in a space must be followed by a word; one without must end at a word boundary.
            if marker.hasSuffix(" ") ? padded.contains(marker) : padded.contains(marker + " ") { return .ask }
        }
        return .place
    }
}
