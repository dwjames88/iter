import Foundation

/// Reads a coordinate from what people paste: "38.5, -109.5", "38.5 -109.5", "38.5°N 109.5°W", "N 38.5 W 109.5",
/// degrees-minutes-seconds ("38°30′00″N 109°30′00″W"), or an Apple Maps link (`?ll=`, `?sll=`, `?q=lat,lon`, or the newer
/// `/place?coordinate=lat,lon`). A pure function: nothing is looked up, nothing is guessed. Out-of-range values give nil.
public enum CoordinateParser {
    public enum Axis: Sendable { case latitude, longitude

        public var limit: Double { self == .latitude ? 90 : 180 }
    }

    /// A latitude and longitude from free text or an Apple Maps link; nil when it is neither.
    public static func parse(_ text: String) -> Coordinate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = linkCoordinate(trimmed) { return url }
        return parsePair(trimmed)
    }

    /// One degrees value for a single field: "38.5", "-109.5", "109.5 W", "38°30′N". Checks the range for the axis.
    public static func parseDegrees(_ text: String, axis: Axis) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = scan(trimmed, lettersFirst: trimmed.first?.isLetter == true)
        guard let components, components.count == 1, let value = components[0].signedValue else { return nil }
        if let hemisphere = components[0].hemisphere, (axis == .latitude) != "NS".contains(hemisphere) { return nil }
        return abs(value) <= axis.limit ? value : nil
    }

    // MARK: Pairs

    private struct Component {
        var value: Double
        var negative: Bool
        var hemisphere: Character?
        var signedValue: Double? {
            let hemisphereNegative = hemisphere.map { "SW".contains($0) } ?? false
            guard !(negative && hemisphereNegative) || value == 0 else { return nil }
            return (negative || hemisphereNegative) ? -value : value
        }
    }

    private static func parsePair(_ text: String) -> Coordinate? {
        guard let parts = scan(text, lettersFirst: text.first?.isLetter == true), parts.count == 2 else { return nil }
        guard let a = parts[0].signedValue, let b = parts[1].signedValue else { return nil }
        let ha = parts[0].hemisphere, hb = parts[1].hemisphere
        let (lat, lon): (Double, Double)
        switch (ha, hb) {
        case (nil, nil): (lat, lon) = (a, b)
        case let (x?, y?):
            let xIsLat = "NS".contains(x), yIsLat = "NS".contains(y)
            guard xIsLat != yIsLat else { return nil }
            (lat, lon) = xIsLat ? (a, b) : (b, a)
        default:
            // One letter only: it names its own axis, the other value takes the other.
            if let x = ha { (lat, lon) = "NS".contains(x) ? (a, b) : (b, a) }
            else if let y = hb { (lat, lon) = "NS".contains(y) ? (b, a) : (a, b) }
            else { return nil }
        }
        guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    private static let degrees = #"(\d+(?:\.\d+)?)(?:\s*[°º](?:\s*(\d+(?:\.\d+)?)\s*['′’](?:\s*(\d+(?:\.\d+)?)\s*(?:["″”]|''|′′))?)?)?"#
    // sign, hemisphere letter before; or sign, degrees, hemisphere letter after.
    private static let lettersFirstRegex = try! NSRegularExpression(
        pattern: #"([NSEWnsew])\s*([-+−])?\s*"# + degrees, options: [])
    private static let lettersLastRegex = try! NSRegularExpression(
        pattern: #"([-+−])?\s*"# + degrees + #"(?:\s*([NSEWnsew]))?"#, options: [])

    /// Finds the numbers and checks nothing else but separators sits between them.
    private static func scan(_ text: String, lettersFirst: Bool) -> [Component]? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let regex = lettersFirst ? lettersFirstRegex : lettersLastRegex
        let matches = regex.matches(in: text, options: [], range: full)
        guard !matches.isEmpty, matches.count <= 2 else { return nil }
        var rest = ns as String
        var out: [Component] = []
        for m in matches.reversed() { rest = (rest as NSString).replacingCharacters(in: m.range, with: " ") }
        guard rest.allSatisfy({ " ,;/\t\n".contains($0) }) else { return nil }
        for m in matches {
            func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            let hemiIndex = lettersFirst ? 1 : 5, signIndex = lettersFirst ? 2 : 1
            let base = lettersFirst ? 3 : 2
            guard let d = group(base).flatMap(Double.init) else { return nil }
            let minutes = group(base + 1).flatMap(Double.init) ?? 0
            let seconds = group(base + 2).flatMap(Double.init) ?? 0
            guard minutes < 60, seconds < 60 else { return nil }
            let value = d + minutes / 60 + seconds / 3600
            let sign = group(signIndex)
            out.append(Component(value: value, negative: sign == "-" || sign == "−",
                                 hemisphere: group(hemiIndex).flatMap { $0.uppercased().first }))
        }
        return out
    }

    // MARK: Links

    private static func linkCoordinate(_ text: String) -> Coordinate? {
        guard let components = URLComponents(string: text), let host = components.host?.lowercased(),
              host == "maps.apple.com" || host.hasSuffix(".maps.apple.com") || host == "maps.apple" else { return nil }
        let items = components.queryItems ?? []
        for name in ["ll", "coordinate", "sll", "center", "q", "daddr"] {
            for item in items where item.name == name {
                if let value = item.value, let c = parsePair(value.trimmingCharacters(in: .whitespaces)) { return c }
            }
        }
        return nil
    }
}
