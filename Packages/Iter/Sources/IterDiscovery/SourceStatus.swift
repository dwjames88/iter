import Foundation
import IterAI
import IterModel
import IterSources

/// What a source was asked to do in a Find run.
public enum SourceRole: String, Sendable, Hashable, Codable {
    case geocoder, boundary, gazetteer, placeSearch, text, photos, ai
}

/// The state of one source in one run, shown as a chip ("OpenStreetMap: 14", "Reddit: needs your own key").
public enum SourceState: Sendable, Hashable {
    /// The source is working on it.
    case searching
    /// It answered with this many results (places, documents or photos, by role).
    case found(Int)
    /// It answered and had nothing.
    case empty
    case failed(NoDataReason)
    /// Ran past its timeout.
    case timedOut
    /// Not asked, with a plain reason (outside coverage, nothing to search for).
    case skipped(String)
    /// Cannot be used at all, with a plain reason (no key, closed to new users, AI off).
    case unavailable(String)
}

/// One row of the source list for a run.
public struct SourceStatus: Sendable, Hashable, Identifiable {
    public var source: SourceID
    public var name: String
    public var role: SourceRole
    public var state: SourceState

    /// One row per source and role: a source that serves two roles (Overpass: gazetteer and boundary) has two rows.
    public var id: String { "\(source.rawValue)#\(role.rawValue)" }

    public init(source: SourceID, name: String, role: SourceRole, state: SourceState) {
        self.source = source
        self.name = name
        self.role = role
        self.state = state
    }

    /// A line for the chip: "OpenStreetMap (Overpass): 14", "Reddit: needs your own Reddit API access; ...".
    public var summary: String {
        switch state {
        case .searching: "\(name): searching"
        case .found(let n): "\(name): \(n)"
        case .empty: "\(name): nothing found"
        case .failed(let reason): "\(name): \(Self.describe(reason))"
        case .timedOut: "\(name): timed out"
        case .skipped(let why), .unavailable(let why): "\(name): \(why)"
        }
    }

    static func describe(_ reason: NoDataReason) -> String {
        switch reason {
        case .outsideCoverage: "outside its coverage"
        case .needsKey: "add a key"
        case .offline: "offline"
        case .rateLimited: "rate limited"
        case .sourceError(_, let text): "error (\(text))"
        case .notProvidedBySource: "not provided"
        case .appleIntelligenceUnavailable: "Apple Intelligence unavailable"
        }
    }
}

/// The text sources that cannot be consulted, always listed so the owner sees why. A user-key provider with one of these
/// ids simply joins the text providers and then shows as consulted (the extension point for Reddit OAuth later).
public enum FixedSources {
    public static let reddit: SourceID = "reddit.api"
    public static let google: SourceID = "google.cse"
    public static let ai: SourceID = "iter.ai"

    public static let redditReason = "needs your own Reddit API access; no free keyless access exists"
    public static let googleReason = "Google Custom Search is closing to new users; not used"

    /// Entries for the sources that are not available, minus any that a registered provider covers.
    static func unavailable(consulting providers: [any SourceDescribing]) -> [SourceStatus] {
        let present = Set(providers.map(\.descriptor.id))
        var out: [SourceStatus] = []
        if !present.contains(reddit) {
            out.append(SourceStatus(source: reddit, name: "Reddit", role: .text, state: .unavailable(redditReason)))
        }
        if !present.contains(google) {
            out.append(SourceStatus(source: google, name: "Google", role: .text, state: .unavailable(googleReason)))
        }
        return out
    }

    static func aiStatus(origin: PlanOrigin) -> SourceStatus {
        switch origin {
        case .ai: SourceStatus(source: ai, name: "Apple Intelligence", role: .ai, state: .found(1))
        case .basic, .basicNoModel: SourceStatus(source: ai, name: "Apple Intelligence", role: .ai, state: .unavailable(origin.label ?? "Basic search"))
        }
    }
}
