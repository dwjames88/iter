import Foundation
import IterModel
import IterSources
import IterSky

// The public vocabulary of IterConditions: what to ask for (`ConditionsRequest`), and what comes back (`SkyReport`).
// Everything here is a Sendable value; reports are Codable so a pack can hold them (BLUEPRINT §6.4, §10.7).

/// How urgently a request is wanted. The service starts and serves lower values first.
public enum ConditionsPriority: Int, Codable, Comparable, Sendable, CaseIterable {
    /// Something the user is looking at.
    case onScreen = 0
    /// The trip being run or built.
    case activeTrip = 1
    /// A pinned trip.
    case pinnedTrip = 2
    /// Everything else, prefetch.
    case background = 3

    public static func < (a: ConditionsPriority, b: ConditionsPriority) -> Bool { a.rawValue < b.rawValue }
}

/// One place on one local day.
public struct ConditionsRequest: Hashable, Sendable {
    public var place: Place
    public var day: LocalDay
    public var priority: ConditionsPriority

    public init(place: Place, day: LocalDay, priority: ConditionsPriority = .onScreen) {
        self.place = place
        self.day = day
        self.priority = priority
    }
}

/// How much of the answer has arrived. A score appears fast and improves.
public enum ForecastTier: Int, Codable, Comparable, Sendable, CaseIterable {
    /// The first usable answer (often one MET Norway request). Good enough for a first score.
    case quick
    /// Every forecast source has answered for the near term; long range or other parts are still coming.
    case nearTerm
    /// Nothing is loading any more.
    case complete

    public static func < (a: ForecastTier, b: ForecastTier) -> Bool { a.rawValue < b.rawValue }
}

/// A part of a report that has not arrived yet.
public enum PendingPart: Codable, Hashable, Sendable {
    /// A forecast source that is still downloading (near term or long range).
    case forecast(SourceID)
    case observations
    case alerts
    case aurora
    case smokeAnalysis
    case horizon
    /// Light pollution and seeing (answered at once while no source exists).
    case lightAndSeeing
}

/// What a named gap is about.
public enum GapSubject: Codable, Hashable, Sendable {
    case field(HourlyField)
    case forecast
    case observations
    case alerts
    case aurora
    case smokeAnalysis
    case horizon
    case lightPollution
    case seeing
}

/// A named gap: something the Sky Index could use that nobody supplied, with the reasons. Never a number.
public struct ConditionsGap: Codable, Hashable, Sendable {
    public var subject: GapSubject
    public var reasons: [NoDataReason]

    public init(subject: GapSubject, reasons: [NoDataReason]) {
        self.subject = subject
        self.reasons = reasons
    }
}

/// Which source supplied a hourly field, with that source's provenance.
public struct FieldProvenance: Codable, Hashable, Sendable {
    public var field: HourlyField
    public var provenance: Provenance
    /// Every source that supplied some hour of the field, best first. More than one means later hours came from a lesser source.
    public var contributors: [SourceID]

    public init(field: HourlyField, provenance: Provenance, contributors: [SourceID]) {
        self.field = field
        self.provenance = provenance
        self.contributors = contributors
    }
}

/// Another source's series, kept to show how far two models disagree (and fed to the Sky Index as `spreadSeries`).
public struct ForecastComparison: Codable, Hashable, Sendable {
    public var source: SourceID
    public var sourceName: String
    public var series: HourlySeries
    public var provenance: Provenance
    /// Largest difference in total cloud (0...1) between the composite and this source over the hours both have.
    public var maxCloudDifference: Double?

    public init(source: SourceID, sourceName: String, series: HourlySeries, provenance: Provenance, maxCloudDifference: Double?) {
        self.source = source
        self.sourceName = sourceName
        self.series = series
        self.provenance = provenance
        self.maxCloudDifference = maxCloudDifference
    }
}

public struct TimedValue: Codable, Hashable, Sendable {
    public var time: Date
    public var value: Double

    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// HRRR's `aod550` is the optical depth of **smoke** only (AOTK), not of all aerosol. It is shown as "smoke optical depth"
/// and never given to the scorer as aerosol.
public struct SmokeOpticalDepth: Codable, Hashable, Sendable {
    public var values: [TimedValue]
    public var provenance: Provenance

    public init(values: [TimedValue], provenance: Provenance) {
        self.values = values
        self.provenance = provenance
    }
}

/// Smoke at a place: the near-surface model value, the analysed polygons, the smoke optical depth.
public struct SmokeReport: Codable, Hashable, Sendable {
    /// HMS analysis for the day: density class from the analysed polygons.
    public var analysis: DataState<SmokeAnalysis>
    /// Largest near-surface smoke (micrograms per cubic metre) over the day's windows, and who supplied it.
    public var nearSurfaceMaxUgm3: Double?
    public var nearSurfaceSource: SourceID?
    public var opticalDepth: SmokeOpticalDepth?

    public init(analysis: DataState<SmokeAnalysis> = .none([]), nearSurfaceMaxUgm3: Double? = nil, nearSurfaceSource: SourceID? = nil,
                opticalDepth: SmokeOpticalDepth? = nil) {
        self.analysis = analysis
        self.nearSurfaceMaxUgm3 = nearSurfaceMaxUgm3
        self.nearSurfaceSource = nearSurfaceSource
        self.opticalDepth = opticalDepth
    }
}

/// A short, honest line the UI shows: "Cloud layers: NOAA HRRR, run 12Z, 2.1 km grid point".
public struct ProvenanceLine: Codable, Hashable, Sendable {
    public var label: String
    public var text: String
    /// Set when the data is old; the line is not shown as fresh.
    public var staleAge: TimeInterval?

