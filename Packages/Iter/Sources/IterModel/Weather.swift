import Foundation

/// The weather and air fields an hourly row can carry. A composite series records which source supplied each.
public enum HourlyField: String, Codable, Sendable, CaseIterable, Hashable {
    case cloudTotal, cloudLow, cloudMid, cloudHigh, cloudBaseM
    case precipChance, precipMm, visibilityKm
    case tempC, dewpointC, rhPercent
    case windMs, gustMs, windDirDeg
    case aod550, smokeUgm3, pm25
}

/// One hour of conditions. Every field is optional: a source supplies what it has, and a gap is a gap, never a zero.
public struct HourlyConditions: Codable, Hashable, Sendable {
    public var time: Date
    /// Cloud cover fractions are 0...1 per layer as the source gives them (total, low, mid, high).
    public var cloudTotal: Double?
    public var cloudLow: Double?
    public var cloudMid: Double?
    public var cloudHigh: Double?
    /// Cloud base height, metres above ground.
    public var cloudBaseM: Double?
    /// 0...1.
    public var precipChance: Double?
    public var precipMm: Double?
    public var visibilityKm: Double?
    public var tempC: Double?
    public var dewpointC: Double?
    public var rhPercent: Double?
    public var windMs: Double?
    public var gustMs: Double?
    public var windDirDeg: Double?
    /// Aerosol optical depth at 550 nm.
    public var aod550: Double?
    /// Smoke, micrograms per cubic metre.
    public var smokeUgm3: Double?
    public var pm25: Double?

    public init(time: Date, cloudTotal: Double? = nil, cloudLow: Double? = nil, cloudMid: Double? = nil, cloudHigh: Double? = nil,
                cloudBaseM: Double? = nil, precipChance: Double? = nil, precipMm: Double? = nil, visibilityKm: Double? = nil,
                tempC: Double? = nil, dewpointC: Double? = nil, rhPercent: Double? = nil, windMs: Double? = nil,
                gustMs: Double? = nil, windDirDeg: Double? = nil, aod550: Double? = nil, smokeUgm3: Double? = nil,
                pm25: Double? = nil) {
        self.time = time
        self.cloudTotal = cloudTotal
        self.cloudLow = cloudLow
        self.cloudMid = cloudMid
        self.cloudHigh = cloudHigh
        self.cloudBaseM = cloudBaseM
        self.precipChance = precipChance
        self.precipMm = precipMm
        self.visibilityKm = visibilityKm
        self.tempC = tempC
        self.dewpointC = dewpointC
        self.rhPercent = rhPercent
        self.windMs = windMs
        self.gustMs = gustMs
        self.windDirDeg = windDirDeg
        self.aod550 = aod550
        self.smokeUgm3 = smokeUgm3
        self.pm25 = pm25
    }

    /// The value of one field.
    public subscript(field: HourlyField) -> Double? {
        switch field {
        case .cloudTotal: cloudTotal
        case .cloudLow: cloudLow
        case .cloudMid: cloudMid
        case .cloudHigh: cloudHigh
        case .cloudBaseM: cloudBaseM
        case .precipChance: precipChance
        case .precipMm: precipMm
        case .visibilityKm: visibilityKm
        case .tempC: tempC
        case .dewpointC: dewpointC
        case .rhPercent: rhPercent
        case .windMs: windMs
        case .gustMs: gustMs
        case .windDirDeg: windDirDeg
        case .aod550: aod550
        case .smokeUgm3: smokeUgm3
        case .pm25: pm25
        }
    }

    /// The fields that carry a value.
    public var presentFields: [HourlyField] { HourlyField.allCases.filter { self[$0] != nil } }
}

/// A run of hourly rows. For a composite forecast, `fieldSources` says which source supplied each field, so the UI can
/// say "Cloud layers: <source>; Smoke: <source>". Fields absent from the map come from `source`-less data (unknown).
public struct HourlySeries: Hashable, Sendable {
    public var hours: [HourlyConditions]
    public var fieldSources: [HourlyField: SourceID]

    public init(hours: [HourlyConditions], fieldSources: [HourlyField: SourceID] = [:]) {
        self.hours = hours
        self.fieldSources = fieldSources
    }

    public func source(of field: HourlyField) -> SourceID? { fieldSources[field] }

    /// The row whose hour contains `date`, if any (the last row starting at or before it, within one hour).
    public func hour(at date: Date) -> HourlyConditions? {
        hours.last { $0.time <= date && date.timeIntervalSince($0.time) < 3600 }
    }
}

