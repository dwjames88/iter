import Foundation
import IterModel

/// A small on-device summary of what the owner saves and plans: how much each kind of place (waterfall, arch, viewpoint...)
/// features in their saved places and trips. "Learn From My Library" uses it to nudge discovery ranking.
///
/// Privacy: this holds only normalised weights per `FeatureKind`. It is computed on the device, never put in a request to a
/// source, never given to the language model (the model sees neither it nor the names it came from), and never stored.
public struct LibraryProfile: Sendable, Hashable {
    /// 0...1 per kind; the owner's most-used kind is 1.
    public let kindWeights: [FeatureKind: Double]

    /// Fewer contributing places than this and the library says too little to learn from: one save must not tilt results.
    public static let minimumPlaces = 3
    /// The most a perfect match can lift a score, as a fraction of it.
    public static let maximumBoost = 0.12

    public init(kindWeights: [FeatureKind: Double]) {
        self.kindWeights = kindWeights.mapValues { min(1, max(0, $0)) }.filter { $0.value > 0 }
    }

    public var isEmpty: Bool { kindWeights.isEmpty }

    /// How well a place's kinds match what the owner saves, 0...1 (the best weight among its kinds).
    public func affinity(for kinds: [FeatureKind]) -> Double {
        kinds.compactMap { kindWeights[$0] }.max() ?? 0
    }

    /// Computed from the saved places and every stop of every trip. A place counts once as saved, again for each trip stop
    /// (planning something is a stronger signal than saving it), and a little more when pinned. Kinds come from the place's
    /// name and tags (words like "arch" or "falls") and, more weakly, from its category.
    public init(savedPlaces: [Place], trips: [Trip]) {
        var weights: [FeatureKind: Double] = [:]
        var contributing = 0
        func add(_ place: Place, weight: Double) {
            let named = Self.namedKinds(in: place)
            let fromCategory = Self.kinds(for: place.category)
            guard !named.isEmpty || !fromCategory.isEmpty else { return }
            contributing += 1
            for k in named { weights[k, default: 0] += weight }
            for k in fromCategory where !named.contains(k) { weights[k, default: 0] += 0.5 * weight / Double(fromCategory.count) }
        }
        for p in savedPlaces { add(p, weight: p.isPinned ? 1.5 : 1) }
        for trip in trips { for stop in trip.stops where stop.kind == .light { add(stop.place, weight: 1.5) } }
        guard contributing >= Self.minimumPlaces, let top = weights.values.max(), top > 0 else {
            self.init(kindWeights: [:])
            return
        }
        self.init(kindWeights: weights.mapValues { $0 / top })
    }

    static func namedKinds(in place: Place) -> Set<FeatureKind> {
        var kinds = Set<FeatureKind>()
        for text in place.tags + [place.name] {
            let tokens = DiscoveryNames.tokens(text)
            var i = 0
            while i < tokens.count {
                if i + 1 < tokens.count, let k = FeatureKind.from(phrase: tokens[i] + " " + tokens[i + 1]) { kinds.insert(k); i += 2; continue }
                if let k = FeatureKind.from(phrase: tokens[i]) { kinds.insert(k) }
                i += 1
            }
        }
        return kinds
    }

    static func kinds(for category: PlaceCategory) -> [FeatureKind] {
        switch category {
        case .waterfall: [.waterfall]
        case .coast: [.beach, .lighthouse]
        case .desert: [.arch, .canyon]
        case .landscape: [.viewpoint, .peak, .lake]
        case .architecture: [.bridge, .castle]
        case .astro, .street, .wildlife, .forest, .urban: []
        }
    }
}
