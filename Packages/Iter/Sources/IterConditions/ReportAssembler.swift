import Foundation
import IterModel
import IterSources
import IterSky
import IterAstro

/// Everything a job has collected so far. `nil` means "has not arrived"; `.none` means "arrived empty, with reasons".
struct JobParts: Sendable {
    /// Forecast candidates in preference order (forecast kind first, then smoke and aerosol).
    var candidates: [SourceDescriptor] = []
    var forecasts: [SourceID: DataState<HourlySeries>] = [:]
    /// Why a source gave nothing (or only an old cached value).
    var failures: [SourceID: [NoDataReason]] = [:]
    /// Sources whose near-term (first) step has resolved, and those whose last step has.
    var nearDone: Set<SourceID> = []
    var fullDone: Set<SourceID> = []
    /// The day is over: no forecast is fetched or scored.
    var pastDay = false

    var observations: DataState<[Sourced<WeatherObservation>]>?
    var stationReports: DataState<[Sourced<StationReport>]>?
    var alerts: DataState<[WeatherAlert]>?
    var aurora: DataState<AuroraOutlook>?
    var smokeAnalysis: DataState<SmokeAnalysis>?
    var horizon: DataState<HorizonProfile>?
    var bortle: Double?
    var seeing: Double?
    var bortleReasons: [NoDataReason]?
    var seeingReasons: [NoDataReason]?

    var pending: [PendingPart] = []
}

/// Turns a job's parts (and a pack entry, when offline) into a `SkyReport`. Pure: the caller supplies `now`.
struct ReportAssembler: Sendable {
    let registry: SourceRegistry
    let ephemeris: any Ephemeris
    let configuration: ConditionsConfiguration

    static let expectedFields: [HourlyField] = [.cloudTotal, .cloudLow, .cloudMid, .cloudHigh, .precipChance, .visibilityKm,
                                                .rhPercent, .windMs, .smokeUgm3]