    public init(label: String, text: String, staleAge: TimeInterval? = nil) {
        self.label = label
        self.text = text
        self.staleAge = staleAge
    }

    /// "Cloud layers: NOAA HRRR, run 12Z".
    public var line: String { label.isEmpty ? text : "\(label): \(text)" }
}

/// Set when a report was served from an offline pack.
public struct PackServing: Codable, Hashable, Sendable {
    public var tripID: UUID
    public var builtAt: Date

    public init(tripID: UUID, builtAt: Date) {
        self.tripID = tripID
        self.builtAt = builtAt
    }
}

/// Sky and weather for one place on one local day: the composite forecast with per-field provenance, every window scored,
/// and everything beside the forecast the UI shows.
public struct SkyReport: Codable, Hashable, Sendable, Identifiable {
    public var placeID: UUID
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var day: LocalDay
    public var generatedAt: Date

    /// How complete the report is, and what is still on its way.
    public var tier: ForecastTier
    public var loading: [PendingPart]

    /// The composite series; `fieldSources` says which source supplied each field.
    public var forecast: DataState<HourlySeries>
    public var fieldProvenance: [FieldProvenance]
    /// The best other source's series, for "sources disagree" and the comparison line.
    public var comparison: ForecastComparison?
    /// TTL the scorer uses to decide the composite is stale.
    public var forecastTTL: TimeInterval

    /// The day's windows, each scored by `LightEngine`.
    public var daylight: DayLight

    public var observations: DataState<[Sourced<WeatherObservation>]>
    public var stationReports: DataState<[Sourced<StationReport>]>
    public var alerts: DataState<[WeatherAlert]>
    public var smoke: SmokeReport
    public var aurora: DataState<AuroraOutlook>
    public var horizon: DataState<HorizonProfile>
    /// Bortle class and seeing, only when a source supplies them (none does today).
    public var bortle: Double?
    public var seeing: Double?

    public var gaps: [ConditionsGap]
    public var provenanceLines: [ProvenanceLine]
    /// Licence keys of every source used; `attributions` turns them into the texts to show.
    public var attributionKeys: [String]
    /// Set when some of the report came from an offline pack.
    public var pack: PackServing?
    /// "Forecast from 06:29, offline" when the forecast is not fresh because there is no network.
    public var offlineNote: String?

    public var id: String { "\(placeID.uuidString)|\(day.iso)" }

    public init(placeID: UUID, coordinate: Coordinate, timeZoneIdentifier: String, day: LocalDay, generatedAt: Date,
                tier: ForecastTier, loading: [PendingPart], forecast: DataState<HourlySeries>, fieldProvenance: [FieldProvenance],
                comparison: ForecastComparison?, forecastTTL: TimeInterval, daylight: DayLight,
                observations: DataState<[Sourced<WeatherObservation>]>, stationReports: DataState<[Sourced<StationReport>]>,
                alerts: DataState<[WeatherAlert]>, smoke: SmokeReport, aurora: DataState<AuroraOutlook>,
                horizon: DataState<HorizonProfile>, bortle: Double?, seeing: Double?, gaps: [ConditionsGap],
                provenanceLines: [ProvenanceLine], attributionKeys: [String], pack: PackServing?, offlineNote: String?) {
        self.placeID = placeID
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.day = day
        self.generatedAt = generatedAt
        self.tier = tier
        self.loading = loading
        self.forecast = forecast
        self.fieldProvenance = fieldProvenance
        self.comparison = comparison
        self.forecastTTL = forecastTTL
        self.daylight = daylight
        self.observations = observations
        self.stationReports = stationReports
        self.alerts = alerts
        self.smoke = smoke
        self.aurora = aurora
        self.horizon = horizon
        self.bortle = bortle
        self.seeing = seeing
        self.gaps = gaps
        self.provenanceLines = provenanceLines
        self.attributionKeys = attributionKeys
        self.pack = pack
        self.offlineNote = offlineNote
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }

    /// What the Forecast Sky Index reads: the composite, the horizon, the aurora outlook and the comparison series.
    /// `bortle` and `seeing` are nil unless a source supplied them. The smoke optical depth is deliberately not in it.
    public var forecastInputs: ForecastSkyInputs {
        ForecastSkyInputs(hourly: forecast.value, provenance: forecast.provenance, ttl: forecastTTL, horizon: horizon.value,
                          aurora: aurora.value, bortle: bortle, seeing: seeing,
                          spreadSeries: comparison.map { [$0.series] } ?? [])
    }

    /// The attribution texts for every source used.
    public var attributions: [AttributionText] { attributionKeys.compactMap { Attribution.text(for: $0) } }

    /// The provenance of one field, if a source supplied it.
    public func provenance(of field: HourlyField) -> Provenance? { fieldProvenance.first { $0.field == field }?.provenance }

    /// The gap record for a subject, if any.
    public func gap(_ subject: GapSubject) -> ConditionsGap? { gaps.first { $0.subject == subject } }

    /// The headline window for an intent on this day.
    public func headline(for intent: LightIntent) -> LightWindow? { daylight.headline(for: intent) }
}
