import Foundation
import IterCore

/// Makes sure every place has a real coordinate inside the area. Places that came with one are kept only if the area
/// contains it. Places that came with a name only (Reddit, Google, Wikivoyage without coordinates) are looked up with
/// Apple Maps; the first result inside the area whose name matches wins, otherwise the place is dropped.
public struct DiscoveryValidator: Sendable {
    public static let defaultMaximumLookups = 12
    private static let concurrency = 4

    private let placeSearch: any PlaceSearching
    private let maximumLookups: Int

    public init(placeSearch: any PlaceSearching, maximumLookups: Int = DiscoveryValidator.defaultMaximumLookups) {
        self.placeSearch = placeSearch
        self.maximumLookups = maximumLookups
    }

    public struct Result: Sendable, Equatable {
        public var places: [DiscoveredPlace]
        /// How many names Apple Maps resolved.
        public var resolved: Int
    }

    public func validate(_ places: [DiscoveredPlace], in area: DiscoveryArea) async throws -> Result {
        var kept: [DiscoveredPlace] = places.filter { place in place.coordinate.map(area.contains) ?? false }
        // One lookup per distinct name, for the best-mentioned first, up to the cap.
        let pending = places.filter { $0.coordinate == nil && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        var groups: [String: [DiscoveredPlace]] = [:]
        for p in pending { groups[DiscoveryNames.key(p.name).description, default: []].append(p) }
        let ordered = groups.values.sorted {
            let ma = $0.map(\.mentions).max() ?? 0, mb = $1.map(\.mentions).max() ?? 0
            return ma != mb ? ma > mb : $0[0].name < $1[0].name
        }.prefix(maximumLookups)

        var resolved = 0
        let areaName = area.name ?? ""
        let list = Array(ordered)
        for start in stride(from: 0, to: list.count, by: Self.concurrency) {
            try Task.checkCancellation()
            let batch = Array(list[start..<min(start + Self.concurrency, list.count)])
            let answers = try await withThrowingTaskGroup(of: (Int, Coordinate?).self) { group in
                for (i, members) in batch.enumerated() {
                    let name = members[0].name
                    group.addTask { (i, await lookup(name, areaName: areaName, area: area)) }
                }
                var out: [Int: Coordinate] = [:]
                for try await (i, c) in group { if let c { out[i] = c } }
                return out
            }
            for (i, members) in batch.enumerated() {
                guard let coordinate = answers[i] else { continue }
                resolved += 1
                for var member in members {
                    member.coordinate = coordinate
                    member.sources.insert(.appleMaps)
                    kept.append(member)
                }
            }
        }
        return Result(places: kept, resolved: resolved)
    }

    private func lookup(_ name: String, areaName: String, area: DiscoveryArea) async -> Coordinate? {
        let query = areaName.isEmpty ? name : name + " " + areaName
        guard let results = try? await placeSearch.search(query, near: area.region) else { return nil }
        return results.first { area.contains($0.coordinate) && DiscoveryNames.looselyMatches($0.name, name) }?.coordinate
    }
}
