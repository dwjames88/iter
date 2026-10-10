import Foundation

/// Name comparison for de-duplication and validation. Pure.
public enum DiscoveryNames {
    /// A comparable form of a name: the words that identify it, and a kind marker when it carried one
    /// ("mount", "lake", "fall"). Two names match when their bases are equal and the markers do not disagree,
    /// so "Mount Cleveland" == "Mt. Cleveland" == "Cleveland", "Bridalveil Fall" == "Bridalveil Falls",
    /// "Lake McDonald" == "McDonald Lake", but "Lake McDonald" != "McDonald Creek".
    public struct Key: Hashable, Sendable, CustomStringConvertible {
        public var marker: String
        public var base: String
        public var description: String { marker.isEmpty ? base : marker + "|" + base }

        public func matches(_ other: Key) -> Bool {
            guard !base.isEmpty, base == other.base else { return false }
            return marker.isEmpty || other.marker.isEmpty || marker == other.marker
        }
    }

    /// Lower case, no diacritics, no punctuation, no bracketed disambiguation, single spaces.
    public static func normalise(_ name: String) -> String {
        tokens(name).joined(separator: " ")
    }

    public static func tokens(_ name: String) -> [String] {
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

    public static func key(_ name: String) -> Key {
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

    public static func matches(_ a: String, _ b: String) -> Bool {
        key(a).matches(key(b))
    }

    /// The looser test used when checking a geocoder's answer against a requested name: the words overlap by at
    /// least half of the shorter name, or one normalised name contains the other.
    public static func looselyMatches(_ a: String, _ b: String) -> Bool {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let na = ta.joined(separator: " "), nb = tb.joined(separator: " ")
        if na.contains(nb) || nb.contains(na) { return true }
        let overlap = Set(ta).intersection(Set(tb)).count
        return Double(overlap) / Double(min(Set(ta).count, Set(tb).count)) >= 0.5
    }
}

/// Reads elevations written in the ways OpenStreetMap and Wikipedia write them.
public enum ElevationParser {
    /// Metres from "3190", "3,190 m", "3190.5", "10466 ft", "10,466 feet", "2 959 m". Nil if there is no number.
    /// A bare number is metres (the OSM convention).
    public static func metres(from text: String) -> Double? {
        let lower = text.lowercased()
        guard let match = lower.firstMatch(of: /(\d[\d,. \u{202F}\u{00A0}]*)\s*([a-z']*)/) else { return nil }
        var digits = String(match.1).replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        // A comma is a thousands separator when three digits follow it, otherwise a decimal mark.
        if digits.contains(",") {
            if digits.range(of: #",\d{3}(?!\d)"#, options: .regularExpression) != nil { digits = digits.replacingOccurrences(of: ",", with: "") }
            else { digits = digits.replacingOccurrences(of: ",", with: ".") }
        }
        digits = digits.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let value = Double(digits) else { return nil }
        let unit = String(match.2)
        switch unit {
        case "ft", "feet", "foot", "'": return value * 0.3048
        default: return value
        }
    }

    /// The first elevation in prose such as "Clements Mountain (8,765 feet (2,672 m))": a metre figure when one is
    /// given, otherwise a feet figure converted. Nil if neither appears.
    public static func metres(inProse text: String) -> Double? {
        if let m = text.firstMatch(of: /(\d[\d,]*(?:\.\d+)?)\s*(?:m|metres|meters)\b/) { return metres(from: String(m.1)) }
        if let f = text.firstMatch(of: /(\d[\d,]*(?:\.\d+)?)\s*(?:ft|feet|foot)\b/) { return metres(from: String(f.1) + " ft") }
        return nil
    }
}