    func assemble(place: Place, day: LocalDay, parts: JobParts, pack: PackEntry?, now: Date) -> SkyReport {
        let engine = LightEngine(ephemeris: ephemeris)
        let windows = engine.windows(for: place, on: day)
        let zone = place.timeZone
        let focus = TimeSpan(start: windows.map(\.span.start).min() ?? day.start(in: zone),
                             end: windows.map(\.span.end).max() ?? day.adding(days: 1).start(in: zone))

        // 1. The composite forecast.
        let inputs = parts.candidates.map { CompositeInput(descriptor: $0, state: parts.forecasts[$0.id] ?? .none([])) }
        let composite = CompositeForecast.build(inputs, focus: focus, smokeOnly: configuration.smokeOnlyOpticalDepth, now: now)
        var forecast: DataState<HourlySeries>
        var fieldProvenance: [FieldProvenance] = composite?.fieldProvenance ?? []
        var comparison: ForecastComparison?
        var opticalDepth = composite?.smokeOpticalDepth
        var ttl = Freshness.defaultTTL
        var usedPack = false

        var forecastReasons: [NoDataReason] = []
        if let composite {
            forecast = composite.state
            if let c = composite.comparison {
                comparison = ForecastComparison(source: c.descriptor.id, sourceName: c.descriptor.name, series: c.sourced.value,
                                                provenance: c.sourced.provenance,
                                                maxCloudDifference: composite.maxCloudDifference(against: c.sourced.value))
            }
            ttl = max(1800, composite.contributing.map { $0.cacheTTL.timeInterval }.min() ?? Freshness.defaultTTL)
        } else {
            if parts.pastDay {
                forecastReasons = []
            } else if parts.candidates.isEmpty {
                forecastReasons = registry.gaps(kind: .forecast, at: place.coordinate)
            } else {
                for d in parts.candidates { forecastReasons.append(contentsOf: parts.forecasts[d.id]?.reasons ?? []) }
                forecastReasons.append(contentsOf: parts.failures.values.flatMap { $0 })
                forecastReasons = Self.unique(forecastReasons)
            }
            forecast = .none(forecastReasons)
            let offline = forecastReasons.contains { if case .offline = $0 { true } else { false } }
            if offline, let pack, let packed = pack.report.forecast.value, let prov = pack.report.forecast.provenance {
                let age = Duration.interval(max(0, now.timeIntervalSince(prov.fetchedAt)))
                forecast = .stale(Sourced(value: packed, provenance: prov), age: age)
                fieldProvenance = pack.report.fieldProvenance
                comparison = pack.report.comparison
                opticalDepth = pack.report.smoke.opticalDepth
                ttl = pack.report.forecastTTL
                usedPack = true
            }
        }

        // 2. The other parts, with the pack standing in for anything offline.
        func part<T: Sendable>(_ own: DataState<T>?, _ packed: DataState<T>) -> DataState<T> {
            guard let own else { return .none([]) }
            if case .none(let reasons) = own, reasons.contains(where: { if case .offline = $0 { true } else { false } }),
               let v = packed.sourced {
                usedPack = true
                return .stale(v, age: .interval(max(0, now.timeIntervalSince(v.provenance.fetchedAt))))
            }
            return own
        }
        let observations = part(parts.observations, pack?.report.observations ?? .none([]))
        let stationReports = part(parts.stationReports, pack?.report.stationReports ?? .none([]))
        let alerts = part(parts.alerts, pack?.report.alerts ?? .none([]))
        let aurora = part(parts.aurora, pack?.report.aurora ?? .none([]))
        let smokeAnalysis = part(parts.smokeAnalysis, pack?.report.smoke.analysis ?? .none([]))
        var horizon = part(parts.horizon, pack?.report.horizon ?? .none([]))
        if horizon.value == nil, let own = place.horizon {
            horizon = .fresh(Sourced(value: own, provenance: Provenance(source: .terrariumTiles, fetchedAt: place.updatedAt,
                                                                          licence: LicenceTag(key: LicenceKey.terrainTiles, mayStore: true))))
        }

        // 3. Score every window of the day.
        var skyInputs: ForecastSkyInputs?
        if let hourly = forecast.value, let prov = forecast.provenance {
            skyInputs = ForecastSkyInputs(hourly: hourly, provenance: prov, ttl: ttl, horizon: horizon.value, aurora: aurora.value,
                                          bortle: parts.bortle, seeing: parts.seeing,
                                          spreadSeries: comparison.map { [$0.series] } ?? [])
        }
        let daylight = engine.dayLight(for: place, on: day, inputs: skyInputs, unavailable: forecast.reasons, now: now)

        // 4. Smoke.
        var nearSurface: Double?
        if let series = forecast.value {
            nearSurface = series.hours.filter { $0.time < focus.end && $0.time.addingTimeInterval(3600) > focus.start }.compactMap(\.smokeUgm3).max()
        }
        let smoke = SmokeReport(analysis: smokeAnalysis, nearSurfaceMaxUgm3: nearSurface,
                                nearSurfaceSource: forecast.value?.fieldSources[.smokeUgm3], opticalDepth: opticalDepth)

        // 5. Tier.
        let tier: ForecastTier
        if parts.pending.isEmpty {
            tier = .complete
        } else if parts.candidates.allSatisfy({ parts.nearDone.contains($0.id) }) {
            tier = .nearTerm
        } else {
            tier = .quick
        }

        var report = SkyReport(
            placeID: place.id, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier, day: day, generatedAt: now,
            tier: tier, loading: parts.pending, forecast: forecast, fieldProvenance: fieldProvenance, comparison: comparison,
            forecastTTL: ttl, daylight: daylight, observations: observations, stationReports: stationReports, alerts: alerts,
            smoke: smoke, aurora: aurora, horizon: horizon, bortle: parts.bortle, seeing: parts.seeing, gaps: [],
            provenanceLines: [], attributionKeys: [], pack: usedPack ? pack.map { PackServing(tripID: $0.tripID, builtAt: $0.builtAt) } : nil,
            offlineNote: nil)
        report.gaps = gaps(for: report, parts: parts, forecastReasons: forecastReasons, place: place)
        report.provenanceLines = lines(for: report, now: now)
        report.attributionKeys = attributionKeys(for: report)
        report.offlineNote = offlineNote(for: report, parts: parts, zone: zone)
        return report
    }

