import Foundation
import IterModel
import IterSources

/// One visible part of a rank. `value` is 0...1, or nil when the part does not apply (the note says why).
public struct RankPart: Sendable, Hashable {
    public var value: Double?
    public var note: String

    public init(value: Double?, note: String) {
        self.value = value.map { min(1, max(0, $0)) }
        self.note = note
    }
}

/// The parts a place's rank is made of, each with a plain note, so the UI can show why it sits where it does.
/// The model never ranks: every part is computed from stored facts.
public struct RankBreakdown: Sendable, Hashable {
    /// How well it matches the requested features and keywords.
    public var featureMatch: RankPart
    /// Photo count, mentions, a Wikipedia presence and how many sources agree.
    public var evidence: RankPart
    /// Match with the owner's "what I like to shoot" text.
    public var preference: RankPart
    /// The facing against the sun in the wanted window. Nil value (with a note) when no facing is known.
    public var lightSuit: RankPart
    /// Straight-line distance from the user or the area centre.
    public var reachability: RankPart
    /// How new it is against the owner's library.
    public var novelty: RankPart
    /// Strict matches always list before related ones, whatever the scores.
    public var matchTier: MatchTier
    /// How well the place's kind matches what the owner saves, 0...1 ("Learn From My Library"). 0 when the setting is off or
    /// the library says too little; then the score is exactly what it would have been without the feature.
    public var libraryAffinity: Double

    public init(featureMatch: RankPart, evidence: RankPart, preference: RankPart, lightSuit: RankPart, reachability: RankPart, novelty: RankPart,
                matchTier: MatchTier = .strict, libraryAffinity: Double = 0) {
        self.matchTier = matchTier
        self.libraryAffinity = min(1, max(0, libraryAffinity))
        self.featureMatch = featureMatch
        self.evidence = evidence
        self.preference = preference
        self.lightSuit = lightSuit
        self.reachability = reachability
        self.novelty = novelty
    }

    /// The weighted score for an ordering, 0...1. Parts without a value are left out and the rest renormalised.
    /// A library match lifts it by at most `LibraryProfile.maximumBoost` (12%), and never past 1.
    public func score(for ordering: DiscoveryOrdering) -> Double {
        let base = baseScore(for: ordering)
        guard libraryAffinity > 0 else { return base }
        return min(1, base * (1 + LibraryProfile.maximumBoost * libraryAffinity))
    }

    private func baseScore(for ordering: DiscoveryOrdering) -> Double {
        switch ordering {
        case .popular: weighted(evidenceWeight: 0.35, invertEvidence: false, noveltyWeight: 0.05)
        case .unique: weighted(evidenceWeight: 0.25, invertEvidence: true, noveltyWeight: 0.20)
        case .mixed: 0.5 * baseScore(for: .popular) + 0.5 * baseScore(for: .unique)
        }
    }

    private func weighted(evidenceWeight: Double, invertEvidence: Bool, noveltyWeight: Double) -> Double {
        var total = 0.0, weight = 0.0
        func add(_ part: RankPart, _ w: Double, invert: Bool = false) {
            guard let v = part.value else { return }
            total += w * (invert ? 1 - v : v)
            weight += w
        }
        add(featureMatch, 0.25)
        add(evidence, evidenceWeight, invert: invertEvidence)
        add(preference, 0.15)
        add(lightSuit, 0.10)
        add(reachability, 0.10)
        add(novelty, noveltyWeight)
        return weight > 0 ? total / weight : 0
    }
}

/// Deterministic ranking from stored facts.
enum DiscoveryRanker {
    struct Context: Sendable {
        var plan: QueryPlan
        var ordering: DiscoveryOrdering
        var preferenceText: String?
        var library: [LibraryReference]
        /// The user's location, else the area centre.
        var anchor: Coordinate
        var anchorIsUser: Bool
        /// Nil with "Learn From My Library" off: ranking is then unchanged.
        var profile: LibraryProfile? = nil
    }

    struct Scored: Sendable {
        var candidate: VerifiedCandidate
        var photoCount: Int
        var photos: [LicensedPhoto]
    }

