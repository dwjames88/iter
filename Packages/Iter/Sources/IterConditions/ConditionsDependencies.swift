import Foundation
import IterModel
import IterSources
import IterAstro

/// Knobs of the service. The defaults are what the app uses; tests change the clock-based ones.
public struct ConditionsConfiguration: Sendable {
    /// How long concurrent forecast requests are collected before one batch call goes out.
    public var coalescingWindow: Duration
    /// Forecast horizons, in hours, a source can be asked for. A request is rounded up to one of them.
    public var tierHours: [Int]
    /// Sources fetched near term first and long range later (NOAA bills one request per forecast hour). A
    /// `BatchForecastProvider` is always treated this way.
    public var incrementalSources: Set<SourceID>
    /// Sources whose `aod550` is smoke optical depth only (HRRR AOTK). Never given to the scorer as aerosol.
    public var smokeOnlyOpticalDepth: Set<SourceID>
    /// Terrain horizons rarely change.
    public var horizonTTL: Duration
    /// Forecast cache cell, degrees (about 1 km).
    public var forecastCellDegrees: Double
    /// Station search radius for observations.
    public var observationRadiusKm: Double
    /// Observations older than this are not asked for.
    public var observationMaxAge: Duration
    /// Observations, alerts, smoke analysis and aurora are only asked for days this many days from today.
    public var liveDays: Int
    /// Fetch the terrain horizon (tile downloads) when the place has none.
    public var fetchesHorizon: Bool

    public init(coalescingWindow: Duration = .milliseconds(30), tierHours: [Int] = [12, 48, 240],
                incrementalSources: Set<SourceID> = [.noaaNOMADS, .noaaHRRRSmoke],
                smokeOnlyOpticalDepth: Set<SourceID> = [.noaaHRRRSmoke],
                horizonTTL: Duration = .seconds(30 * 86_400), forecastCellDegrees: Double = 0.01, observationRadiusKm: Double = 50,
                observationMaxAge: Duration = .seconds(3 * 3600), liveDays: Int = 2, fetchesHorizon: Bool = true) {
        self.coalescingWindow = coalescingWindow
        self.tierHours = tierHours.sorted()
        self.incrementalSources = incrementalSources
        self.smokeOnlyOpticalDepth = smokeOnlyOpticalDepth
        self.horizonTTL = horizonTTL
        self.forecastCellDegrees = forecastCellDegrees
        self.observationRadiusKm = observationRadiusKm
        self.observationMaxAge = observationMaxAge
        self.liveDays = liveDays
        self.fetchesHorizon = fetchesHorizon
    }
}

/// Everything `ConditionsService` needs, injected.
public struct ConditionsDependencies: Sendable {
    public var registry: SourceRegistry
    public var cache: SourceCache
    public var clock: any SourceClock
    public var ephemeris: any Ephemeris
    /// Where trip packs live (`<packDirectory>/<tripID>.json`); nil disables packs.
    public var packDirectory: URL?
    public var configuration: ConditionsConfiguration

    public init(registry: SourceRegistry, cache: SourceCache, clock: any SourceClock, ephemeris: any Ephemeris,
                packDirectory: URL? = nil, configuration: ConditionsConfiguration = ConditionsConfiguration()) {
        self.registry = registry
        self.cache = cache
        self.clock = clock
        self.ephemeris = ephemeris
        self.packDirectory = packDirectory
        self.configuration = configuration
    }
}

extension HourlyConditions {
    /// A copy with one field set.
    func setting(_ field: HourlyField, _ value: Double?) -> HourlyConditions {
        var c = self
        switch field {
        case .cloudTotal: c.cloudTotal = value
        case .cloudLow: c.cloudLow = value
        case .cloudMid: c.cloudMid = value
        case .cloudHigh: c.cloudHigh = value
        case .cloudBaseM: c.cloudBaseM = value
        case .precipChance: c.precipChance = value
        case .precipMm: c.precipMm = value
        case .visibilityKm: c.visibilityKm = value
        case .tempC: c.tempC = value
        case .dewpointC: c.dewpointC = value
        case .rhPercent: c.rhPercent = value
        case .windMs: c.windMs = value
        case .gustMs: c.gustMs = value
        case .windDirDeg: c.windDirDeg = value
        case .aod550: c.aod550 = value
        case .smokeUgm3: c.smokeUgm3 = value
        case .pm25: c.pm25 = value
        }
        return c
    }
}

extension DataState {
    /// The same value shown as stale with `age` (a fresh value becomes stale; none stays none).
    func asStale(age: Duration) -> DataState<Value> {
        switch self {
        case .fresh(let s): .stale(s, age: age)
        case .stale(let s, let a): .stale(s, age: max(a, age))
        case .none: self
        }
    }
}