// Enum-keyed dictionaries encode as arrays in Codable; store the source map as a string-keyed object instead.
extension HourlySeries: Codable {
    private enum CodingKeys: String, CodingKey { case hours, fieldSources }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hours = try c.decodeIfPresent([HourlyConditions].self, forKey: .hours) ?? []
        let raw = try c.decodeIfPresent([String: SourceID].self, forKey: .fieldSources) ?? [:]
        var map: [HourlyField: SourceID] = [:]
        for (key, value) in raw { if let f = HourlyField(rawValue: key) { map[f] = value } }
        fieldSources = map
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hours, forKey: .hours)
        try c.encode(Dictionary(uniqueKeysWithValues: fieldSources.map { ($0.key.rawValue, $0.value) }), forKey: .fieldSources)
    }
}

/// What a station or analysis measured at a time (as opposed to forecast).
public struct Observation: Codable, Hashable, Sendable {
    public var time: Date
    public var stationName: String?
    public var conditions: HourlyConditions

    public init(time: Date, stationName: String? = nil, conditions: HourlyConditions? = nil) {
        self.time = time
        self.stationName = stationName
        self.conditions = conditions ?? HourlyConditions(time: time)
    }
}

/// One step of a short-range (minutes ahead) precipitation and cloud nowcast.
public struct NowcastStep: Codable, Hashable, Sendable {
    public var time: Date
    /// Rain rate, millimetres per hour.
    public var precipMmPerHour: Double?
    public var precipChance: Double?
    public var cloudTotal: Double?

    public init(time: Date, precipMmPerHour: Double? = nil, precipChance: Double? = nil, cloudTotal: Double? = nil) {
        self.time = time
        self.precipMmPerHour = precipMmPerHour
        self.precipChance = precipChance
        self.cloudTotal = cloudTotal
    }
}

/// Everything the sky score reads for one place: forecast rows, the latest observation, the nowcast, the terrain horizon
/// and the night-sky darkness. Every part is optional; a missing part is a gap.
public struct SkyInputs: Codable, Hashable, Sendable {
    public var coordinate: Coordinate
    public var hourly: HourlySeries?
    public var observation: Observation?
    public var nowcast: [NowcastStep]
    public var horizon: HorizonProfile?
    /// Bortle class 1...9 (lower is darker), if known.
    public var bortle: Double?

    public init(coordinate: Coordinate, hourly: HourlySeries? = nil, observation: Observation? = nil, nowcast: [NowcastStep] = [],
                horizon: HorizonProfile? = nil, bortle: Double? = nil) {
        self.coordinate = coordinate
        self.hourly = hourly
        self.observation = observation
        self.nowcast = nowcast
        self.horizon = horizon
        self.bortle = bortle
    }
}

/// The terrain horizon around a place: the elevation angle of the skyline at evenly spaced azimuths, clockwise from north.
/// The standard profile is 72 values at 5 degrees.
public struct HorizonProfile: Codable, Hashable, Sendable {
    public static let standardStepDegrees = 5.0
    public static let standardCount = 72

    /// Degrees between samples (360 / count).
    public var azimuthStepDegrees: Double
    /// Skyline elevation in degrees at azimuth 0, step, 2 × step, ... Negative when the horizon is below level.
    public var elevationsDegrees: [Double]

    public init(azimuthStepDegrees: Double = HorizonProfile.standardStepDegrees, elevationsDegrees: [Double]) {
        self.azimuthStepDegrees = azimuthStepDegrees > 0 ? azimuthStepDegrees : HorizonProfile.standardStepDegrees
        self.elevationsDegrees = elevationsDegrees
    }

    /// A level horizon at the standard resolution.
    public static var flat: HorizonProfile {
        HorizonProfile(elevationsDegrees: Array(repeating: 0, count: standardCount))
    }

    /// The skyline elevation toward `azimuth` (degrees, any value; wrapped to 0..<360), linearly interpolated between the two
    /// nearest samples and wrapping from the last sample back to the first. 0 for an empty profile.
    public func elevation(atAzimuth azimuth: Double) -> Double {
        let n = elevationsDegrees.count
        guard n > 0 else { return 0 }
        let wrapped = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let position = wrapped / azimuthStepDegrees
        let lower = Int(position.rounded(.down)) % n
        let upper = (lower + 1) % n
        let t = position - position.rounded(.down)
        return elevationsDegrees[lower] * (1 - t) + elevationsDegrees[upper] * t
    }

    /// True when the sun or moon at `altitude` (degrees) toward `azimuth` is above the skyline.
    public func isVisible(altitude: Double, azimuth: Double) -> Bool { altitude > elevation(atAzimuth: azimuth) }
}
