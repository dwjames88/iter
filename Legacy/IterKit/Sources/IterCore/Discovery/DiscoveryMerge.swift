import Foundation

/// De-duplicates places from different sources, drops those outside the area, and ranks what is left. Pure and
/// deterministic: the same input in any order gives the same output.
public enum DiscoveryMerge {
    /// Two places whose names match (see `DiscoveryNames.Key`) are one place when this close.
    public static let sameNameRadiusMeters = 1_500.0
    /// Two places this close are one place whatever they are called.
    public static let anyNameRadiusMeters = 60.0

    /// Merged, inside the area, ranked by `settings.preference` and cut to `settings.maxResults`.
    public static func merge(_ places: [DiscoveredPlace], area: DiscoveryArea, settings: DiscoverySettings) -> [DiscoveredPlace] {
        Array(mergeAll(places, area: area, preference: settings.preference).prefix(settings.maxResults))
    }

    /// As `merge` but not cut, so callers can count what each source contributed.
    public static func mergeAll(_ places: [DiscoveredPlace], area: DiscoveryArea, preference: DiscoveryPreference) -> [DiscoveredPlace] {
        let located = places.filter { place in
            guard let c = place.coordinate, !place.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            return area.contains(c)
        }
        return rank(deduplicate(located), preference: preference)
    }

    // MARK: De-duplication

