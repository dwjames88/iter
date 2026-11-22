import Foundation

/// Whether the text in a search field reads like a request for the Find pipeline ("waterfalls near Lone Pine at
/// sunrise") or like a place name ("Mesa Arch"). Ported from the old `SearchIntent`. Pure; word count plays no part.
public enum FindIntent: Equatable, Sendable {
    case place
    case ask

    static let requestOpeners = [
        "show me", "where", "what", "which", "looking for", "i want", "i'd like", "somewhere", "anywhere", "take me",
        "help me", "give me", "best place", "best places", "good place", "good places", "places", "spots",
    ]
    static let verbOpeners: Set<String> = [
        "find", "show", "take", "help", "give", "suggest", "recommend", "plan", "shoot", "photograph", "see", "watch",
        "catch", "explore", "visit", "hike", "go", "get", "want", "need", "chase",
    ]
    static let keywords: Set<String> = [
        "near", "within", "for", "with", "sunrise", "sunset", "fog", "foggy", "misty", "forest", "coast", "hours", "drive",
    ]
    static let constraintMarkers = [
        "hour of", "minutes of", "miles of", "km of", "drive from", "near me", "golden hour", "blue hour", "milky way",
    ]

    public static func classify(_ query: String) -> FindIntent {
        let folded = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        if folded.contains("?") { return .ask }
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