    /// Re-scores a stored report with a later `now` (a pack served long after it was built). Parts are kept as they were.
    func rescored(_ stored: SkyReport, place: Place, now: Date, pack: PackServing?) -> SkyReport {
        var r = stored
        func age(_ p: Provenance?) -> Duration { .interval(max(0, now.timeIntervalSince(p?.fetchedAt ?? now))) }
        func stale<T: Sendable>(_ s: DataState<T>) -> DataState<T> { s.asStale(age: age(s.provenance)) }
        r.forecast = stale(r.forecast)
        r.observations = stale(r.observations)
        r.stationReports = stale(r.stationReports)
        r.alerts = stale(r.alerts)
        r.aurora = stale(r.aurora)
        r.horizon = stale(r.horizon)
        r.smoke.analysis = stale(r.smoke.analysis)
        r.generatedAt = now
        r.pack = pack
        r.tier = .complete
        r.loading = []
        let inputs: ForecastSkyInputs? = r.forecast.value == nil ? nil : r.forecastInputs
        r.daylight = LightEngine(ephemeris: ephemeris).dayLight(for: place, on: r.day, inputs: inputs, unavailable: r.forecast.reasons, now: now)
        r.provenanceLines = lines(for: r, now: now)
        r.offlineNote = r.forecast.provenance.map { "Forecast from \(Self.clock($0.fetchedAt, r.timeZone)), offline" }
        return r
    }

    // MARK: Gaps

    private func gaps(for r: SkyReport, parts: JobParts, forecastReasons: [NoDataReason], place: Place) -> [ConditionsGap] {
        var out: [ConditionsGap] = []
        let forecastPending = parts.pending.contains { if case .forecast = $0 { true } else { false } }
        if r.forecast.value == nil {
            if !forecastPending, !parts.pastDay, !forecastReasons.isEmpty { out.append(ConditionsGap(subject: .forecast, reasons: forecastReasons)) }
        } else if !forecastPending, let series = r.forecast.value {
            let failureReasons = Self.unique(parts.failures.values.flatMap { $0 })
            for f in Self.expectedFields where series.fieldSources[f] == nil {
                if f == .precipChance, series.fieldSources[.precipMm] != nil { continue }
                let kind: DataKind = f == .smokeUgm3 ? .smoke : .forecast
                var reasons = registry.gaps(kind: kind, at: place.coordinate)
                if reasons.contains(.notProvidedBySource) == false { reasons.append(contentsOf: failureReasons) }
                reasons = Self.unique(reasons)
                out.append(ConditionsGap(subject: .field(f), reasons: reasons.isEmpty ? [.notProvidedBySource] : reasons))
            }
        }
        if r.bortle == nil, let reasons = parts.bortleReasons { out.append(ConditionsGap(subject: .lightPollution, reasons: reasons)) }
        if r.seeing == nil, let reasons = parts.seeingReasons { out.append(ConditionsGap(subject: .seeing, reasons: reasons)) }
        func add<T: Sendable>(_ s: DataState<T>, _ subject: GapSubject) {
            if case .none(let reasons) = s, !reasons.isEmpty { out.append(ConditionsGap(subject: subject, reasons: reasons)) }
        }
        add(r.observations, .observations)
        add(r.alerts, .alerts)
        add(r.aurora, .aurora)
        add(r.smoke.analysis, .smokeAnalysis)
        add(r.horizon, .horizon)
        return out
    }

    // MARK: Provenance lines

    func sourceName(_ id: SourceID) -> String {
        registry.sources.first { $0.descriptor.id == id }?.descriptor.name ?? SourceCatalogue.descriptor(id)?.name ?? id.rawValue
    }

    private func describe(_ p: Provenance, grid: Bool) -> String {
        var text = sourceName(p.source)
        if let m = p.model, !m.isEmpty, !text.localizedCaseInsensitiveContains(m) { text += " (\(m))" }
        if let issued = p.issuedAt { text += ", run \(Self.runHour(issued))Z" }
        if grid, let d = p.distanceKm { text += String(format: ", %.1f km grid point", d) }
        text += Self.militaryNote(p.origin)
        return text
    }