    /// Groups places that are the same by the radius rules and merges each group into one place.
    /// Places without a coordinate are returned unchanged at the end.
    public static func deduplicate(_ places: [DiscoveredPlace]) -> [DiscoveredPlace] {
        let located = places.filter { $0.coordinate != nil }.sorted(by: stableOrder)
        let unlocated = places.filter { $0.coordinate == nil }.sorted(by: stableOrder)
        var parent = Array(0..<located.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let keys = located.map { DiscoveryNames.key($0.name) }
        for i in 0..<located.count {
            guard let a = located[i].coordinate else { continue }
            for j in (i + 1)..<max(i + 1, located.count) {
                guard let b = located[j].coordinate else { continue }
                if abs(a.latitude - b.latitude) > 0.02 { continue }   // about 2.2 km, beyond both radii
                let d = a.distance(to: b)
                if d <= anyNameRadiusMeters || (d <= sameNameRadiusMeters && keys[i].matches(keys[j])) {
                    let ri = find(i), rj = find(j)
                    if ri != rj { parent[max(ri, rj)] = min(ri, rj) }
                }
            }
        }
        var groups: [Int: [DiscoveredPlace]] = [:]
        for i in 0..<located.count { groups[find(i), default: []].append(located[i]) }
        let merged = groups.keys.sorted().map { combine(groups[$0]!) }
        return merged + unlocated
    }

    private static func stableOrder(_ a: DiscoveredPlace, _ b: DiscoveredPlace) -> Bool {
        let na = DiscoveryNames.normalise(a.name), nb = DiscoveryNames.normalise(b.name)
        if na != nb { return na < nb }
        let ca = a.coordinate, cb = b.coordinate
        if ca?.latitude != cb?.latitude { return (ca?.latitude ?? 0) < (cb?.latitude ?? 0) }
        if ca?.longitude != cb?.longitude { return (ca?.longitude ?? 0) < (cb?.longitude ?? 0) }
        return a.name < b.name
    }

    /// How much a source's wording of a name is trusted. Wikipedia and OSM carry official names.
    static func nameRank(_ source: DiscoverySourceID) -> Int {
        switch source {
        case .wikipedia: 5
        case .openStreetMap: 4
        case .wikivoyage: 3
        case .appleMaps: 2
        case .google: 1
        case .reddit: 0
        }
    }

    /// How much a source's coordinate is trusted. An OSM node is a surveyed point; Wikipedia's is usually rounded.
    static func coordinateRank(_ source: DiscoverySourceID) -> Int {
        switch source {
        case .openStreetMap: 5
        case .wikipedia: 4
        case .wikivoyage: 3
        case .appleMaps: 2
        case .google: 1
        case .reddit: 0
        }
    }

    private static func best(_ place: DiscoveredPlace, by rank: (DiscoverySourceID) -> Int) -> Int {
        place.sources.map(rank).max() ?? -1
    }

    private static func combine(_ group: [DiscoveredPlace]) -> DiscoveredPlace {
        guard group.count > 1 else { return group[0] }
        let byName = group.sorted {
            let ra = best($0, by: nameRank), rb = best($1, by: nameRank)
            if ra != rb { return ra > rb }
            if $0.name.count != $1.name.count { return $0.name.count > $1.name.count }
            return $0.name < $1.name
        }
        let byCoordinate = group.sorted {
            let ra = best($0, by: coordinateRank), rb = best($1, by: coordinateRank)
            if ra != rb { return ra > rb }
            return $0.name < $1.name
        }
        var result = byName[0]
        result.coordinate = byCoordinate.first(where: { $0.coordinate != nil })?.coordinate
        result.elevationMeters = byCoordinate.compactMap(\.elevationMeters).first
        result.feature = byName.compactMap(\.feature).first
        result.sources = group.reduce(into: Set<DiscoverySourceID>()) { $0.formUnion($1.sources) }
        result.mentions = group.map(\.mentions).max() ?? 0
        result.why = byName.compactMap(\.why).first
        let wikipediaSnippet = byName.first(where: { $0.sources.contains(.wikipedia) })?.snippet
        result.snippet = wikipediaSnippet ?? byName.compactMap(\.snippet).max(by: { $0.count < $1.count })
        var seen = Set<String>()
        result.links = byName.flatMap(\.links).filter { seen.insert($0.absoluteString).inserted }
        return result
    }

    // MARK: Ranking

    /// Popular: most mentioned first, then a Wikipedia presence, then the higher ground. Unique: the least mentioned
    /// first, places with no Wikipedia presence ahead, single-source OSM or Reddit entries ahead of the rest.
    /// Mixed: the two orders interleaved, popular first.
    public static func rank(_ places: [DiscoveredPlace], preference: DiscoveryPreference) -> [DiscoveredPlace] {
        switch preference {
        case .popular: return popularOrder(places)
        case .unique: return uniqueOrder(places)
        case .mixed:
            let popular = popularOrder(places), unique = uniqueOrder(places)
            var result: [DiscoveredPlace] = []
            var used = Set<String>()
            var p = 0, u = 0
            func take(_ list: [DiscoveredPlace], _ index: inout Int) {
                while index < list.count {
                    let candidate = list[index]; index += 1
                    if used.insert(candidate.id).inserted { result.append(candidate); return }
                }
            }
            while result.count < places.count && (p < popular.count || u < unique.count) {
                take(popular, &p)
                take(unique, &u)
            }
            return result
        }
    }

    private static func popularOrder(_ places: [DiscoveredPlace]) -> [DiscoveredPlace] {
        places.sorted { a, b in
            if a.mentions != b.mentions { return a.mentions > b.mentions }
            if a.hasWikipediaPresence != b.hasWikipediaPresence { return a.hasWikipediaPresence }
            if a.elevationMeters != b.elevationMeters { return (a.elevationMeters ?? -.infinity) > (b.elevationMeters ?? -.infinity) }
            return tieBreak(a, b)
        }
    }

    private static func uniqueOrder(_ places: [DiscoveredPlace]) -> [DiscoveredPlace] {
        func singleSource(_ p: DiscoveredPlace) -> Bool { p.sources == [.openStreetMap] || p.sources == [.reddit] }
        return places.sorted { a, b in
            if a.mentions != b.mentions { return a.mentions < b.mentions }
            if a.hasWikipediaPresence != b.hasWikipediaPresence { return !a.hasWikipediaPresence }
            if singleSource(a) != singleSource(b) { return singleSource(a) }
            if a.sources.count != b.sources.count { return a.sources.count < b.sources.count }
            return tieBreak(a, b)
        }
    }

    private static func tieBreak(_ a: DiscoveredPlace, _ b: DiscoveredPlace) -> Bool {
        let na = DiscoveryNames.normalise(a.name), nb = DiscoveryNames.normalise(b.name)
        if na != nb { return na < nb }
        return a.id < b.id
    }
}
