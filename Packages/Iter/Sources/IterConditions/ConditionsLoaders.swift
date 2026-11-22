import Foundation
import IterModel
import IterSources
import IterSky

// The smaller parts of a report: observations, alerts, aurora, smoke analysis, the horizon, and the inputs no source has
// yet. Each answers a `DataState`: fresh from the cache or the network, stale with its age when the network failed, or none
// with the named reasons.

extension ConditionsService {
    /// A cached source answer. Fresh while within `ttl` (default the source's `cacheTTL`); otherwise fetched, and when the
    /// fetch fails the old value is returned as `.stale` with its age, else `.none` with the reason.
    func cachedState<T: Codable & Sendable>(_ key: CacheKey, descriptor d: SourceDescriptor, ttl: Duration? = nil,
                                            fetch: () async throws -> Sourced<T>) async -> DataState<T> {
        let old = await cache.entry(key, as: Sourced<T>.self)
        let limit = (ttl ?? d.cacheTTL).timeInterval
        if let old, clock.now.timeIntervalSince(old.storedAt) < limit { return .fresh(old.value) }
        do {
            let value = try await fetch()
            await cache.store(value, for: key, licence: d.licence)
            return .fresh(value)
        } catch {
            let e = SourceError.wrap(error)
            if let old { return .stale(old.value, age: .interval(max(0, clock.now.timeIntervalSince(old.storedAt)))) }
            return .none(e == .cancelled ? [] : [e.noDataReason(source: d.id, lastGood: nil)])
        }
    }

    /// The first provider that answers, in preference order; when none does, every reason.
    func firstState<P: Sendable, T: Sendable>(_ providers: [P], kind: DataKind, at c: Coordinate,
                                    state: (P) async -> DataState<T>) async -> DataState<T> {
        if providers.isEmpty { return .none(registry.gaps(kind: kind, at: c)) }
        var reasons: [NoDataReason] = []
        for p in providers {
            let s = await state(p)
            if s.value != nil { return s }
            reasons.append(contentsOf: s.reasons)
        }
        return .none(ReportAssembler.unique(reasons))
    }

    // MARK: Observations

    func loadObservations(_ place: Place) async -> JobPart {
        async let obs = nearbyObservations(place.coordinate)
        async let reports = nearbyStationReports(place.coordinate)
        return await .observations(obs, reports)
    }

    func nearbyObservations(_ c: Coordinate) async -> DataState<[Sourced<WeatherObservation>]> {
        let providers = registry.providers((any ObservationProvider).self, kind: .observation, at: c)
        if providers.isEmpty { return .none(registry.gaps(kind: .observation, at: c)) }
        let radius = configuration.observationRadiusKm, maxAge = configuration.observationMaxAge
        let states = await withTaskGroup(of: DataState<[Sourced<WeatherObservation>]>.self) { group in
            for p in providers {
                group.addTask {
                    let d = p.descriptor
                    return await self.cachedState(CacheKey(source: d.id, kind: .observation, cell: c.cacheKey, bucket: "obs"), descriptor: d) {
                        let list = try await p.latest(near: c, within: radius, maxAge: maxAge)
                        let prov = list.first?.provenance ?? d.provenance(fetchedAt: self.clock.now)
                        return Sourced(value: list, provenance: prov)
                    }
                }
            }
            var out: [DataState<[Sourced<WeatherObservation>]>] = []
            for await s in group { out.append(s) }
            return out
        }
        return Self.merge(states) { $0.provenance.distanceKm ?? .infinity }
    }

    func nearbyStationReports(_ c: Coordinate) async -> DataState<[Sourced<StationReport>]> {
        let providers = registry.providers((any StationReportProvider).self, kind: .observation, at: c)
        if providers.isEmpty { return .none(registry.gaps(kind: .observation, at: c)) }
        let radius = configuration.observationRadiusKm
        let states = await withTaskGroup(of: DataState<[Sourced<StationReport>]>.self) { group in
            for p in providers {
                group.addTask {
                    let d = p.descriptor
                    return await self.cachedState(CacheKey(source: d.id, kind: .observation, cell: c.cacheKey, bucket: "reports"), descriptor: d) {
                        let list = try await p.reports(near: c, within: radius, limit: 4)
                        let prov = list.first?.provenance ?? d.provenance(fetchedAt: self.clock.now)
                        return Sourced(value: list, provenance: prov)
                    }
                }
            }
            var out: [DataState<[Sourced<StationReport>]>] = []
            for await s in group { out.append(s) }
            return out
        }
        return Self.merge(states) { $0.value.distanceKm }
    }

    /// Several providers' lists as one, nearest first. Stale only when every list is.
    static func merge<X: Sendable>(_ states: [DataState<[X]>], sortKey: (X) -> Double) -> DataState<[X]> {
        let have = states.compactMap { $0.sourced }
        guard let lead = have.first else { return .none(ReportAssembler.unique(states.flatMap(\.reasons))) }
        let merged = Sourced(value: have.flatMap(\.value).sorted { sortKey($0) < sortKey($1) }, provenance: lead.provenance)
        let ages = states.compactMap { s -> Duration? in if case .stale(_, let a) = s { a } else { nil } }
        if let youngest = ages.min(), ages.count == have.count { return .stale(merged, age: youngest) }
        return .fresh(merged)
    }

