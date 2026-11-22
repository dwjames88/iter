import Foundation
import IterModel

/// Which photo subjects sit near each other for a photographer: a search for viewpoints is also happy with peaks, arches,
/// canyons and lakes when the strict pass finds little. Widened results rank below strict ones and say "related: <kind>".
enum FeatureRelatedness {
    static func related(to kind: FeatureKind) -> [FeatureKind] {
        switch kind {
        case .viewpoint: [.peak, .arch, .canyon, .lake, .waterfall, .glacier, .beach, .lighthouse]
        case .peak: [.viewpoint, .glacier, .lake, .canyon]
        case .lake: [.peak, .viewpoint, .waterfall, .glacier]
        case .waterfall: [.canyon, .lake, .viewpoint, .cave]
        case .arch: [.canyon, .viewpoint, .cave, .peak]
        case .beach: [.lighthouse, .viewpoint, .cave]
        case .lighthouse: [.beach, .viewpoint]
        case .canyon: [.arch, .viewpoint, .waterfall, .cave]
        case .glacier: [.peak, .lake, .viewpoint]
        case .hotSpring: [.lake, .waterfall]
        case .cave: [.arch, .canyon, .waterfall]
        case .bridge: [.canyon, .castle, .waterfall]
        case .castle: [.bridge, .viewpoint, .lighthouse]
        }
    }

    /// Union of the related kinds of `kinds`, without `kinds` themselves, in a stable order.
    static func related(to kinds: [FeatureKind]) -> [FeatureKind] {
        var out: [FeatureKind] = []
        for k in kinds { for r in related(to: k) where !kinds.contains(r) && !out.contains(r) { out.append(r) } }
        return out
    }

    /// Words a natural-feature article title may end with without naming a `FeatureKind`: "Alabama Hills", "Sherwin Range".
    static let naturalTitleWords: Set<String> = [
        "hills", "range", "dunes", "valley", "basin", "rocks", "rock", "spire", "dome", "butte", "mesa", "point", "overlook", "vista",
        "mountain", "mountains", "ridge", "pass", "gorge", "canyon", "falls", "fall", "lake", "arch", "bluff", "cliffs", "crater", "flat",
        "meadow", "meadows", "peak", "peaks", "needles", "narrows", "wash", "springs", "creek",
    ]

    static func looksLikeNaturalFeature(title: String) -> Bool {
        guard let last = DiscoveryNames.tokens(title).last else { return false }
        return naturalTitleWords.contains(last)
    }

    /// 0 strict, 1 related or unknown kind, 2 unrelated. With no requested features everything is strict.
    static func tier(of kinds: [FeatureKind], plan: QueryPlan) -> MatchTier {
        guard !plan.features.isEmpty else { return .strict }
        if kinds.contains(where: plan.features.contains) { return .strict }
        if kinds.isEmpty { return .related }
        let rel = Set(related(to: plan.features))
        return kinds.contains(where: rel.contains) ? .related : .other
    }
}

/// How a place relates to what was asked for. Strict matches are always listed before the rest.
public enum MatchTier: Int, Sendable, Hashable, Comparable {
    case strict = 0, related = 1, other = 2
    public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
}