    static func place(from s: Scored, context: Context) -> DiscoveredPlace {
        let c = s.candidate
        let distance = c.coordinate.value.distance(to: context.anchor) / 1000
        let rank = breakdown(for: s, context: context, distanceKm: distance)
        return DiscoveredPlace(id: DiscoveredPlace.makeID(name: c.name, coordinate: c.coordinate.value), name: c.name, coordinate: c.coordinate,
                               elevationMeters: c.elevationMeters, featureKinds: c.featureKinds, sources: c.sources,
                               verification: c.verification, citations: c.citations, mentionCount: c.mentionCount, photoCount: s.photoCount,
                               photos: s.photos, snippet: c.snippet, why: nil, rank: rank, distanceKm: distance)
    }

    /// Ranked, best first; ties by name then id so the order never depends on arrival order.
    static func rank(_ items: [Scored], context: Context) -> [DiscoveredPlace] {
        items.map { place(from: $0, context: context) }.sorted { a, b in
            if a.rank.matchTier != b.rank.matchTier { return a.rank.matchTier < b.rank.matchTier }
            let sa = a.rank.score(for: context.ordering), sb = b.rank.score(for: context.ordering)
            if abs(sa - sb) > 1e-9 { return sa > sb }
            let na = DiscoveryNames.normalise(a.name), nb = DiscoveryNames.normalise(b.name)
            if na != nb { return na < nb }
            return a.id < b.id
        }
    }

    // MARK: Parts

    static func breakdown(for s: Scored, context: Context, distanceKm: Double) -> RankBreakdown {
        RankBreakdown(featureMatch: featureMatch(s.candidate, plan: context.plan), evidence: evidence(s),
                      preference: preference(s.candidate, text: context.preferenceText),
                      lightSuit: RankPart(value: nil, note: "No facing is known for this place, so light suit is not scored."),
                      reachability: reachability(distanceKm: distanceKm, anchorIsUser: context.anchorIsUser),
                      novelty: novelty(s.candidate, library: context.library),
                      matchTier: FeatureRelatedness.tier(of: s.candidate.featureKinds, plan: context.plan),
                      libraryAffinity: context.profile?.affinity(for: s.candidate.featureKinds) ?? 0)
    }

    static func featureMatch(_ c: VerifiedCandidate, plan: QueryPlan) -> RankPart {
        let words = Set(DiscoveryNames.tokens(c.name + " " + (c.snippet ?? "")))
        let keywordHits = plan.keywords.filter { k in
            let t = DiscoveryNames.tokens(k)
            return !t.isEmpty && t.allSatisfy(words.contains)
        }.count
        let keywordPart = plan.keywords.isEmpty ? 0 : 0.2 * Double(keywordHits) / Double(plan.keywords.count)
        if plan.features.isEmpty {
            return plan.keywords.isEmpty ? RankPart(value: nil, note: "No feature was asked for.")
                : RankPart(value: min(1, 0.4 + keywordPart * 3), note: "\(keywordHits) of \(plan.keywords.count) search words appear.")
        }
        let hit = c.featureKinds.first(where: plan.features.contains)
        if let hit { return RankPart(value: 0.8 + keywordPart, note: "A \(hit.singularName), as asked.") }
        if c.featureKinds.isEmpty { return RankPart(value: 0.3 + keywordPart, note: "Its kind is not known.") }
        let relatedKinds = Set(FeatureRelatedness.related(to: plan.features))
        if let r = c.featureKinds.first(where: relatedKinds.contains) { return RankPart(value: 0.4 + keywordPart, note: "related: \(r.singularName)") }
        return RankPart(value: keywordPart, note: "Not one of the requested kinds.")
    }

    static func evidence(_ s: Scored) -> RankPart {
        let c = s.candidate
        let photos = min(1, log1p(Double(s.photoCount)) / log1p(50)) * 0.35
        let mentions = min(1, log1p(Double(c.mentionCount)) / log1p(20)) * 0.20
        let wiki = c.sources.contains { $0.family == "wikipedia" } ? 0.20 : 0
        let agreeing = min(1, Double(c.independentSourceCount - 1) / 3) * 0.25
        var notes: [String] = []
        if s.photoCount > 0 { notes.append("\(s.photoCount) geotagged \(s.photoCount == 1 ? "photo" : "photos")") }
        if c.mentionCount > 0 { notes.append("\(c.mentionCount) \(c.mentionCount == 1 ? "mention" : "mentions")") }
        if wiki > 0 { notes.append("on Wikipedia") }
        notes.append("\(c.independentSourceCount) source\(c.independentSourceCount == 1 ? "" : "s")")
        return RankPart(value: photos + mentions + wiki + agreeing, note: notes.joined(separator: ", "))
    }

