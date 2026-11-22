import Foundation

// Section 4: product definition. Templates 4.0 (instantaneous) and 4.8 (statistically processed over an interval).

/// What a field measures: GRIB2 discipline, parameter category and parameter number.
public struct GRIB2Parameter: Sendable, Hashable {
    public let discipline: Int, category: Int, number: Int
    public init(_ discipline: Int, _ category: Int, _ number: Int) {
        (self.discipline, self.category, self.number) = (discipline, category, number)
    }

    public static let temperature = GRIB2Parameter(0, 0, 0)
    public static let dewPoint = GRIB2Parameter(0, 0, 6)
    public static let relativeHumidity = GRIB2Parameter(0, 1, 1)
    public static let precipitationRate = GRIB2Parameter(0, 1, 7)
    public static let totalPrecipitation = GRIB2Parameter(0, 1, 8)
    public static let totalCloudCover = GRIB2Parameter(0, 6, 1)
    public static let lowCloudCover = GRIB2Parameter(0, 6, 3)
    public static let midCloudCover = GRIB2Parameter(0, 6, 4)
    public static let highCloudCover = GRIB2Parameter(0, 6, 5)
    public static let visibility = GRIB2Parameter(0, 19, 0)
    public static let uWind = GRIB2Parameter(0, 2, 2)
    public static let vWind = GRIB2Parameter(0, 2, 3)
    public static let windGust = GRIB2Parameter(0, 2, 22)
    public static let massDensity = GRIB2Parameter(0, 20, 0)
    public static let columnMassDensity = GRIB2Parameter(0, 20, 1)
    public static let aerosolOpticalThickness = GRIB2Parameter(0, 20, 102)
}

/// A fixed surface (code table 4.5) with its value (scale factor applied), e.g. type 103 and value 2 is 2 m above ground.
public struct GRIB2Surface: Sendable, Equatable {
    public let type: Int
    public let value: Double
}

/// A level to match against a field's first fixed surface. `value == nil` matches any value of that surface type.
public struct GRIB2Level: Sendable, Equatable {
    public let surfaceType: Int
    public let value: Double?
    public init(surfaceType: Int, value: Double? = nil) { (self.surfaceType, self.value) = (surfaceType, value) }

    public static let surface = GRIB2Level(surfaceType: 1)
    public static let entireAtmosphere = GRIB2Level(surfaceType: 10)
    public static let entireAtmosphereSingleLayer = GRIB2Level(surfaceType: 200)
    public static let lowCloudLayer = GRIB2Level(surfaceType: 214)
    public static let middleCloudLayer = GRIB2Level(surfaceType: 224)
    public static let highCloudLayer = GRIB2Level(surfaceType: 234)
    public static func heightAboveGround(_ metres: Double) -> GRIB2Level { GRIB2Level(surfaceType: 103, value: metres) }
    public static let height2m = heightAboveGround(2)
    public static let height8m = heightAboveGround(8)
    public static let height10m = heightAboveGround(10)

    public func matches(_ s: GRIB2Surface?) -> Bool {
        guard let s, s.type == surfaceType else { return false }
        return value.map { abs($0 - s.value) < 1e-6 } ?? true
    }
}

/// Template 4.8 statistics over the first time range.
public struct GRIB2Statistical: Sendable, Equatable {
    /// Code table 4.10: 0 average, 1 accumulation, 2 maximum, 3 minimum, 4 difference, ...
    public let process: Int
    public let endOfInterval: Date
    /// Length of the time range in seconds (nil when expressed in a calendar unit such as months).
    public let rangeSeconds: Int?
    public var rangeHours: Double? { rangeSeconds.map { Double($0) / 3600 } }
    public var isAccumulation: Bool { process == 1 }
    public var isAverage: Bool { process == 0 }
}

public struct GRIB2Product: Sendable, Equatable {
    public let templateNumber: Int
    public let parameter: GRIB2Parameter
    public let generatingProcess: Int
    /// Code table 4.4 unit of `forecastTime`.
    public let timeUnit: Int
    /// Forecast time in `timeUnit`: the start of the interval for template 4.8.
    public let forecastTime: Int
    public let firstSurface: GRIB2Surface?
    public let secondSurface: GRIB2Surface?
    public let statistical: GRIB2Statistical?

    /// Seconds for fixed-length units (code table 4.4); nil for months, years and longer.
    static func seconds(perUnit unit: Int) -> Int? {
        switch unit {
        case 0: 60
        case 1: 3600
        case 2: 86_400
        case 10: 10_800
        case 11: 21_600
        case 12: 43_200
        case 13: 1
        default: nil
        }
    }

    public var forecastSeconds: Int? {
        guard let per = Self.seconds(perUnit: timeUnit) else { return nil }
        let (v, overflow) = forecastTime.multipliedReportingOverflow(by: per)
        return overflow ? nil : v
    }

    init(section s: GRIB2Section, discipline: Int) throws(GRIB2Error) {
        let template = try s.int(8, 2)
        guard template == 0 || template == 8 else { throw .unsupportedProductTemplate(template) }
        templateNumber = template
        parameter = GRIB2Parameter(discipline, try s.int(10, 1), try s.int(11, 1))
        generatingProcess = try s.int(12, 1)
        timeUnit = try s.int(18, 1)
        forecastTime = try s.signed(19, 4)
        firstSurface = try Self.surface(s, typeOctet: 23)
        secondSurface = try Self.surface(s, typeOctet: 29)
        if template == 8 {
            let c = (try s.int(35, 2), try s.int(37, 1), try s.int(38, 1), try s.int(39, 1), try s.int(40, 1), try s.int(41, 1))
            guard let end = GRIB2Time.epochSeconds(year: c.0, month: c.1, day: c.2, hour: c.3, minute: c.4, second: c.5) else {
                throw .invalidReferenceTime
            }
            let length = try s.int(50, 4)
            let range = Self.seconds(perUnit: try s.int(49, 1)).flatMap { per -> Int? in
                let (v, o) = length.multipliedReportingOverflow(by: per)
                return o ? nil : v
            }
            statistical = GRIB2Statistical(
                process: try s.int(47, 1), endOfInterval: Date(timeIntervalSince1970: TimeInterval(end)), rangeSeconds: range)
        } else {
            statistical = nil
        }
    }

    /// Surface type, scale factor (sign-magnitude) and scaled value; type 255 (missing) means no surface.
    private static func surface(_ s: GRIB2Section, typeOctet: Int) throws(GRIB2Error) -> GRIB2Surface? {
        let type = try s.int(typeOctet, 1)
        guard type != 255 else { return nil }
        let scale = try s.signed(typeOctet + 1, 1)
        let scaled = try s.uint(typeOctet + 2, 4)
        guard scaled != 0xFFFF_FFFF, abs(scale) < 300 else { return GRIB2Surface(type: type, value: 0) }
        return GRIB2Surface(type: type, value: Double(scaled) / pow(10, Double(scale)))
    }
}
