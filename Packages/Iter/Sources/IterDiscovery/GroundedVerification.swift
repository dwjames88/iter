import Foundation
import IterModel
import IterSources

// THE GROUNDING INVARIANT (BLUEPRINT §7 step 5).
//
// Every place Find returns carries a coordinate that came from a non-model source. This is enforced by the type system:
//
//  * `DiscoveredPlace.coordinate` is a `GroundedCoordinate`.
//  * `GroundedCoordinate`'s only initialiser is `fileprivate` to THIS file, and the only callers are in this file, and
//    they read the value from a provider-returned `PlaceCandidate.coordinate` or `GeocodeResult.coordinate`.
//  * Everything the model produces (`QueryPlanDTO`, `ExtractionDTO`, explanation text) is built from `String`, `Int` and
//    `Bool` only; `AISchema` has no floating-point case, so it cannot express a coordinate. Names the model returns are
//    only names: they are geocoded here, inside the area, with a name match.
//  * Later stages (merge, rank, explain) copy `GroundedCoordinate` values; they cannot create one.
//
// `GroundingTests` checks that no other source file calls the initialiser.

/// Where a grounded coordinate came from.
public enum CoordinateBasis: String, Sendable, Hashable {
    /// A source listed the place with this coordinate (OSM, GNIS, MapKit, Wikipedia).
    case structuredSource
    /// A geocoder or place search located a name taken from a document.
    case geocodedName
}

/// A coordinate with the source that supplied it. It cannot be made outside `GroundedVerification.swift`.
public struct GroundedCoordinate: Hashable, Sendable {
    public let value: Coordinate
    public let source: SourceID
    public let basis: CoordinateBasis

    fileprivate init(value: Coordinate, source: SourceID, basis: CoordinateBasis) {
        self.value = value
        self.source = source
        self.basis = basis
    }

    public var latitude: Double { value.latitude }
    public var longitude: Double { value.longitude }

    /// How much this coordinate is trusted when places are merged: OSM and GNIS points over Wikipedia over MapKit over a
    /// geocoded name.
    var precisionRank: Int {
        if basis == .geocodedName { return 2 }
        switch source.family {
        case "osm", "usgs": return 6
        case "wikipedia", "wikidata": return 5
        case "apple": return 3
        default: return 4
        }
    }
}

extension SourceID {
    /// The operator family: "apple" for every MapKit source, "osm", "wikipedia". Sources of one family are not independent.
    var family: String { String(rawValue.split(separator: ".").first ?? Substring(rawValue)) }
}

/// A candidate that passed verification: it has a grounded coordinate inside the area and a name.
struct VerifiedCandidate: Sendable, Hashable {
    var name: String
    var coordinate: GroundedCoordinate
    var elevationMeters: Double?
    var featureKinds: [FeatureKind]
    var sources: [SourceID]
    /// Sources that vouch for the place with a stable id (OSM, GNIS, a Wikipedia page with coordinates).
    var stableSources: Set<SourceID>
    var citations: [Citation]
    var mentionCount: Int
    var snippet: String?
    var externalIDs: [String]

    /// Independent families among `sources`.
    var independentSourceCount: Int { Set(sources.map(\.family)).count }

    /// `confirmed` for two or more independent sources, or one structured source with a stable id; else `singleSource`.
    var verification: Verification {
        (independentSourceCount >= 2 || !stableSources.isEmpty) ? .confirmed : .singleSource
    }
}

/// A name taken from a document by the extractor, with nothing located yet.
struct ExtractedName: Sendable, Hashable {
    var name: String
    var featureHint: FeatureKind?
    var source: SourceID
    var citation: Citation
    var snippet: String?
}

enum CandidateVerifier {
    /// Sources whose ids are stable and which give coordinates.
    static let stableSources: Set<SourceID> = [.osmOverpass, .usgsGNIS, .wikipedia, "wikidata", "nga.gns"]

    /// Structured candidates keep their own coordinate if the area contains it. Nil: no coordinate, no name, or outside.
    static func verifyStructured(_ c: PlaceCandidate, in area: DiscoveryArea) -> VerifiedCandidate? {
        try? check(c, in: area).get()
    }

