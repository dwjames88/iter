import Foundation

/// The two forecast models served through the NOMADS GRIB filter, and one file of one model run.

public enum NOMADSModel: String, Sendable, Hashable, CaseIterable, Codable {
    case hrrr, gfs

    public var label: String { self == .hrrr ? "HRRR" : "GFS" }

    /// Hours between model cycles (HRRR runs every hour, GFS every 6 hours).
    var cycleStepHours: Int { self == .hrrr ? 1 : 6 }

    /// Largest forecast hour a cycle produces: HRRR 48 on 00/06/12/18Z and 18 otherwise, GFS 384.
    public func maxForecastHour(cycleHourUTC h: Int) -> Int {
        switch self {
        case .hrrr: h % 6 == 0 ? 48 : 18
        case .gfs: 384
        }
    }

    /// Whether the model publishes this forecast hour: HRRR f01 up to the cycle's limit; GFS f001...f120 hourly, then
    /// every third hour to f384 (f000, the analysis, is never used).
    public func publishes(forecastHour fh: Int, cycleHourUTC h: Int) -> Bool {
        guard fh >= 1, fh <= maxForecastHour(cycleHourUTC: h) else { return false }
        switch self {
        case .hrrr: return true
        case .gfs: return fh <= 120 || fh % 3 == 0
        }
    }

    /// Zero-padded forecast-hour label: `f01` for HRRR, `f003` for GFS.
    func hourLabel(_ fh: Int) -> String { self == .hrrr ? String(format: "f%02d", fh) : String(format: "f%03d", fh) }
}

/// One file of one model run: model, cycle (UTC, on the hour) and forecast hour.
public struct NOMADSFileRef: Sendable, Hashable, CustomStringConvertible {
    public let model: NOMADSModel
    public let cycle: Date
    public let forecastHour: Int

    public init(model: NOMADSModel, cycle: Date, forecastHour: Int) {
        self.model = model
        self.cycle = cycle
        self.forecastHour = forecastHour
    }

    public var validTime: Date { cycle.addingTimeInterval(TimeInterval(forecastHour) * 3600) }
    public var cycleHourUTC: Int { NOMADSTime.hour(of: cycle) }
    /// `yyyyMMdd` of the cycle (the directory date).
    public var dateStamp: String { NOMADSTime.dateStamp(cycle) }
    /// `yyyyMMddHH`.
    public var cycleStamp: String { dateStamp + String(format: "%02d", cycleHourUTC) }
    /// `f01` / `f003`.
    public var hourLabel: String { model.hourLabel(forecastHour) }
    /// The cache bucket: "<model> <yyyyMMddHH> f<FFF>" (three-digit hour for both models).
    public var cacheBucket: String { "\(model.rawValue) \(cycleStamp) f\(String(format: "%03d", forecastHour))" }
    public var description: String { "\(model.label) \(cycleStamp) \(hourLabel)" }
}

/// UTC calendar arithmetic on whole hours (cycles are always on the hour).
enum NOMADSTime {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? c.timeZone
        return c
    }()

    /// Rounds down to a whole hour (UTC instants on the hour are multiples of 3600 s).
    static func floorHour(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    static func ceilHour(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.up) * 3600)
    }

    static func hour(of d: Date) -> Int { calendar.component(.hour, from: d) }

    static func dateStamp(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "2026-11-22 12Z".
    static func cycleLabel(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: d)
        return String(format: "%04d-%02d-%02d %02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0)
    }
}
