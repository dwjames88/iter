import Foundation
import IterModel
import IterSources
import IterDiscovery

// Plain `Equatable` values the Find screens draw. Nothing here reads a clock or touches a service.

/// What the Find surface is doing.
public enum FindPhase: Equatable, Sendable {
    /// Nothing searched.
    case idle
    /// A typed place search (saved places and Apple Maps) is running.
    case lookingUp
    /// AI discovery is running (planning, resolving the area, or searching sources).
    case discovering
    case finished
    /// The run could not search at all; the text is ready to show.
    case failed(String)
    case cancelled
}

/// How one source row reads. The chip colours and symbols hang off this, not off the text.
public enum SourceChipState: Equatable, Sendable {
    case searching
    /// Still searching after longer than the slow threshold (Overpass queues for 30 s and answers 502 or 504 often).
    case slow
    case found(Int)
    case empty
    /// Failed or timed out: the source is down for this run.
    case down
    /// Cannot be used at all (no key, closed to new users, AI off).
    case unavailable
    /// Not asked, with a plain reason.
    case skipped
}

/// One row of the per-source list for a run.
public struct SourceChip: Equatable, Identifiable, Sendable {
    public var id: String
    public var sourceID: SourceID
    public var name: String
    public var role: SourceRole
    public var state: SourceChipState
    /// "OpenStreetMap: 14", "Reddit: needs your own Reddit API access; ...", "OpenStreetMap: still searching (slow)".
    public var text: String
    /// The plain reason for unavailable, skipped and down rows; nil otherwise.
    public var reason: String?

    public init(id: String, sourceID: SourceID, name: String, role: SourceRole, state: SourceChipState, text: String, reason: String? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.role = role
        self.state = state
        self.text = text
        self.reason = reason
    }

    /// True while the source can still add results.
    public var isWorking: Bool { state == .searching || state == .slow }
    /// True when the row counts toward "sources done of total" (unavailable and skipped sources are not asked).
    public var isAsked: Bool { state != .unavailable && state != .skipped }

    static func make(_ status: SourceStatus, slow: Bool) -> SourceChip {
        let state: SourceChipState
        var reason: String?
        var text = status.summary
        switch status.state {
        case .searching:
            state = slow ? .slow : .searching
            if slow { text = "\(status.name): still searching (slow)"; reason = "Waiting longer than usual; other sources are not held up." }
        case .found(let n): state = .found(n)
        case .empty: state = .empty
        case .failed:
            state = .down
            reason = status.summary.replacingOccurrences(of: "\(status.name): ", with: "")
        case .timedOut:
            state = .down
            reason = "Timed out"
        case .skipped(let why): state = .skipped; reason = why
        case .unavailable(let why): state = .unavailable; reason = why
        }
        return SourceChip(id: status.id, sourceID: status.source, name: status.name, role: status.role, state: state, text: text, reason: reason)
    }
}

/// "3 of 7 sources done, 4 s".
public struct FindProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var elapsed: TimeInterval
    public var isRunning: Bool

    public init(done: Int = 0, total: Int = 0, elapsed: TimeInterval = 0, isRunning: Bool = false) {
        self.done = done
        self.total = total
        self.elapsed = elapsed
        self.isRunning = isRunning
    }

    /// 0...1, nil until a source has been asked.
    public var fraction: Double? { total > 0 ? Double(done) / Double(total) : nil }
}

/// The area a run searched, for the map outline and the sentence under the field.
public struct FindArea: Equatable, Sendable {
    public var name: String?
    public var region: GeoRegion
    /// The real outline when a boundary source had one; empty otherwise (the map draws the box).
    public var outline: [[Coordinate]]
    public var hasRealBoundary: Bool
    /// "Outline from OpenStreetMap", "Box of 30 km around the town", "The map area you were looking at".
    public var basisText: String
    public var citation: Citation?

    public init(name: String?, region: GeoRegion, outline: [[Coordinate]], hasRealBoundary: Bool, basisText: String, citation: Citation?) {
        self.name = name
        self.region = region
        self.outline = outline
        self.hasRealBoundary = hasRealBoundary
        self.basisText = basisText
        self.citation = citation
    }

    static func make(_ r: ResolvedArea) -> FindArea {
        let basis: String
        switch r.basis {
        case .currentLocation(let km): basis = "Within \(Int(km.rounded())) km of you"
        case .visibleMap: basis = "The map area you were looking at"
        case .boundary(let name, _): basis = "Outline of \(name)" + (r.boundaryCitation.map { " from \($0.title)" } ?? "")
        case .box(let km, let why): basis = "Box of \(Int(km.rounded())) km (\(why)); no outline"
        case .geocodedRegion: basis = "The region Apple Maps gives for it; no outline"
        default: basis = "Area box, no outline found"
        }
        return FindArea(name: r.area.name ?? r.geocodedName, region: r.area.region, outline: r.area.boundary?.rings ?? [],
                        hasRealBoundary: r.hasRealBoundary, basisText: basis, citation: r.boundaryCitation)
    }
}

/// Where a result's time comes from. Never presented as a drive until a router has answered.
public enum FindDriveBasis: Equatable, Sendable {
    /// A real drive time from the router, departing now.
    case drive
    /// Straight-line distance at a typical road speed. Labelled "straight-line".
    case straightLine
}

public struct DriveTime: Equatable, Sendable {
    public var basis: FindDriveBasis
    public var minutes: Int
    public init(basis: FindDriveBasis, minutes: Int) {
        self.basis = basis
        self.minutes = minutes
    }
    /// "25 min drive", "~25 min straight-line", "1 h 5 min drive".
    public var text: String {
        let m = minutes >= 60 ? "\(minutes / 60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min") : "\(minutes) min"
        return basis == .drive ? "\(m) drive" : "~\(m) straight-line"
    }
}

