import Foundation
import Observation
import IterModel
import IterSources
import IterDiscovery

/// Settings ▸ General, Search and Sources & Credits (updates are the Mac shell's). `@MainActor @Observable`; takes the
/// preferences, the key vault and the source descriptors, never the container. Keys go through `KeyVault` only and are never
/// logged, printed or kept here.
@MainActor @Observable
public final class SettingsModel {
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let keyVault: KeyVault
    @ObservationIgnored private let descriptors: [SourceDescriptor]
    @ObservationIgnored private let dataMode: DataMode

    /// Bumped when a key is added or removed, so key rows (read from the Keychain) refresh.
    private var keyRevision = 0

    public init(preferences: Preferences, keyVault: KeyVault, sources: [SourceDescriptor], dataMode: DataMode = .live) {
        self.preferences = preferences
        self.keyVault = keyVault
        descriptors = sources
        self.dataMode = dataMode
    }

    // MARK: General

    /// "hybrid" (default), "standard" or "imagery".
    public var mapStyle: String {
        get { preferences.mapStyle }
        set { preferences.mapStyle = newValue }
    }
    public var showDaylight: Bool {
        get { preferences.showDaylight }
        set { preferences.showDaylight = newValue }
    }
    public static let mapStyles: [(id: String, title: String)] = [("hybrid", "Hybrid"), ("standard", "Standard"), ("imagery", "Satellite")]

    // MARK: Search

    /// "What I Like to Shoot". Matched by words when ranking; never sent to a source.
    public var preferenceText: String {
        get { preferences.preferenceText }
        set { preferences.preferenceText = newValue }
    }
    public var ordering: DiscoveryOrdering {
        get { preferences.ordering }
        set { preferences.ordering = newValue }
    }
    public var resultCap: Int {
        get { preferences.resultCap }
        set { preferences.resultCap = min(Self.resultCapRange.upperBound, max(Self.resultCapRange.lowerBound, newValue)) }
    }
    public static let resultCapRange = 10...100

    /// Every source Find can use, plus Reddit and Google as unavailable rows with their reasons.
    public var discoverySources: [SourceRow] {
        rows.filter { !$0.dataKinds.isDisjoint(with: Self.discoveryKinds) || Self.unavailableIDs.contains($0.id) }
    }

    // MARK: Sources & Credits

    /// One row per source the app knows, then Reddit and Google.
    public var rows: [SourceRow] {
        let settings = SourceSettings.current(preferences, keys: keyVault)
        _ = keyRevision
        let known = descriptors.sorted { ($0.tier, $0.name) < ($1.tier, $1.name) }.map { row(for: $0, settings: settings) }
        return known + Self.unavailableRows
    }

    /// Sources grouped by origin tier, military first (the owner's preference), for the credits list.
    public var rowsByTier: [(tier: SourceTier, rows: [SourceRow])] {
        let all = rows
        return SourceTier.allCases.compactMap { tier in
            let group = all.filter { $0.tier == tier }
            return group.isEmpty ? nil : (tier, group)
        }
    }

    /// What no source supplies today.
    public var namedGaps: [NamedGap] {
        [
            NamedGap(title: "Light Pollution", explanation: "No free source of sky brightness allows use in an app, so Iter shows no Bortle number and says so."),
            NamedGap(title: "Seeing and Transparency", explanation: "No free source allows commercial use, so night scores leave seeing out and say so."),
        ]
    }

    /// Switch a source on or off. Discovery sources apply on the next search, conditions sources on the next launch
    /// (`SourceRow.toggleTiming` says which). A source that is off by default is switched ON through an override.
    public func setSource(_ id: SourceID, enabled: Bool) {
        guard let d = descriptors.first(where: { $0.id == id }), row(for: d, settings: SourceSettings()).isToggleable else { return }
        if enabled {
            preferences.disabledSources.remove(id)
            if !d.enabledByDefault { preferences.enabledOverrides.insert(id) }
        } else {
            preferences.disabledSources.insert(id)
            preferences.enabledOverrides.remove(id)
        }
    }

    // MARK: Keys

    /// The sources that accept an optional key (or require one). Empty today: every source Iter uses is free and keyless.
    public var keyRows: [KeyRow] {
        _ = keyRevision
        return descriptors.compactMap { d -> KeyRow? in
            switch d.key {
            case .none: nil
            case .optional(let id): KeyRow(id: id, sourceName: d.name, isRequired: false, hasKey: keyVault.key(for: id) != nil)
            case .required(let id): KeyRow(id: id, sourceName: d.name, isRequired: true, hasKey: keyVault.key(for: id) != nil)
            }
        }
    }

    /// The sentence the Keys section shows.
    public var keysSummary: String {
        keyRows.isEmpty
            ? "No source Iter uses needs a key. Every source is free, and none asks you to sign up."
            : "These sources can use a key of your own. Keys stay in your Keychain."
    }

    public func setKey(_ key: String, for source: SourceID) throws {
        try keyVault.setKey(key, for: source)
        keyRevision += 1
    }

    public func removeKey(for source: SourceID) throws {
        try keyVault.removeKey(for: source)
        keyRevision += 1
    }

    // MARK: Row building

