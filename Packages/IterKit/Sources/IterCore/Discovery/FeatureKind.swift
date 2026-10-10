import Foundation

/// One OpenStreetMap tag test: `key` is one of `values`, every `also` key is one of its values, and the name
/// contains `nameContains` when given. Several of these per feature are alternatives (a union).
public struct OSMTag: Hashable, Sendable {
    public var key: String
    public var values: [String]
    public var also: [String: [String]]
    public var nameContains: String?

    public init(_ key: String, _ values: [String], also: [String: [String]] = [:], nameContains: String? = nil) {
        self.key = key
        self.values = values
        self.also = also
        self.nameContains = nameContains
    }

    /// Overpass QL filters, e.g. `["natural"~"^(peak|volcano)$"]["name"]`. Always requires a name.
    public var overpassFilters: String {
        func filter(_ k: String, _ v: [String]) -> String {
            v.count == 1 ? "[\"\(k)\"=\"\(v[0])\"]" : "[\"\(k)\"~\"^(\(v.joined(separator: "|")))$\"]"
        }
        var out = filter(key, values)
        for k in also.keys.sorted() { out += filter(k, also[k] ?? []) }
        if let nameContains { out += "[\"name\"~\"\(nameContains)\"]" } else { out += "[\"name\"]" }
        return out
    }
}

/// A kind of photo subject that can be listed from map data: peaks, waterfalls, arches and so on.
public enum FeatureKind: String, CaseIterable, Hashable, Sendable {
    case peak, lake, waterfall, arch, viewpoint, beach, lighthouse, canyon, glacier, hotSpring, cave, bridge, castle

    /// "waterfall"
    public var singularName: String {
        switch self {
        case .hotSpring: "hot spring"
        default: rawValue
        }
    }

    /// "waterfalls"; "peaks" for peaks, since a user who asks for mountains wants summits.
    public var pluralName: String {
        switch self {
        case .arch: "arches"
        case .beach: "beaches"
        case .hotSpring: "hot springs"
        case .peak: "mountains"
        default: rawValue + "s"
        }
    }

    /// Lower-case phrases that mean this feature, singular and plural.
    public var synonyms: [String] {
        switch self {
        case .peak: ["mountain", "mountains", "peak", "peaks", "summit", "summits", "volcano", "volcanoes", "volcanos"]
        case .lake: ["lake", "lakes", "reservoir", "reservoirs", "tarn", "tarns"]
        case .waterfall: ["waterfall", "waterfalls", "falls", "cascade", "cascades"]
        case .arch: ["arch", "arches", "natural arch", "natural arches", "rock arch", "rock arches"]
        case .viewpoint: ["viewpoint", "viewpoints", "overlook", "overlooks", "lookout", "lookouts", "vista", "vistas",
                          "scenic view", "scenic views", "view point", "view points"]
        case .beach: ["beach", "beaches"]
        case .lighthouse: ["lighthouse", "lighthouses"]
        case .canyon: ["canyon", "canyons", "gorge", "gorges", "slot canyon", "slot canyons"]
        case .glacier: ["glacier", "glaciers"]
        case .hotSpring: ["hot spring", "hot springs"]
        case .cave: ["cave", "caves", "cavern", "caverns"]
        case .bridge: ["bridge", "bridges", "covered bridge", "covered bridges"]
        case .castle: ["castle", "castles"]
        }
    }

    /// OSM tags for this feature (alternatives). Names follow the OSM wiki: `natural=peak`, `natural=volcano`,
    /// `waterway=waterfall`, `tourism=viewpoint`, `natural=arch`, `man_made=lighthouse`, `natural=beach`,
    /// `natural=glacier`, `natural=cave_entrance`, `natural=hot_spring`, `historic=castle`.
    public var osmTags: [OSMTag] {
        switch self {
        case .peak: [OSMTag("natural", ["peak", "volcano"])]
        case .lake: [OSMTag("natural", ["water"], also: ["water": ["lake", "reservoir"]]),
                     OSMTag("natural", ["water"], nameContains: "Lake")]
        case .waterfall: [OSMTag("waterway", ["waterfall"])]
        case .arch: [OSMTag("natural", ["arch"])]
        case .viewpoint: [OSMTag("tourism", ["viewpoint"])]
        case .beach: [OSMTag("natural", ["beach"])]
        case .lighthouse: [OSMTag("man_made", ["lighthouse"])]
        case .canyon: [OSMTag("natural", ["valley"], nameContains: "Canyon"), OSMTag("natural", ["canyon"])]
        case .glacier: [OSMTag("natural", ["glacier"])]
        case .hotSpring: [OSMTag("natural", ["hot_spring"])]
        case .cave: [OSMTag("natural", ["cave_entrance"])]
        case .bridge: [OSMTag("man_made", ["bridge"])]
        case .castle: [OSMTag("historic", ["castle"])]
        }
    }

