import Foundation
import IterCore
import IterServices
import IterFeatures

/// Phrasing for Search Here and the typed feature search ("peaks in Glacier National Park"): the button, progress,
/// the In View and feature section headers, per-source unavailability, and the sources and elevation on a row. The
/// model reports facts (`SearchHereStatus`, `FeatureSearchStatus`); the words are here. Title-style where it names a
/// thing, plain sentences for a source that could not answer.
extension LightText {
    // MARK: Button and progress

    static let searchHere = String(localized: "Search Here", comment: "Button over the Explore list: search the part of the map in view")
    static let searchHereHelp = String(localized: "Look for places in the part of the map you can see", comment: "Tooltip and VoiceOver hint on the Search Here button")
    static let searchHereCancel = String(localized: "Cancel", comment: "Button: stop a running Search Here")
    static let searchHereCancelHelp = String(localized: "Stop searching and remove the results", comment: "Tooltip on the Cancel button while Search Here runs")

    /// What Search Here is doing now. Maps first, then Ask when it runs, otherwise the web sources.
    static func searchHereProgress(_ status: SearchHereStatus) -> String {
        switch status.phase {
        case .idle, .finished, .searchingMaps:
            String(localized: "Searching Maps…", comment: "Search Here progress: Apple Maps is searching the visible area")
        case .asking:
            if status.ask == .running {
                String(localized: "Asking…", comment: "Search Here progress: Apple Intelligence is naming places in the visible area")
            } else {
                String(localized: "Searching the Web…", comment: "Search Here progress: Wikipedia, OpenStreetMap and the other web sources are being searched")
            }
        }
    }

    // MARK: Source names

    /// "Maps", "Reddit", ...: the short names used in headers and on rows.
    static func shortName(_ source: DiscoverySourceID) -> String {
        switch source {
        case .appleMaps: String(localized: "Maps", comment: "Source name on a result row and in a section header: Apple Maps")
        case .reddit: String(localized: "Reddit", comment: "Source name: Reddit")
        case .wikipedia: String(localized: "Wikipedia", comment: "Source name: Wikipedia")
        case .wikivoyage: String(localized: "Wikivoyage", comment: "Source name: Wikivoyage")
        case .openStreetMap: String(localized: "OpenStreetMap", comment: "Source name: OpenStreetMap")
        case .google: String(localized: "Google", comment: "Source name: Google search")
        }
    }

    static let askSourceName = String(localized: "Ask", comment: "Source name on a result row and in a section header: Apple Intelligence suggested the place")

    /// "Maps + Ask + Wikipedia".
    static func sourceSummary(_ names: [String]) -> String {
        names.joined(separator: String(localized: " + ", comment: "Joins source names in a section header, e.g. Maps + Ask"))
    }

    // MARK: In View

    static func inViewTitle(count: Int) -> String {
        InflectedCount.string("place-in-view", count: count) {
            AttributedString(localized: "^[\(count) Place](inflect: true) in View", comment: "In View section header: number of places Search Here found")
        }
    }

    static let inViewName = String(localized: "In View", comment: "List section: places Search Here found in the visible map area")
    static let noPlacesInView = String(localized: "No Places in View", comment: "Search Here found nothing in the visible map area")

    /// The sources that gave this Search Here at least one place, in the order the app lists them.
    static func inViewSources(_ status: SearchHereStatus) -> [String] {
        var names: [String] = []
        if case .found(let n) = status.maps, n > 0 { names.append(shortName(.appleMaps)) }
        if case .found(let n) = status.ask, n > 0 { names.append(askSourceName) }
        names += discoverySources(status.discovery)
        return names
    }

    /// The honest quiet lines: nothing found, or a source that could not answer. Empty when everything worked.
    static func inViewNotes(_ status: SearchHereStatus) -> [String] {
        var notes: [String] = []
        if status.phase == .finished, status.total == 0, status.maps != .failed { notes.append(noPlacesInView) }
        if status.maps == .failed { notes.append(appleMapsUnavailable) }
        switch status.ask {
        case .unavailable(let availability): notes.append(askUnavailableShort(availability))
        case .failed: notes.append(String(localized: "Ask Iter couldn't finish", comment: "Ask failure title"))
        case .pending, .running, .found, .none: break
        }
        if status.discoveryOutcome == .failed { notes.append(webUnavailable) }
        notes += unavailableSources(status.discovery)
        return notes
    }

    static let appleMapsUnavailable = String(localized: "Apple Maps unavailable", comment: "Search Here or feature search: Apple Maps could not answer")
    static let webUnavailable = String(localized: "Web sources unavailable", comment: "Search Here or feature search: the web sources (Wikipedia, OpenStreetMap, ...) could not be searched")

    static func sourceUnavailable(_ source: DiscoverySourceID) -> String {
        String(localized: "\(shortName(source)) unavailable", comment: "A web source could not answer; the first part is its name, e.g. Reddit unavailable")
    }

