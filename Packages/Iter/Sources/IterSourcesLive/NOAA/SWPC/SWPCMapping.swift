import Foundation
import IterModel
import IterSources

/// Pure mapping for the NOAA SWPC feeds: the OVATION aurora grid, the 1-minute planetary Kp, and the 3-hour Kp forecast.
public enum SWPCMapping {
    // MARK: OVATION grid

    /// The OVATION nowcast: aurora probability (percent) on a 1 degree grid, longitude 0...359, latitude -90...90.
    public struct OvationGrid: Sendable, Equatable {
        public static let longitudes = 360
        public static let latitudes = 181

        public var observedAt: Date
        public var forecastFor: Date
        /// Percent, index `longitude * 181 + (latitude + 90)`; -1 for a cell the file did not list.
        let cells: [Int16]

        init(observedAt: Date, forecastFor: Date, cells: [Int16]) {
            self.observedAt = observedAt
            self.forecastFor = forecastFor
            self.cells = cells
        }

        /// A grid from explicit `[longitude, latitude, percent]` triples (tests and parsing).
        public init(observedAt: Date, forecastFor: Date, triples: [[Double]]) throws {
            var cells = [Int16](repeating: -1, count: Self.longitudes * Self.latitudes)
            for t in triples {
                guard t.count == 3, t[0].isFinite, t[1].isFinite, t[2].isFinite else {
                    throw SourceError.decoding("OVATION row is not [longitude, latitude, aurora]")
                }
                let lon = Int(t[0]), lat = Int(t[1])
                guard (0..<Self.longitudes).contains(lon), (-90...90).contains(lat) else {
                    throw SourceError.decoding("OVATION cell outside the grid: \(t)")
                }
                cells[lon * Self.latitudes + lat + 90] = Int16(clamping: Int(t[2].rounded()))
            }
            self.init(observedAt: observedAt, forecastFor: forecastFor, cells: cells)
        }

        /// The grid cell (longitude 0...359, latitude -90...90) nearest to a coordinate. Longitudes outside 0...360
        /// are wrapped, so -0.4 and 359.6 both land on cell 0. Exact half-degrees round away from zero.
        public static func cell(for c: Coordinate) -> (longitude: Int, latitude: Int) {
            var lon = c.longitude.truncatingRemainder(dividingBy: 360)
            if lon < 0 { lon += 360 }
            let lat = min(90, max(-90, Int(c.latitude.rounded())))
            return (Int(lon.rounded()) % longitudes, lat)
        }

        /// Percent at the nearest cell; nil if the file did not list that cell.
        public func probability(at c: Coordinate) -> Double? {
            let cell = Self.cell(for: c)
            let v = cells[cell.longitude * Self.latitudes + cell.latitude + 90]
            return v < 0 ? nil : Double(v)
        }
    }

    private struct OvationFile: Decodable {
        let observed: String
        let forecast: String
        let coordinates: [[Double]]
        enum CodingKeys: String, CodingKey {
            case observed = "Observation Time", forecast = "Forecast Time", coordinates
        }
    }

    /// Parses `ovation_aurora_latest.json`.
    public static func ovation(from data: Data) throws -> OvationGrid {
        let file: OvationFile
        do { file = try JSONDecoder().decode(OvationFile.self, from: data) } catch {
            throw SourceError.decoding("OVATION aurora JSON: \(error)")
        }
        guard let observed = SWPCUTC.parse(file.observed), let forecast = SWPCUTC.parse(file.forecast) else {
            throw SourceError.decoding("OVATION times: \(file.observed) / \(file.forecast)")
        }
        guard !file.coordinates.isEmpty else { throw SourceError.decoding("OVATION grid is empty") }
        return try OvationGrid(observedAt: observed, forecastFor: forecast, triples: file.coordinates)
    }

    // MARK: Planetary Kp, 1 minute

    /// The newest row of `planetary_k_index_1m.json`.
    public struct KpNow: Sendable, Equatable {
        public var kp: Double
        public var observedAt: Date
    }

    /// Kp from a letter-suffixed value such as "1Z" (1.0), "2P" (2.33), "2M" (1.67). Nil when not of that form.
    public static func kp(fromLabel label: String) -> Double? {
        guard let last = label.last, let base = Double(label.dropLast()) else { return nil }
        switch last {
        case "Z", "z": return base
        case "P", "p": return base + 1.0 / 3.0
        case "M", "m": return base - 1.0 / 3.0
        default: return nil
        }
    }

    /// The latest row (by `time_tag`): `estimated_kp`, else `kp_index`, else the `kp` label. The times carry no zone and are UTC.
    public static func kpNow(from data: Data) throws -> KpNow {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw SourceError.decoding("planetary_k_index_1m.json is not an array of objects")
        }
        var best: (time: Date, row: [String: Any])?
        for row in rows {
            guard let tag = row["time_tag"] as? String, let t = SWPCUTC.parse(tag) else { continue }
            if best == nil || t > best!.time { best = (t, row) }
        }
        guard let (time, row) = best else { throw SourceError.decoding("no Kp rows with a valid time_tag") }
        if let v = (row["estimated_kp"] as? NSNumber)?.doubleValue { return KpNow(kp: v, observedAt: time) }
        if let v = (row["kp_index"] as? NSNumber)?.doubleValue { return KpNow(kp: v, observedAt: time) }
        if let label = row["kp"] as? String, let v = kp(fromLabel: label) { return KpNow(kp: v, observedAt: time) }
        throw SourceError.decoding("latest Kp row has no estimated_kp, kp_index or kp")
    }

    // MARK: Kp forecast

    /// Parses `noaa-planetary-k-index-forecast.json`. The recorded shape is an array of objects
    /// (`time_tag`, `kp`, `observed`, `noaa_scale`); the older array-of-arrays shape with a header row is read too.
    /// Oldest first.
    public static func kpForecast(from data: Data) throws -> [KpPeriod] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw SourceError.decoding("Kp forecast is not a JSON array")
        }
        var objects: [[String: Any]] = []
        if let rows = json as? [[String: Any]] {
            objects = rows
        } else if let table = json as? [[Any]], let header = table.first?.compactMap({ $0 as? String }) {
            for row in table.dropFirst() {
                var o: [String: Any] = [:]
                for (i, key) in header.enumerated() where i < row.count { o[key] = row[i] }
                objects.append(o)
            }
        } else {
            throw SourceError.decoding("Kp forecast rows are neither objects nor a table")
        }
        var out: [KpPeriod] = []
        for o in objects {
            guard let tag = o["time_tag"] as? String, let start = SWPCUTC.parse(tag) else {
                throw SourceError.decoding("Kp forecast row without a valid time_tag: \(o)")
            }
            let kpValue: Double
            if let n = o["kp"] as? NSNumber { kpValue = n.doubleValue }
            else if let s = o["kp"] as? String, let v = Double(s) ?? kp(fromLabel: s) { kpValue = v }
            else { throw SourceError.decoding("Kp forecast row without a kp value: \(o)") }
            guard let kindText = o["observed"] as? String, let kind = KpPeriod.Kind(rawValue: kindText) else {
                throw SourceError.decoding("Kp forecast row with an unknown 'observed' value: \(o["observed"] ?? "nil")")
            }
            let scale = (o["noaa_scale"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            out.append(KpPeriod(start: start, kp: kpValue, kind: kind, noaaScale: scale))
        }
        guard !out.isEmpty else { throw SourceError.decoding("Kp forecast is empty") }
        return out.sorted { $0.start < $1.start }
    }
}