    /// Words that, in a Wikipedia title or a listing name, suggest this feature. Lower case.
    public var titleKeywords: [String] {
        switch self {
        case .peak: ["mountain", "mount ", "mt ", "mt.", "peak", "summit", "volcano", "butte", "spire", "dome", "pinnacle", "ridge", "horn"]
        case .lake: ["lake", "reservoir", "tarn", "pond"]
        case .waterfall: ["fall", "cascade"]
        case .arch: ["arch", "bridge", "window"]
        case .viewpoint: ["overlook", "viewpoint", "view", "lookout", "vista", "point"]
        case .beach: ["beach", "shore", "sands", "cove"]
        case .lighthouse: ["lighthouse", "light"]
        case .canyon: ["canyon", "gorge", "narrows"]
        case .glacier: ["glacier"]
        case .hotSpring: ["hot spring", "springs", "geyser", "thermal"]
        case .cave: ["cave", "cavern", "grotto"]
        case .bridge: ["bridge"]
        case .castle: ["castle", "fort", "palace"]
        }
    }

    /// Looks a lower-case word or phrase up among every feature's synonyms.
    public static func from(phrase: String) -> FeatureKind? { synonymTable[phrase] }

    private static let synonymTable: [String: FeatureKind] = {
        var table: [String: FeatureKind] = [:]
        for kind in allCases { for s in kind.synonyms { table[s] = kind } }
        return table
    }()
}

/// "<feature> in <named area>": the request shape that discovery answers by listing every matching place.
public struct FeatureAreaQuery: Hashable, Sendable {
    public var feature: FeatureKind
    /// The area as the user typed it (original casing), without a leading "the".
    public var area: String

    public init(feature: FeatureKind, area: String) {
        self.feature = feature
        self.area = area
    }

    private static let prepositions: [[String]] = [
        ["in"], ["at"], ["near"], ["around"], ["of"], ["on"], ["within"], ["across"], ["throughout"], ["inside"],
        ["by"], ["along"], ["close", "to"], ["next", "to"],
    ]
    private static let notAnArea: Set<String> = ["me", "here", "there", "my location", "my area", "the map", "this map", "this area",
                                                  "the area", "this place", "the world", "anywhere", "nearby", "my trip", "the trip", "this trip"]

    /// Recognises "all the mountains in Glacier National Park", "waterfalls of Yosemite", "peaks around Banff",
    /// "lighthouses on the oregon coast". Nil when no known feature is directly followed by a preposition and
    /// a named area ("waterfalls near me" is not a named area).
    public static func parse(_ text: String) -> FeatureAreaQuery? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 3 else { return nil }
        let lower = words.map { stripPunctuation($0).lowercased() }

        for i in 0..<words.count {
            for length in [2, 1] where i + length < words.count {
                let phrase = lower[i..<(i + length)].joined(separator: " ")
                guard let feature = FeatureKind.from(phrase: phrase) else { continue }
                let next = i + length
                for prep in prepositions where next + prep.count < words.count {
                    guard Array(lower[next..<(next + prep.count)]) == prep else { continue }
                    var areaWords = Array(words[(next + prep.count)...])
                    if let first = areaWords.first, stripPunctuation(first).lowercased() == "the", areaWords.count > 1 { areaWords.removeFirst() }
                    let area = areaWords.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"'"))
                    guard isNamedArea(area) else { continue }
                    return FeatureAreaQuery(feature: feature, area: area)
                }
            }
        }
        return nil
    }

    private static func stripPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?\"'()"))
    }

    private static func isNamedArea(_ area: String) -> Bool {
        guard area.count >= 2, area.count <= 80, area.contains(where: { $0.isLetter }) else { return false }
        return !notAnArea.contains(area.lowercased())
    }
}