    private func lines(for r: SkyReport, now: Date) -> [ProvenanceLine] {
        var out: [ProvenanceLine] = []
        func age(_ p: Provenance) -> TimeInterval? {
            guard r.forecast.isStale else { return nil }
            return max(0, now.timeIntervalSince(p.fetchedAt))
        }
        let groups: [(String, [HourlyField])] = [
            ("Cloud layers", [.cloudLow, .cloudMid, .cloudHigh]), ("Cloud cover", [.cloudTotal]),
            ("Precipitation", [.precipChance, .precipMm]), ("Visibility", [.visibilityKm]),
            ("Humidity", [.rhPercent, .dewpointC]), ("Wind", [.windMs, .gustMs]), ("Smoke", [.smokeUgm3]),
        ]
        for (label, fields) in groups {
            let provs = fields.compactMap { f in r.fieldProvenance.first { $0.field == f } }
            guard let first = provs.first else { continue }
            if label == "Cloud cover", let layers = r.fieldProvenance.first(where: { [.cloudLow, .cloudMid, .cloudHigh].contains($0.field) }),
               layers.provenance.source == first.provenance.source {
                continue
            }
            var text = describe(first.provenance, grid: true)
            let others = Self.unique(provs.map(\.provenance.source)).filter { $0 != first.provenance.source }
            if !others.isEmpty { text += " and " + others.map(sourceName).joined(separator: " and ") }
            let later = Self.unique(provs.flatMap(\.contributors)).filter { $0 != first.provenance.source && !others.contains($0) }
            if !later.isEmpty { text += ", then " + later.map(sourceName).joined(separator: " and ") + " for later hours" }
            out.append(ProvenanceLine(label: label, text: text, staleAge: age(first.provenance)))
        }
        if let od = r.smoke.opticalDepth {
            out.append(ProvenanceLine(label: "Smoke optical depth", text: describe(od.provenance, grid: true)))
        }
        if let c = r.comparison { out.append(ProvenanceLine(label: "Compared with", text: c.sourceName)) }
        if let o = r.observations.value?.first {
            var text = sourceName(o.provenance.source)
            if let n = o.value.stationName { text += ", \(n)" }
            if let d = o.provenance.distanceKm { text += String(format: ", %.0f km", d) }
            let minutes = Int(max(0, now.timeIntervalSince(o.value.time)) / 60)
            text += ", \(minutes) min old" + Self.militaryNote(o.provenance.origin)
            out.append(ProvenanceLine(label: "Observed", text: text, staleAge: r.observations.isStale ? TimeInterval(minutes * 60) : nil))
        }
        if let p = r.alerts.provenance { out.append(ProvenanceLine(label: "Alerts", text: sourceName(p.source), staleAge: r.alerts.isStale ? max(0, now.timeIntervalSince(p.fetchedAt)) : nil)) }
        if let p = r.aurora.provenance { out.append(ProvenanceLine(label: "Aurora", text: sourceName(p.source), staleAge: r.aurora.isStale ? max(0, now.timeIntervalSince(p.fetchedAt)) : nil)) }
        if let p = r.smoke.analysis.provenance { out.append(ProvenanceLine(label: "Smoke analysis", text: sourceName(p.source))) }
        if let p = r.horizon.provenance { out.append(ProvenanceLine(label: "Horizon", text: sourceName(p.source))) }
        return out
    }

    private func attributionKeys(for r: SkyReport) -> [String] {
        var provs: [Provenance] = r.fieldProvenance.map(\.provenance)
        provs.append(contentsOf: [r.comparison?.provenance, r.smoke.opticalDepth?.provenance, r.alerts.provenance, r.aurora.provenance,
                                  r.smoke.analysis.provenance, r.horizon.provenance, r.forecast.provenance].compactMap { $0 })
        provs.append(contentsOf: (r.observations.value ?? []).map(\.provenance))
        provs.append(contentsOf: (r.stationReports.value ?? []).map(\.provenance))
        return Self.unique(provs.map(\.licence.key)).filter { $0 != LicenceKey.none }
    }

    private func offlineNote(for r: SkyReport, parts: JobParts, zone: TimeZone) -> String? {
        guard r.forecast.isStale, let prov = r.forecast.provenance else { return nil }
        let offline = r.pack != nil || parts.failures.values.joined().contains { if case .offline = $0 { true } else { false } }
        return offline ? "Forecast from \(Self.clock(prov.fetchedAt, zone)), offline" : nil
    }

    // MARK: Helpers

    /// ", military-origin (US Army) via NOAA Aviation Weather Center" for data a military organisation produced; nothing otherwise.
    static func militaryNote(_ origin: SourceOrigin?) -> String {
        guard let origin, origin.tier == .military else { return "" }
        return ", " + origin.label.prefix(1).lowercased() + origin.label.dropFirst()
    }

    static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }

    static func runHour(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return String(format: "%02d", cal.component(.hour, from: date))
    }

    static func clock(_ date: Date, _ zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

extension DataState {
    /// The sourced value, fresh or stale.
    var sourced: Sourced<Value>? {
        switch self {
        case .fresh(let s), .stale(let s, _): s
        case .none: nil
        }
    }
}
