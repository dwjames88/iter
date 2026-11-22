import Foundation

/// Name comparison for de-duplication, the literal-name rule and geocode checks. Pure. Ported from the old `DiscoveryNames`.
enum DiscoveryNames {
    /// A comparable form of a name: the words that identify it, and a kind marker when it carried one
    /// ("mount", "lake", "fall"). Two names match when their bases are equal and the markers do not disagree, so
    /// "Mount Cleveland" == "Mt. Cleveland" == "Cleveland", "Bridalveil Fall" == "Bridalveil Falls",
    /// "Lake McDonald" == "McDonald Lake", but "Lake McDonald" != "McDonald Creek".
    struct Key: Hashable, Sendable, CustomStringConvertible {
        var marker: String
        var base: String
        var description: String { marker.isEmpty ? base : marker + "|" + base }

        func matches(_ other: Key) -> Bool {
            guard !base.isEmpty, base == other.base else { return false }
            return marker.isEmpty || other.marker.isEmpty || marker == other.marker
        }
    }

    /// Lower case, no diacritics, no punctuation, no bracketed disambiguation, single spaces.
    static func normalise(_ name: String) -> String { tokens(name).joined(separator: " ") }

    static func tokens(_ name: String) -> [String] {
        var text = name
        // "Mount Cleveland (Montana)" -> "Mount Cleveland"
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var result: [String] = []
        var current = ""
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) { current.unicodeScalars.append(ch) }
            else if ch == "'" || ch == "\u{2019}" { continue }   // McDonald's == McDonalds
            else if !current.isEmpty { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Every token including those inside brackets: what a document literally says, for the literal-name rule.
    static func allTokens(_ text: String) -> [String] {
        tokens(text.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " "))
    }

    static func key(_ name: String) -> Key {
        var words = tokens(name).filter { $0 != "the" }
        var marker = ""
        let mountain: Set<String> = ["mount", "mt", "mtn"]
        if let first = words.first, mountain.contains(first), words.count > 1 {
            marker = "mount"; words.removeFirst()
        } else if let first = words.first, first == "lake", words.count > 1 {
            marker = "lake"; words.removeFirst()
        } else if let last = words.last, last == "lake", words.count > 1 {
            marker = "lake"; words.removeLast()
        } else if let last = words.last, last == "falls" || last == "fall", words.count > 1 {
            marker = "fall"; words.removeLast()
        }
        return Key(marker: marker, base: words.joined(separator: " "))
    }

    static func matches(_ a: String, _ b: String) -> Bool { key(a).matches(key(b)) }

    /// True when `name`'s normalised words occur, in order and next to each other, in `text`. This is the rule that keeps
    /// the model from naming a place the document does not mention.
    static func occursLiterally(_ name: String, in text: String) -> Bool {
        let needle = tokens(name)
        guard !needle.isEmpty else { return false }
        let hay = allTokens(text)
        guard hay.count >= needle.count else { return false }
        for i in 0...(hay.count - needle.count) where Array(hay[i..<(i + needle.count)]) == needle { return true }
        return false
    }
}