    static let discoveryKinds: Set<DataKind> = [.places, .gazetteer, .textEvidence, .photoEvidence, .geocode, .boundary]
    private static let conditionsKinds: Set<DataKind> = [.forecast, .observation, .nowcast, .alerts, .aurora, .smoke, .aerosol, .elevation, .horizon,
                                                          .imagery, .satelliteCloud]   // map overlays read the same switches when they next load

    static let unavailableRows: [SourceRow] = [
        unavailable(FixedSources.reddit, "Reddit", "Reddit", FixedSources.redditReason),
        unavailable(FixedSources.google, "Google", "Google", FixedSources.googleReason),
    ]
    static let unavailableIDs: Set<SourceID> = [FixedSources.reddit, FixedSources.google]

    private static func unavailable(_ id: SourceID, _ name: String, _ operatorName: String, _ reason: String) -> SourceRow {
        SourceRow(id: id, name: name, operatorName: operatorName, tier: .userKey, originLabel: "Your own access", isMilitaryOrigin: false,
                  kinds: ["Text evidence"], coverage: "Worldwide", status: .unavailable(reason), toggleTiming: .never,
                  attributionShort: "", attributionFull: "Not used: \(reason).", attributionURL: nil, termsURL: nil, dataKinds: [.textEvidence])
    }

    private func row(for d: SourceDescriptor, settings: SourceSettings) -> SourceRow {
        let status: SourceRowStatus
        if settings.disabled.contains(d.id) { status = .disabled }
        else if !d.enabledByDefault && !settings.enabledOverrides.contains(d.id) { status = .offByDefault }
        else if !settings.keySatisfied(d) { status = .needsKey }
        else { status = .enabled }

        let attribution = Attribution.text(for: d.licence.key)
        let isSample = d.licence.key == SampleConditions.licenceKey
        let timing: ToggleTiming = {
            guard !d.kinds.isDisjoint(with: Self.discoveryKinds.union(Self.conditionsKinds)), !isSample, d.id != .appleLookAround else { return .never }
            return d.kinds.isDisjoint(with: Self.discoveryKinds) ? .nextLaunch : .nextSearch
        }()
        return SourceRow(
            id: d.id, name: d.name, operatorName: d.operatorName, tier: d.origin.tier, originLabel: Self.originLabel(d),
            isMilitaryOrigin: d.origin.tier == .military,
            kinds: d.kinds.map(Self.kindName).sorted(), coverage: Self.coverageName(d.coverage), status: status, toggleTiming: timing,
            attributionShort: isSample ? "Sample data" : (attribution?.short ?? ""),
            attributionFull: isSample ? SampleConditions.attributionText : (attribution?.full ?? "No attribution text is registered for this source."),
            attributionURL: attribution?.url, termsURL: d.termsURL, dataKinds: d.kinds)
    }

    /// "Military-origin via NOAA Aviation Weather Center (military airfields)", "Military-origin via NOAA NCEI, computed on
    /// this device", "Government (NOAA NCEP)". Honest about mixed feeds: METAR is military-origin only for military airfields.
    static func originLabel(_ d: SourceDescriptor) -> String {
        let o = d.origin
        guard o.tier == .military else { return o.label }
        var text = "Military-origin"
        if let via = o.distributor, !via.isEmpty { text += " via \(via)" }
        else if o.computedOnDevice { text += " standard (\(o.producer))" }
        if o.producer.localizedCaseInsensitiveContains("civil") { text += " for military airfields; civil stations are government" }
        if o.computedOnDevice { text += ", computed on this device" }
        return text
    }

    static func kindName(_ k: DataKind) -> String {
        switch k {
        case .places: "Place search"
        case .gazetteer: "Named places"
        case .textEvidence: "Text evidence"
        case .photoEvidence: "Photo evidence"
        case .geocode: "Place lookup"
        case .forecast: "Forecast"
        case .observation: "Observations"
        case .nowcast: "Nowcast"
        case .aerosol: "Aerosols"
        case .smoke: "Smoke"
        case .airQuality: "Air quality"
        case .satelliteCloud: "Satellite cloud"
        case .lightPollution: "Light pollution"
        case .aurora: "Aurora"
        case .astronomy: "Astronomy"
        case .elevation: "Elevation"
        case .horizon: "Horizon"
        case .routing: "Routing"
        case .eta: "Drive times"
        case .imagery: "Imagery"
        case .alerts: "Alerts"
        case .seeing: "Seeing"
        case .magnetic: "Magnetic declination"
        case .gridReference: "Grid reference"
        case .boundary: "Area outlines"
        }
    }

    static func coverageName(_ c: Coverage) -> String {
        if case .global = c { return "Worldwide" }
        let moab = Coordinate(latitude: 38.57, longitude: -109.55), paris = Coordinate(latitude: 48.85, longitude: 2.35)
        let tokyo = Coordinate(latitude: 35.68, longitude: 139.69), ottawa = Coordinate(latitude: 45.42, longitude: -75.70)
        if c.contains(moab), c.contains(paris), c.contains(tokyo) { return "Worldwide" }
        if c.contains(moab) { return c.contains(ottawa) ? "North America" : "United States" }
        if c.contains(paris) { return "Europe, Africa and the Atlantic" }
        if c.contains(tokyo) { return "Asia and the Pacific" }
        return "Part of the world"
    }
}
