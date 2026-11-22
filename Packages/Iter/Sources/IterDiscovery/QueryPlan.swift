import Foundation
import IterAI
import IterModel

// The structured form of what the user asked for (BLUEPRINT §7 step 1). Deliberately has NO coordinate, latitude, longitude
// or any other measured number except a drive-time cap: the plan names an area as text and the Find pipeline resolves it
// through a geocoder and boundary source. That is the first half of the grounding rule; `GroundedCoordinate` is the second.

/// How the search area is given.
public enum AreaMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// A place the user named ("Lone Pine, California"); `QueryPlan.areaText` holds it.
    case named
    /// Around the user's current location.
    case nearMe
    /// Inside the map region the user is looking at.
    case mapArea
}

/// What the user wants to find, in a form the pipeline can act on. Pure value, no coordinates by construction.
public struct QueryPlan: Codable, Sendable, Hashable {
    public var areaText: String?
    public var areaMode: AreaMode
    public var features: [FeatureKind]
    public var windows: [LightWindowKind]
    public var dateHint: String?
    /// Straight-line radius is derived from this; the real ETA filter happens later on the top results.
    public var maxDriveMinutes: Int?
    /// At most `QueryPlan.maximumKeywords`.
    public var keywords: [String]
    public var exclude: [String]

    public static let maximumKeywords = 6

    public init(areaText: String? = nil, areaMode: AreaMode = .named, features: [FeatureKind] = [], windows: [LightWindowKind] = [],
                dateHint: String? = nil, maxDriveMinutes: Int? = nil, keywords: [String] = [], exclude: [String] = []) {
        self.areaText = areaText
        self.areaMode = areaMode
        self.features = features
        self.windows = windows
        self.dateHint = dateHint
        self.maxDriveMinutes = maxDriveMinutes
        self.keywords = Array(keywords.prefix(Self.maximumKeywords))
        self.exclude = exclude
    }

    /// Search words for text and place-search sources: keywords plus the feature names.
    public var searchTerms: [String] {
        var out: [String] = []
        for t in keywords + features.map(\.singularName) where !out.contains(t) { out.append(t) }
        return out
    }
}

/// Where a plan came from. `.basic` is the deterministic parser, shown as "Basic search".
public enum PlanOrigin: Sendable, Hashable {
    case ai
    /// No model was given to the engine at all (not the same as a model that reports itself unavailable).
    case basicNoModel
    /// `reason` is why the model was not used, when it was unavailable (nil when it failed or timed out).
    case basic(reason: AIUnavailableReason?)

    public var isBasic: Bool { if case .ai = self { return false }; return true }

    /// "Basic search: AI unavailable (Apple Intelligence is turned off)"; nil for `.ai`.
    public var label: String? {
        switch self {
        case .ai: nil
        case .basicNoModel: "Basic search: AI not set up"
        case .basic(let reason?): "Basic search: AI unavailable (\(reason.plainText))"
        case .basic(nil): "Basic search: AI did not answer"
        }
    }
}

extension AIUnavailableReason {
    /// Plain words for the UI.
    public var plainText: String {
        switch self {
        case .deviceNotEligible: "this device cannot run Apple Intelligence"
        case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off"
        case .modelNotReady: "the model is still getting ready"
        case .frameworkUnavailable: "not available on this system"
        case .disabledInSettings: "turned off in Iter settings"
        case .unknown: "reason unknown"
        }
    }
}