/// How well the light suits the place. Discovered places have no facing, so this is honestly unknown for them.
public struct LightSuit: Equatable, Sendable {
    public var facingKnown: Bool
    /// 0...1 when known.
    public var value: Double?
    public var note: String
    public init(facingKnown: Bool, value: Double? = nil, note: String) {
        self.facingKnown = facingKnown
        self.value = value
        self.note = note
    }
    /// "Light suit unknown: no facing" for a place with none.
    public var text: String { facingKnown ? note : "Light suit unknown: no facing" }
}

public enum DistanceBasis: Equatable, Sendable {
    case fromYou
    case fromAreaCentre
}

/// One result in the list. Equatable, so a list that is handed the same row does not redraw.
public struct FindRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// "Waterfall, Viewpoint".
    public var kindsText: String
    public var kinds: [FeatureKind]
    public var coordinate: Coordinate
    public var why: String?
    public var whyIsModelWritten: Bool
    public var verification: Verification
    /// "Confirmed by 3 sources" / "One source: OpenStreetMap".
    public var verificationLabel: String
    public var sourceNames: [String]
    public var photo: LicensedPhoto?
    public var photoCount: Int
    public var distanceKm: Double?
    public var distanceBasis: DistanceBasis
    public var drive: DriveTime?
    public var lightSuit: LightSuit
    public var isSaved: Bool
    /// True while a router answer is on its way for this row.
    public var isFetchingDrive: Bool

    /// "23 km from you", "23 km from the search centre".
    public var distanceText: String? {
        guard let km = distanceKm else { return nil }
        let v = km < 10 ? String(format: "%.1f", km) : "\(Int(km.rounded()))"
        return "\(v) km " + (distanceBasis == .fromYou ? "from you" : "from the search centre")
    }
}

/// One kind in the filter list.
public struct KindFilter: Equatable, Identifiable, Sendable {
    public var kind: FeatureKind
    public var count: Int
    public var isOn: Bool
    public var id: String { kind.rawValue }
    public var title: String { count == 1 ? kind.singularName.capitalized : kind.pluralName.capitalized }
}

/// A typed-search match: one of the owner's saved places or an Apple Maps result.
public struct PlaceMatch: Equatable, Identifiable, Sendable {
    public enum Origin: Equatable, Sendable { case saved, appleMaps }
    public var id: String
    public var name: String
    public var subtitle: String
    public var coordinate: Coordinate
    public var origin: Origin
    public var place: Place
}

/// What Return would run for the current text, and the Ask Iter suggestion beside it.
public struct FindSuggestions: Equatable, Sendable {
    /// The query for the local lookup (saved places and Apple Maps); nil for blank text.
    public var lookup: String?
    /// Set when the text reads like a request ("waterfalls near Lone Pine at sunrise"): the Ask Iter row.
    public var ask: String?
    /// Set when the text is "<feature> in <area>": Return runs it as a discovery search.
    public var feature: FeatureAreaQuery?
    public static let none = FindSuggestions(lookup: nil, ask: nil, feature: nil)
}

/// A pin on the Find map. Values only; the view maps them to annotations.
public struct FindPin: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A discovery result at this rank (1 = best).
        case result(rank: Int)
        case saved
        /// One of the owner's own spots. Never clusters, and can be dragged.
        case own
        case match
    }
    public var id: String
    public var coordinate: Coordinate
    public var title: String
    public var kind: Kind
    public var isMovable: Bool { kind == .own }
}

/// A cluster of nearby result pins at the current zoom.
public struct FindCluster: Equatable, Identifiable, Sendable {
    public var id: String
    public var coordinate: Coordinate
    public var count: Int
    public var memberIDs: [String]
}

/// Everything the map draws for Find, computed off the view's body.
public struct FindMapContent: Equatable, Sendable {
    /// Pins that stand alone (every own spot is here).
    public var pins: [FindPin]
    public var clusters: [FindCluster]
    public var outline: [[Coordinate]]
    public var areaRegion: GeoRegion?
    public static let empty = FindMapContent(pins: [], clusters: [], outline: [], areaRegion: nil)
}

/// A trip in the Add to Trip list.
public struct TripChoice: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var dayCount: Int
    public var stopCount: Int
}

/// Whether Look Around covers the selected place; the card shows the satellite fallback when it does not.
public enum LookAroundAvailability: Equatable, Sendable {
    case unknown
    case checking
    case available
    /// No coverage, or no provider: show the satellite view instead.
    case satelliteFallback
}

/// A citation as the card lists it.
public struct CardCitation: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var sourceName: String
    public var url: URL?
    public var licence: String?
}

/// The place card for the selected result, typed match or own spot.
public struct PlaceCard: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case discovered, saved, own, match }
    public var id: String
    public var kind: Kind
    public var name: String
    public var locality: String
    public var why: String?
    public var whyIsModelWritten: Bool
    public var sourceNames: [String]
    public var verification: Verification?
    public var verificationLabel: String?
    public var citations: [CardCitation]
    public var photo: LicensedPhoto?
    public var distanceText: String?
    public var drive: DriveTime?
    public var lightSuit: LightSuit
    public var isSaved: Bool
    public var coordinate: Coordinate
    /// What Save, Add to Trip and Open in Maps act on.
    public var place: Place
    public var isOwn: Bool { kind == .own }
}
