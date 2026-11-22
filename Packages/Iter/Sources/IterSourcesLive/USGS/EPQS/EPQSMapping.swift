import Foundation
import IterSources

/// Pure mapping for the USGS 3DEP Elevation Point Query Service (`/v1/json`).
///
/// A good answer is JSON with `value` (a decimal string, metres) and `resolution` (source DEM metres). Outside the US the
/// service answers HTTP 200 with plain text starting "Call failed."; a point with no data inside its area returns the
/// no-data value -1000000. Both are `.outsideCoverage`. Anything else unreadable is `.decoding`.
public enum EPQSMapping {
    public struct Result: Sendable, Equatable {
        public var elevationM: Double
        /// Resolution of the DEM that answered, metres, when reported.
        public var resolutionM: Double?
    }

    /// The no-data sentinel EPQS returns.
    public static let noDataValue = -1_000_000.0

    public static func elevation(from data: Data) throws -> Result {
        let object = try? JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            let text = String(decoding: data.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("Call failed") { throw SourceError.outsideCoverage }
            throw SourceError.decoding("EPQS answer is neither JSON nor a known failure: \(text.prefix(80))")
        }
        let value: Double?
        switch dict["value"] {
        case let s as String: value = Double(s)
        case let n as NSNumber: value = n.doubleValue
        default: value = nil
        }
        guard let v = value, v.isFinite else { throw SourceError.decoding("EPQS JSON has no numeric value") }
        if v <= noDataValue + 1 { throw SourceError.outsideCoverage }
        let resolution: Double?
        switch dict["resolution"] {
        case let s as String: resolution = Double(s)
        case let n as NSNumber: resolution = n.doubleValue
        default: resolution = nil
        }
        return Result(elevationM: v, resolutionM: resolution)
    }
}