    /// As `verifyStructured`, saying why a candidate was dropped. Dropping is deliberate: no usable name, no coordinate from
    /// the source, a nonsense coordinate, or a coordinate outside the area (its outline when it has one).
    static func check(_ c: PlaceCandidate, in area: DiscoveryArea) -> Result<VerifiedCandidate, DropReason> {
        guard let name = cleanName(c.name) else { return .failure(.noName) }
        guard let provided = c.coordinate else { return .failure(.noCoordinate) }
        guard valid(provided) else { return .failure(.invalidCoordinate) }
        guard area.contains(provided) else { return .failure(.outsideArea) }
        let grounded = GroundedCoordinate(value: provided, source: c.source, basis: .structuredSource)
        let stable = stableSources.contains(c.source) && c.externalID != nil
        return .success(VerifiedCandidate(name: name, coordinate: grounded, elevationMeters: c.elevationMeters, featureKinds: unique(c.featureKinds),
                                 sources: [c.source], stableSources: stable ? [c.source] : [], citations: c.citations,
                                 mentionCount: c.mentionCount, snippet: c.snippet, externalIDs: c.externalID.map { ["\(c.source.rawValue):\($0)"] } ?? []))
    }

    /// A name from a document is located by a geocoder, then by place search, inside the area, and accepted only when the
    /// result's name matches (normalised) and the area contains its coordinate.
    static func verifyNamed(_ n: ExtractedName, area: DiscoveryArea, geocoders: [any Geocoder], placeSearch: [any PlaceSearchProvider],
                            timeout: @Sendable (SourceDescriptor) -> Duration) async -> VerifiedCandidate? {
        guard let name = cleanName(n.name) else { return nil }
        let query = [name, area.name].compactMap { $0 }.joined(separator: ", ")
        var located: GroundedCoordinate?
        var locatedElevation: Double?
        var locatedKinds: [FeatureKind] = []

        for g in geocoders where located == nil {
            if Task.isCancelled { return nil }
            let limit = timeout(g.descriptor)
            guard let results = try? await withDeadline(limit, { try await g.geocode(query, near: area.region) }) else { continue }
            if let hit = results.first(where: { DiscoveryNames.matches($0.name, name) && valid($0.coordinate) && area.contains($0.coordinate) }) {
                located = GroundedCoordinate(value: hit.coordinate, source: g.descriptor.id, basis: .geocodedName)
            }
        }
        for p in placeSearch where located == nil {
            if Task.isCancelled { return nil }
            let limit = timeout(p.descriptor)
            guard let results = try? await withDeadline(limit, { try await p.search(name, near: area.region) }) else { continue }
            if let hit = results.first(where: { r in
                guard let c = r.coordinate else { return false }
                return DiscoveryNames.matches(r.name, name) && valid(c) && area.contains(c)
            }), let c = hit.coordinate {
                located = GroundedCoordinate(value: c, source: p.descriptor.id, basis: .geocodedName)
                locatedElevation = hit.elevationMeters
                locatedKinds = hit.featureKinds
            }
        }
        guard let located else { return nil }
        var sources = [n.source]
        if !sources.contains(located.source) { sources.append(located.source) }
        return VerifiedCandidate(name: name, coordinate: located, elevationMeters: locatedElevation,
                                 featureKinds: unique((n.featureHint.map { [$0] } ?? []) + locatedKinds), sources: sources, stableSources: [],
                                 citations: [n.citation], mentionCount: 1, snippet: n.snippet, externalIDs: [])
    }

    /// A name worth keeping: trimmed, bracketed text and anything that looks like a coordinate removed, not empty.
    static func cleanName(_ raw: String) -> String? {
        var text = raw
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") { text.removeSubrange(open...close) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,;:.\"'"))
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.count >= 2, text.count <= 90, text.contains(where: \.isLetter) else { return nil }
        if text.firstMatch(of: /-?\d{1,3}\.\d{2,}/) != nil { return nil }   // a decimal-degree number in a name
        return text
    }

    private static func valid(_ c: Coordinate) -> Bool {
        c.latitude.isFinite && c.longitude.isFinite && abs(c.latitude) <= 90 && abs(c.longitude) <= 180
    }

    private static func unique(_ kinds: [FeatureKind]) -> [FeatureKind] {
        var out: [FeatureKind] = []
        for k in kinds where !out.contains(k) { out.append(k) }
        return out
    }
}

/// Why a structured candidate was not kept.
public enum DropReason: String, Error, Sendable, Hashable {
    case noName, noCoordinate, invalidCoordinate, outsideArea
}

/// A candidate a source offered that verification dropped, for diagnostics.
public struct DroppedCandidate: Sendable, Hashable {
    public var name: String
    public var source: SourceID
    public var reason: DropReason
}