    // MARK: Alerts, aurora, smoke

    func loadAlerts(_ place: Place) async -> JobPart {
        let c = place.coordinate
        let providers = registry.providers((any AlertProvider).self, kind: .alerts, at: c)
        return await .alerts(firstState(providers, kind: .alerts, at: c) { p in
            let d = p.descriptor
            return await self.cachedState(CacheKey(source: d.id, kind: .alerts, cell: c.cacheKey, bucket: ""), descriptor: d) {
                try await p.alerts(at: c)
            }
        })
    }

    func loadAurora(_ place: Place) async -> JobPart {
        let c = place.coordinate
        let providers = registry.providers((any AuroraProvider).self, kind: .aurora, at: c)
        return await .aurora(firstState(providers, kind: .aurora, at: c) { p in
            let d = p.descriptor
            return await self.cachedState(CacheKey(source: d.id, kind: .aurora, cell: GeoCell.key(c, degrees: 0.5), bucket: ""), descriptor: d) {
                let reading = try await p.aurora(at: c)
                // The Kp forecast is optional: a failure there leaves the probability on its own.
                let kp = (try? await p.kpForecast())?.value ?? []
                let outlook = AuroraOutlook(kp: kp.map { AuroraOutlook.KpStep(time: $0.start, value: $0.kp) },
                                            probabilityPercent: reading.value.probabilityPercent, provenance: reading.provenance)
                return Sourced(value: outlook, provenance: reading.provenance)
            }
        })
    }

    func loadSmokeAnalysis(_ place: Place, day: LocalDay) async -> JobPart {
        let c = place.coordinate
        let date = day.noon(in: place.timeZone)
        let providers = registry.providers((any SmokeAnalysisProvider).self, kind: .smoke, at: c)
        return await .smokeAnalysis(firstState(providers, kind: .smoke, at: c) { p in
            let d = p.descriptor
            return await self.cachedState(CacheKey(source: d.id, kind: .smoke, cell: GeoCell.key(c, degrees: 0.1), bucket: day.iso), descriptor: d) {
                try await p.smoke(at: c, on: date)
            }
        })
    }

    // MARK: Horizon

    func fetchHorizon(_ c: Coordinate) async -> DataState<HorizonProfile> {
        let providers = registry.providers((any TerrainProvider).self, kind: .horizon, at: c)
        return await firstState(providers, kind: .horizon, at: c) { p in
            let d = p.descriptor
            return await self.cachedState(CacheKey(source: d.id, kind: .horizon, cell: c.cacheKey, bucket: ""), descriptor: d,
                                          ttl: self.configuration.horizonTTL) {
                try await p.horizon(at: c, azimuthStep: HorizonProfile.standardStepDegrees)
            }
        }
    }

    // MARK: Inputs nobody supplies yet

    /// Light pollution and seeing. Today their only providers throw `.noSource`, so both come back absent with
    /// `.notProvidedBySource`; a real provider would flow through without a change here.
    func loadOptionalInputs(_ place: Place) async -> JobPart {
        let c = place.coordinate
        var bortle: Double?
        var bortleReasons: [NoDataReason] = []
        let sky = registry.providers((any SkyBrightnessProvider).self, kind: .lightPollution, at: c)
        if sky.isEmpty { bortleReasons = Self.gapOrNotProvided(registry.gaps(kind: .lightPollution, at: c)) }
        for p in sky {
            do {
                bortle = try await p.skyBrightness(at: c).value.bortle
                if bortle != nil { bortleReasons = []; break }
                bortleReasons = [.notProvidedBySource]
            } catch {
                bortleReasons = [SourceError.wrap(error).noDataReason(source: p.descriptor.id)]
            }
        }
        var seeing: Double?
        var seeingReasons: [NoDataReason] = []
        let seeingProviders = registry.providers((any SeeingProvider).self, kind: .seeing, at: c)
        if seeingProviders.isEmpty { seeingReasons = Self.gapOrNotProvided(registry.gaps(kind: .seeing, at: c)) }
        let start = floorHour(clock.now)
        for p in seeingProviders {
            do {
                let estimates = try await p.seeing(at: c, span: TimeSpan(start: start, end: start.addingTimeInterval(24 * 3600))).value
                let values = estimates.compactMap(\.seeingArcsec)
                if !values.isEmpty { seeing = values.reduce(0, +) / Double(values.count); seeingReasons = []; break }
                seeingReasons = [.notProvidedBySource]
            } catch {
                seeingReasons = [SourceError.wrap(error).noDataReason(source: p.descriptor.id)]
            }
        }
        return .optionalInputs(bortle: bortle, bortleReasons: bortleReasons, seeing: seeing, seeingReasons: seeingReasons)
    }

    private static func gapOrNotProvided(_ gaps: [NoDataReason]) -> [NoDataReason] { gaps.isEmpty ? [.notProvidedBySource] : gaps }
}
