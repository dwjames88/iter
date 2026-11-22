import Foundation
import IterModel
import IterSources

/// One source's answer, in preference order, as the composite builder reads it.
struct CompositeInput: Sendable {
    var descriptor: SourceDescriptor
    var state: DataState<HourlySeries>
}

/// The composite of several sources' series (BLUEPRINT §6.3): every field of every hour comes from the first source, in
/// preference order, that has it at that hour. Pure.
struct CompositeForecast: Sendable {
    var series: HourlySeries
    var state: DataState<HourlySeries>
    var fieldProvenance: [FieldProvenance]
    var smokeOpticalDepth: SmokeOpticalDepth?
    /// The best source (in order) other than the one that supplied total cloud, with its series, for the spread rule.
    var comparison: (descriptor: SourceDescriptor, sourced: Sourced<HourlySeries>)?
    /// Sources that supplied at least one value.
    var contributing: [SourceDescriptor]

    /// - Parameters:
    ///   - inputs: candidates, best first. Only those with a value take part.
    ///   - focus: the span being scored. A field's headline source is the best source that has the field inside it
    ///     (so "Cloud: NOAA HRRR" is not claimed for a day NOAA's near-term series does not reach).
    ///   - smokeOnly: sources whose `aod550` is smoke optical depth; it is kept apart and never enters the series.
    static func build(_ inputs: [CompositeInput], focus: TimeSpan, smokeOnly: Set<SourceID>, now: Date) -> CompositeForecast? {
        struct Item { var d: SourceDescriptor; var sourced: Sourced<HourlySeries>; var stale: Duration?; var rows: [Date: HourlyConditions] }
        var items: [Item] = []
        var opticalDepth: SmokeOpticalDepth?
        for input in inputs {
            let sourced: Sourced<HourlySeries>
            var stale: Duration?
            switch input.state {
            case .fresh(let s): sourced = s
            case .stale(let s, let age): sourced = s; stale = age
            case .none: continue
            }
            var rows: [Date: HourlyConditions] = [:]
            var depth: [TimedValue] = []
            for var h in sourced.value.hours {
                if smokeOnly.contains(input.descriptor.id), let a = h.aod550 {
                    depth.append(TimedValue(time: h.time, value: a))
                    h.aod550 = nil
                }
                rows[h.time] = h
            }
            if !depth.isEmpty, opticalDepth == nil {
                opticalDepth = SmokeOpticalDepth(values: depth.sorted { $0.time < $1.time }, provenance: sourced.provenance)
            }
            items.append(Item(d: input.descriptor, sourced: sourced, stale: stale, rows: rows))
        }
        guard !items.isEmpty else { return nil }

        let times = Set(items.flatMap { $0.rows.keys }).sorted()
        var hours: [HourlyConditions] = []
        var used: [HourlyField: [Int]] = [:]       // field -> item indexes that supplied a value, in order of first use
        var usedInFocus: [HourlyField: [Int]] = [:]
        for t in times {
            var row = HourlyConditions(time: t)
            let inFocus = t < focus.end && t.addingTimeInterval(3600) > focus.start
            for f in HourlyField.allCases {
                for (i, item) in items.enumerated() {
                    guard let v = item.rows[t]?[f] else { continue }
                    row = row.setting(f, v)
                    if !(used[f]?.contains(i) ?? false) { used[f, default: []].append(i) }
                    if inFocus, !(usedInFocus[f]?.contains(i) ?? false) { usedInFocus[f, default: []].append(i) }
                    break
                }
            }
            hours.append(row)
        }

        var fieldSources: [HourlyField: SourceID] = [:]
        var fieldProv: [FieldProvenance] = []
        var contributing = Set<Int>()
        for f in HourlyField.allCases {
            guard let all = used[f], !all.isEmpty else { continue }
            let ordered = (usedInFocus[f] ?? []).sorted() + all.filter { !(usedInFocus[f]?.contains($0) ?? false) }.sorted()
            let head = ordered[0]
            fieldSources[f] = items[head].d.id
            fieldProv.append(FieldProvenance(field: f, provenance: items[head].sourced.provenance,
                                             contributors: ordered.map { items[$0].d.id }))
            contributing.formUnion(all)
        }
        let series = HourlySeries(hours: hours, fieldSources: fieldSources)

        // The overall provenance: the source of total cloud (else any cloud field, else the first), dated by the oldest
        // contributor so an old source cannot hide behind a fresh one.
        let lead = [HourlyField.cloudTotal, .cloudLow, .cloudMid, .cloudHigh]
            .compactMap { f in fieldSources[f].flatMap { id in items.firstIndex { $0.d.id == id } } }.first
            ?? contributing.sorted().first ?? 0
        var prov = items[lead].sourced.provenance
        let contributors = contributing.sorted()
        if let oldest = contributors.map({ items[$0].sourced.provenance.fetchedAt }).min() { prov.fetchedAt = oldest }

        let staleAge = contributors.compactMap { items[$0].stale }.max()
        let sourced = Sourced(value: series, provenance: prov)
        let state: DataState<HourlySeries> = staleAge.map { .stale(sourced, age: $0) } ?? .fresh(sourced)

        // Comparison: the best other source that has total cloud.
        var comparison: (SourceDescriptor, Sourced<HourlySeries>)?
        let cloudLead = fieldSources[.cloudTotal].flatMap { id in items.firstIndex { $0.d.id == id } }
        for (i, item) in items.enumerated() where i != cloudLead {
            if item.rows.values.contains(where: { $0.cloudTotal != nil }) {
                comparison = (item.d, item.sourced)
                break
            }
        }
        return CompositeForecast(series: series, state: state, fieldProvenance: fieldProv, smokeOpticalDepth: opticalDepth,
                                 comparison: comparison, contributing: contributors.map { items[$0].d })
    }

    /// Largest difference in total cloud between this composite and another series, over the hours both have.
    func maxCloudDifference(against other: HourlySeries) -> Double? {
        let mine = Dictionary(series.hours.compactMap { h in h.cloudTotal.map { (h.time, $0) } }, uniquingKeysWith: { a, _ in a })
        let diffs = other.hours.compactMap { h in h.cloudTotal.flatMap { o in mine[h.time].map { abs($0 - o) } } }
        return diffs.max()
    }
}
