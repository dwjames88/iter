import Foundation
import IterModel

/// The aurora outlook for a place: the Kp forecast and the local probability, when the source gives one.
public struct AuroraOutlook: Codable, Hashable, Sendable {
    /// One three-hour Kp step; `time` is the start of the step.
    public struct KpStep: Codable, Hashable, Sendable {
        public var time: Date
        public var value: Double

        public init(time: Date, value: Double) {
            self.time = time
            self.value = value
        }
    }

    public var kp: [KpStep]
    /// Chance of visible aurora overhead, 0...100.
    public var probabilityPercent: Double?
    public var provenance: Provenance?

    public init(kp: [KpStep] = [], probabilityPercent: Double? = nil, provenance: Provenance? = nil) {
        self.kp = kp
        self.probabilityPercent = probabilityPercent
        self.provenance = provenance
    }
}

/// Everything the Forecast Sky Index reads. Every part is optional: a missing part drops its factor, lowers confidence
/// and produces a note.
public struct ForecastSkyInputs: Hashable, Sendable {
    public var hourly: HourlySeries?
    /// Where the hourly series came from and when. Without it the forecast cannot be dated, so it is not scored.
    public var provenance: Provenance?
    /// After `provenance.fetchedAt + ttl` the forecast is stale.
    public var ttl: TimeInterval
    /// The terrain skyline; when nil the place's own horizon is used.
    public var horizon: HorizonProfile?
    public var aurora: AuroraOutlook?
    /// Bortle class 1...9. No source supplies it today; it is never defaulted.
    public var bortle: Double?
    /// Astronomical seeing in arcseconds. No source supplies it today; it is never defaulted.
    public var seeing: Double?
    /// Other sources' hourly series, read only for total cloud, to detect disagreement (the spread rule).
    public var spreadSeries: [HourlySeries]

    public init(hourly: HourlySeries? = nil, provenance: Provenance? = nil, ttl: TimeInterval = Freshness.defaultTTL,
                horizon: HorizonProfile? = nil, aurora: AuroraOutlook? = nil, bortle: Double? = nil, seeing: Double? = nil,
                spreadSeries: [HourlySeries] = []) {
        self.hourly = hourly
        self.provenance = provenance
        self.ttl = ttl
        self.horizon = horizon
        self.aurora = aurora
        self.bortle = bortle
        self.seeing = seeing
        self.spreadSeries = spreadSeries
    }

    /// From the model's `SkyInputs` (hourly, horizon and Bortle), plus the parts it does not carry.
    public init(_ inputs: SkyInputs, provenance: Provenance?, ttl: TimeInterval = Freshness.defaultTTL,
                aurora: AuroraOutlook? = nil, seeing: Double? = nil, spreadSeries: [HourlySeries] = []) {
        self.init(hourly: inputs.hourly, provenance: provenance, ttl: ttl, horizon: inputs.horizon, aurora: aurora,
                  bortle: inputs.bortle, seeing: seeing, spreadSeries: spreadSeries)
    }
}

// MARK: - Reading a series

extension HourlySeries {
    /// The earliest hour's start.
    var firstTime: Date? { hours.map(\.time).min() }

    /// The instant after the last hour (each row covers one hour).
    var horizonDate: Date? { hours.map(\.time).max().map { $0.addingTimeInterval(3600) } }

    /// How many consecutive local days, starting at `day`, begin before the end of the data (0 when there are no hours).
    func coveredDays(from day: LocalDay, in zone: TimeZone) -> Int {
        guard let horizon = horizonDate else { return 0 }
        var count = 0
        while day.adding(days: count).start(in: zone) < horizon { count += 1 }
        return count
    }

    /// Rows overlapping `span`.
    func hours(overlapping span: TimeSpan) -> [HourlyConditions] {
        hours.filter { $0.time < span.end && $0.time.addingTimeInterval(3600) > span.start }
    }
}
