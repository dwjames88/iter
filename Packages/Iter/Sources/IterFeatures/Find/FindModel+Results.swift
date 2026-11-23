import Foundation
import IterModel
import IterSources
import IterStore
import IterDiscovery

// Rows, filters, ordering and map content for Find. Everything here is a pure rebuild of values from `raw`, the
// preferences, the location and the drive times that have arrived; no network and no refetch.

extension FindModel {
    /// Popular, Unique or Mixed. Changing it re-orders the places already found; nothing is fetched again.
    public var ordering: DiscoveryOrdering {
        get { preferences.ordering }
        set {
            guard newValue != preferences.ordering else { return }
            preferences.ordering = newValue
            rebuildRows()
        }
    }

    // MARK: Filters

    public func toggleKind(_ kind: FeatureKind) {
        if selectedKinds.contains(kind) { selectedKinds.remove(kind) } else { selectedKinds.insert(kind) }
        rebuildRows()
    }

    public func clearKindFilters() {
        guard !selectedKinds.isEmpty else { return }
        selectedKinds = []
        rebuildRows()
    }

    // MARK: Rows

    /// The places in the order for the current preference: strict matches first, then the ordering's score, then name.
    func orderedPlaces() -> [DiscoveredPlace] {
        let ordering = preferences.ordering
        return raw.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.rank.matchTier != y.rank.matchTier { return x.rank.matchTier < y.rank.matchTier }
            let sx = x.rank.score(for: ordering), sy = y.rank.score(for: ordering)
            if abs(sx - sy) > 1e-9 { return sx > sy }
            return a.offset < b.offset
        }.map(\.element)
    }

    func rebuildRows() {
        let ordered = orderedPlaces()
        var counts: [FeatureKind: Int] = [:]
        for p in ordered { for k in Set(p.featureKinds) { counts[k, default: 0] += 1 } }
        let filters = FeatureKind.allCases.compactMap { k in counts[k].map { KindFilter(kind: k, count: $0, isOn: selectedKinds.contains(k)) } }
        if filters != kindFilters { kindFilters = filters }
        let shown = selectedKinds.isEmpty ? ordered : ordered.filter { !selectedKinds.isDisjoint(with: $0.featureKinds) }
        let next = shown.map(makeRow)
        if next != rows { rows = next }
        rebuildMapContent()
        refreshScoreRequests()
    }

    /// Rebuilds one row (a drive time arrived, a place was saved) without touching the others.
    func refreshRow(_ id: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }), let d = raw.first(where: { $0.id == id }) else { return }
        let row = makeRow(d)
        if row != rows[i] { rows[i] = row }
    }

    var sourceNames: [SourceID: String] {
        var out: [SourceID: String] = [:]
        for s in rawStatuses { out[s.source] = s.name }
        return out
    }

    func name(of source: SourceID, in names: [SourceID: String]) -> String {
        names[source] ?? SourceCatalogue.descriptor(source)?.name ?? source.rawValue
    }

    func makeRow(_ d: DiscoveredPlace) -> FindRow {
        let names = sourceNames
        let (km, basis) = distance(of: d)
        return FindRow(
            id: d.id, name: d.name, kindsText: d.featureKinds.map { $0.singularName.capitalized }.joined(separator: ", "),
            kinds: d.featureKinds, coordinate: d.coordinate.value, why: d.why?.text, whyIsModelWritten: d.why?.isModelWritten ?? false,
            verification: d.verification, verificationLabel: verificationLabel(d, names: names),
            sourceNames: d.sources.map { name(of: $0, in: names) }, photo: d.photos.first, photoCount: d.photoCount,
            distanceKm: km, distanceBasis: basis, drive: driveTime(id: d.id, km: km, basis: basis), lightSuit: lightSuit(of: d),
            isSaved: library.places.isSaved(placeForRow(d)), isFetchingDrive: fetchingDrive.contains(d.id), score: scoreValues[d.id])
    }

    func distance(of d: DiscoveredPlace) -> (Double?, DistanceBasis) {
        if let you = location.current { return (you.distance(to: d.coordinate.value) / 1000, .fromYou) }
        return (d.distanceKm, .fromAreaCentre)
    }

    /// A real drive time once the router answered; before that, a straight-line estimate, labelled so, and only from you.
    func driveTime(id: String, km: Double?, basis: DistanceBasis) -> DriveTime? {
        if let s = driveSeconds[id] { return DriveTime(basis: .drive, minutes: max(1, Int((s / 60).rounded()))) }
        guard basis == .fromYou, let km else { return nil }
        // The same assumption `Leg.estimate` makes: 1.3 times the straight line at 70 km/h.
        return DriveTime(basis: .straightLine, minutes: max(1, Int((km * 1.3 / 70 * 60).rounded())))
    }

    func lightSuit(of d: DiscoveredPlace) -> LightSuit {
        if let v = d.rank.lightSuit.value { return LightSuit(facingKnown: true, value: v, note: d.rank.lightSuit.note) }
        return LightSuit(facingKnown: false, value: nil, note: d.rank.lightSuit.note)
    }

    func verificationLabel(_ d: DiscoveredPlace, names: [SourceID: String]) -> String {
        switch d.verification {
        case .confirmed: "Confirmed by \(max(2, d.sources.count)) sources"
        case .singleSource: "One source: " + (d.sources.first.map { name(of: $0, in: names) } ?? "unknown")
        case .userPlaced: "Placed by you"
        }
    }

    // MARK: Map content

    /// Re-reads the library's saved and own places for the map.
    public func refreshLibraryPins() {
        rebuildMapContent()
    }

    func rebuildMapContent() {
        var singles: [FindPin] = []
        // Library places: yours never cluster; saved ones are few enough to stay single.
        for p in library.places.savedValues() {
            singles.append(FindPin(id: "place:\(p.id.uuidString)", coordinate: p.coordinate, title: p.name, kind: p.origin == .user ? .own : .saved))
        }
        for m in matches { singles.append(FindPin(id: m.id, coordinate: m.coordinate, title: m.name, kind: .match)) }
        let resultPins = rows.enumerated().map { FindPin(id: $0.element.id, coordinate: $0.element.coordinate, title: $0.element.name, kind: .result(rank: $0.offset + 1), score: $0.element.score) }
        let grouped = FindPinClusterer.cluster(resultPins.map { ($0.id, $0.coordinate) }, region: region, viewportWidth: viewportWidth)
        let single = Set(grouped.singles)
        singles += resultPins.filter { single.contains($0.id) }
        let next = FindMapContent(pins: singles, clusters: grouped.clusters, outline: area?.outline ?? [], areaRegion: area?.region)
        if next != mapContent { mapContent = next }
    }
}