    static let preferenceStopwords: Set<String> = [
        "i", "like", "love", "to", "shoot", "photograph", "photographing", "shooting", "photography", "and", "the", "a", "an", "of", "in", "on",
        "my", "mostly", "mainly", "some", "lots", "things", "stuff", "with", "or", "really", "especially", "any", "all", "good", "great",
    ]

    /// Kinds and plain words the owner's preference text names.
    static func preferenceTerms(_ text: String) -> (kinds: Set<FeatureKind>, words: Set<String>) {
        let tokens = DiscoveryNames.tokens(text)
        var kinds = Set<FeatureKind>()
        var consumed = Set<Int>()
        var i = 0
        while i < tokens.count {
            if i + 1 < tokens.count, let k = FeatureKind.from(phrase: tokens[i] + " " + tokens[i + 1]) {
                kinds.insert(k); consumed.insert(i); consumed.insert(i + 1); i += 2; continue
            }
            if let k = FeatureKind.from(phrase: tokens[i]) { kinds.insert(k); consumed.insert(i) }
            i += 1
        }
        var words = Set<String>()
        for (n, t) in tokens.enumerated() where !consumed.contains(n) && !preferenceStopwords.contains(t) && t.count >= 3 { words.insert(stem(t)) }
        return (kinds, words)
    }

    private static func stem(_ w: String) -> String { w.hasSuffix("s") && w.count > 3 ? String(w.dropLast()) : w }

    static func preference(_ c: VerifiedCandidate, text: String?) -> RankPart {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return RankPart(value: nil, note: "No \"what I like to shoot\" text is set.")
        }
        let (kinds, words) = preferenceTerms(text)
        if kinds.isEmpty && words.isEmpty { return RankPart(value: nil, note: "Nothing usable in the \"what I like to shoot\" text.") }
        var score = 0.0
        var notes: [String] = []
        let kindHits = kinds.filter(c.featureKinds.contains)
        if !kindHits.isEmpty {
            score += 0.7
            notes.append("a " + kindHits.map(\.singularName).sorted().joined(separator: " and ") + " you like")
        }
        let haystack = Set(DiscoveryNames.tokens(c.name + " " + (c.snippet ?? "")).map(stem))
        let wordHits = words.filter(haystack.contains)
        if !wordHits.isEmpty {
            score += min(0.3, 0.15 * Double(wordHits.count))
            notes.append("mentions " + wordHits.sorted().joined(separator: ", "))
        }
        return RankPart(value: score, note: notes.isEmpty ? "Nothing in common with what you like to shoot." : notes.joined(separator: "; "))
    }

    static func reachability(distanceKm: Double, anchorIsUser: Bool) -> RankPart {
        let from = anchorIsUser ? "you" : "the middle of the area"
        return RankPart(value: 1 / (1 + distanceKm / 40), note: String(format: "%.0f km from %@ in a straight line", distanceKm, from))
    }

    static func novelty(_ c: VerifiedCandidate, library: [LibraryReference]) -> RankPart {
        guard !library.isEmpty else { return RankPart(value: nil, note: "Your library is empty, so nothing is compared.") }
        for ref in library {
            if DiscoveryNames.matches(ref.name, c.name) { return RankPart(value: 0, note: "Already in your library.") }
            if let rc = ref.coordinate, rc.distance(to: c.coordinate.value) < 100 { return RankPart(value: 0, note: "Already in your library as \(ref.name).") }
        }
        let nearest = library.compactMap { $0.coordinate?.distance(to: c.coordinate.value) }.min()
        if let nearest, nearest < 2_000 { return RankPart(value: 0.6, note: "New, but close to a place you saved.") }
        let sameKind = c.featureKinds.contains { k in library.contains { $0.featureKinds.contains(k) } }
        return RankPart(value: sameKind ? 0.85 : 1, note: sameKind ? "New to your library, a kind you already save." : "New to your library, and a kind you have not saved.")
    }
}