    private static func discoverySources(_ statuses: [DiscoverySourceID: DiscoverySourceStatus]) -> [String] {
        DiscoverySourceID.allCases.compactMap { source in
            if case .ok(let n)? = statuses[source], n > 0 { shortName(source) } else { nil }
        }
    }

    private static func unavailableSources(_ statuses: [DiscoverySourceID: DiscoverySourceStatus]) -> [String] {
        DiscoverySourceID.allCases.compactMap { source in
            if case .unavailable? = statuses[source] { sourceUnavailable(source) } else { nil }
        }
    }

    // MARK: Feature search

    /// "Peaks", "Waterfalls", "Hot Springs": the section's plural, or the singular for one.
    static func featureName(_ feature: FeatureKind?, count: Int? = nil) -> String {
        guard let feature else { return String(localized: "Places", comment: "Feature search header when the kind of place is unknown") }
        if count == 1 { return feature.singularName.capitalized }
        return feature == .peak ? String(localized: "Peaks", comment: "Feature search header: mountain peaks") : feature.pluralName.capitalized
    }

    /// The area as the search resolved it, else as typed.
    @MainActor static func featureAreaName(_ explore: ExploreModel) -> String {
        if let name = explore.featureArea?.name, !name.isEmpty { return name }
        return explore.featureStatus.areaName
    }

    /// "24 Peaks in Glacier National Park".
    static func featureTitle(count: Int, feature: FeatureKind?, area: String) -> String {
        let kind = featureName(feature, count: count)
        return String(localized: "\(count) \(kind) in \(area)", comment: "Feature search section header: count, kind of place (Peaks), area name")
    }

    static func featureSources(_ status: FeatureSearchStatus) -> [String] {
        var names: [String] = []
        if case .found(let n) = status.maps, n > 0 { names.append(shortName(.appleMaps)) }
        names += discoverySources(status.sources)
        return names
    }

    static func featureNotes(_ status: FeatureSearchStatus) -> [String] {
        var notes: [String] = []
        if status.maps == .failed { notes.append(appleMapsUnavailable) }
        if status.discoveryFailed { notes.append(webUnavailable) }
        notes += unavailableSources(status.sources)
        return notes
    }

    /// The line under the search field while a search runs: Apple Maps text search, or the feature search's stage.
    static func searchProgress(_ status: FeatureSearchStatus, area: String) -> String {
        switch status.phase {
        case .resolvingArea:
            String(localized: "Finding \(status.areaName)…", comment: "Feature search progress: looking up the named area")
        case .searching:
            String(localized: "Searching \(featureName(status.feature)) in \(area)…", comment: "Feature search progress: kind of place (Peaks) and area name")
        case .idle, .finished:
            searchingApple
        }
    }

    static func areaNotFound(_ area: String) -> String {
        String(localized: "Couldn't find \(area). Showing Apple Maps results.", comment: "Feature search fell back to a plain Apple Maps search because the area was not found")
    }

    /// "Find Peaks in Glacier National Park", the top suggestion for a feature query.
    static func findFeature(_ query: FeatureAreaQuery) -> String {
        String(localized: "Find \(featureName(query.feature)) in \(query.area)", comment: "Search suggestion that lists every place of one kind in a named area, e.g. Find Peaks in Glacier National Park")
    }

    static let findFeatureDetail = String(localized: "Apple Maps and the web sources you've turned on", comment: "Second line of the feature search suggestion")

    // MARK: Prompt prefix

    static let usingShootingNotes = String(localized: "Using your shooting notes", comment: "Under the Ask suggestion when the person wrote what they like to shoot in Settings")

    /// The first part of the notes, for the tooltip.
    static func shootingNotesPreview(_ prefix: String) -> String {
        let flat = prefix.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 40 ? String(flat.prefix(40)) + "…" : flat
    }

    // MARK: Rows

    /// "Maps · Reddit · Wikipedia": every source that lists the place; Ask marked when it suggested it.
    static func sourcesLine(_ row: ExploreRow) -> String? {
        var names: [String] = []
        for source in DiscoverySourceID.allCases where row.sources.contains(source) {
            names.append(shortName(source))
            if source == .appleMaps, row.viaAsk { names.append(askSourceName) }
        }
        if row.viaAsk, !names.contains(askSourceName) { names.append(askSourceName) }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }

    /// "2,938 m" in metric regions, feet where people read heights in feet.
    static func elevation(meters: Double, locale: Locale = .current) -> String {
        let metric = locale.measurementSystem == .metric
        let value = Measurement(value: meters, unit: UnitLength.meters).converted(to: metric ? .meters : .feet)
        return value.formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                            numberFormatStyle: .number.precision(.fractionLength(0)).locale(locale)).locale(locale))
    }

    /// The sources and elevation as one quiet line, or nil when the row has neither.
    static func provenanceLine(_ row: ExploreRow) -> String? {
        let parts = [sourcesLine(row), row.elevationMeters.map { elevation(meters: $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
