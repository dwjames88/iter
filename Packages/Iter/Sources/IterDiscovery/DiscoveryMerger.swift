import Foundation
import IterModel
import IterSources

/// De-duplicates verified candidates from different sources. Ported from the old `DiscoveryMerge`: two places whose names
/// match are one place within 1.5 km, and any two places within 60 m are one place. Pure and deterministic: the same
/// input in any order gives the same output. The merged coordinate is the most precise grounded coordinate among the
/// members (OSM and GNIS over Wikipedia over MapKit over a geocoded name); it is copied, never created.
enum DiscoveryMerger {
    static let sameNameRadiusMeters = 1_500.0
    static let anyNameRadiusMeters = 60.0

    static func merge(_ candidates: [VerifiedCandidate]) -> [VerifiedCandidate] {
        let sorted = candidates.sorted(by: stableOrder)
        var parent = Array(0..<sorted.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let keys = sorted.map { DiscoveryNames.key($0.name) }
        for i in 0..<sorted.count {
            let a = sorted[i].coordinate.value
            for j in (i + 1)..<max(i + 1, sorted.count) {
                let b = sorted[j].coordinate.value
                if abs(a.latitude - b.latitude) > 0.02 { continue }   // about 2.2 km, beyond both radii
                let d = a.distance(to: b)
                if d <= anyNameRadiusMeters || (d <= sameNameRadiusMeters && keys[i].matches(keys[j])) {
                    let ri = find(i), rj = find(j)
                    if ri != rj { parent[max(ri, rj)] = min(ri, rj) }
                }
            }
        }
        var groups: [Int: [VerifiedCandidate]] = [:]
        for i in 0..<sorted.count { groups[find(i), default: []].append(sorted[i]) }
        return groups.keys.sorted().map { combine(groups[$0]!) }
    }

    private static func stableOrder(_ a: VerifiedCandidate, _ b: VerifiedCandidate) -> Bool {
        let na = DiscoveryNames.normalise(a.name), nb = DiscoveryNames.normalise(b.name)
        if na != nb { return na < nb }
        let ca = a.coordinate.value, cb = b.coordinate.value
        if ca.latitude != cb.latitude { return ca.latitude < cb.latitude }
        if ca.longitude != cb.longitude { return ca.longitude < cb.longitude }
        return a.sources.map(\.rawValue).joined() < b.sources.map(\.rawValue).joined()
    }

    /// How much a source's wording of a name is trusted. Wikipedia and OSM carry official names.
    static func nameRank(_ source: SourceID) -> Int {
        switch source.family {
        case "wikipedia", "wikidata": 5
        case "osm", "usgs": 4
        case "wikivoyage": 3
        case "apple": 2
        default: 1
        }
    }

    private static func best(_ c: VerifiedCandidate) -> Int { c.sources.map(nameRank).max() ?? 0 }

    private static func combine(_ group: [VerifiedCandidate]) -> VerifiedCandidate {
        guard group.count > 1 else { return group[0] }
        let byName = group.sorted {
            if best($0) != best($1) { return best($0) > best($1) }
            if $0.name.count != $1.name.count { return $0.name.count > $1.name.count }
            return $0.name < $1.name
        }
        let byCoordinate = group.sorted {
            if $0.coordinate.precisionRank != $1.coordinate.precisionRank { return $0.coordinate.precisionRank > $1.coordinate.precisionRank }
            return $0.name < $1.name
        }
        var result = byName[0]
        result.coordinate = byCoordinate[0].coordinate
        result.elevationMeters = byCoordinate.compactMap(\.elevationMeters).first
        var kinds: [FeatureKind] = []
        var sources: [SourceID] = []
        var stable = Set<SourceID>()
        var citations: [Citation] = []
        var seenCitations = Set<String>()
        var ids: [String] = []
        for c in byName {
            for k in c.featureKinds where !kinds.contains(k) { kinds.append(k) }
            for s in c.sources where !sources.contains(s) { sources.append(s) }
            stable.formUnion(c.stableSources)
            for cit in c.citations where seenCitations.insert("\(cit.source.rawValue)|\(cit.url?.absoluteString ?? cit.title)").inserted { citations.append(cit) }
            for id in c.externalIDs where !ids.contains(id) { ids.append(id) }
        }
        result.featureKinds = kinds
        result.sources = sources
        result.stableSources = stable
        result.citations = citations
        result.externalIDs = ids
        result.mentionCount = group.reduce(0) { $0 + $1.mentionCount }
        let wikiSnippet = byName.first(where: { $0.sources.contains { $0.family == "wikipedia" } })?.snippet
        result.snippet = wikiSnippet ?? byName.compactMap(\.snippet).max(by: { $0.count < $1.count })
        return result
    }
}
