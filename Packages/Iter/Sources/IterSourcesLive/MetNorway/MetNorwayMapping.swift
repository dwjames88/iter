import Foundation
import IterModel
import IterSources

/// Pure mapping from a MET Norway locationforecast 2.0 `complete` document to hourly rows.
///
/// Unit rules: cloud and probability percentages become 0...1; wind is already m/s; temperatures are degrees Celsius.
/// `fog_area_fraction` is not a model field and is ignored (visibility stays nil: nothing is inferred from fog).
/// Precipitation comes only from `next_1_hours.details.precipitation_amount`; a row that has only `next_6_hours`
/// gets `precipMm == nil` (a 6 h total is never spread over six rows).
public enum MetNorwayMapping {
    public struct Forecast: Sendable, Hashable {
        /// Rows at the model's native valid times, ascending (hourly early, 6-hourly later).
        public var hours: [HourlyConditions]
        /// `properties.meta.updated_at`: when the model run behind the document was published.
        public var updatedAt: Date?
    }

    /// Decodes `data` and keeps the rows whose valid time lies inside `span` (all rows when `span` is nil).
    public static func forecast(from data: Data, span: TimeSpan?) throws -> Forecast {
        let doc: Document
        do { doc = try JSONDecoder().decode(Document.self, from: data) } catch {
            throw SourceError.decoding("MET Norway locationforecast: \(error)")
        }
        var rows: [HourlyConditions] = []
        for entry in doc.properties.timeseries {
            guard let time = parseDate(entry.time) else { continue }
            if let span, !span.contains(time) { continue }
            rows.append(row(entry, at: time))
        }
        rows.sort { $0.time < $1.time }
        return Forecast(hours: rows, updatedAt: parseDate(doc.properties.meta?.updatedAt))
    }

    static func row(_ entry: Entry, at time: Date) -> HourlyConditions {
        let i = entry.data.instant?.details ?? [:]
        let next1 = entry.data.next1Hours?.details ?? [:]
        let next6 = entry.data.next6Hours?.details ?? [:]
        func fraction(_ key: String) -> Double? { i[key].map { min(1, max(0, $0 / 100)) } }
        let chance = (next1["probability_of_precipitation"] ?? next6["probability_of_precipitation"])
            .map { min(1, max(0, $0 / 100)) }
        return HourlyConditions(
            time: time,
            cloudTotal: fraction("cloud_area_fraction"),
            cloudLow: fraction("cloud_area_fraction_low"),
            cloudMid: fraction("cloud_area_fraction_medium"),
            cloudHigh: fraction("cloud_area_fraction_high"),
            precipChance: chance,
            precipMm: next1["precipitation_amount"],
            tempC: i["air_temperature"],
            dewpointC: i["dew_point_temperature"],
            rhPercent: i["relative_humidity"],
            windMs: i["wind_speed"],
            gustMs: i["wind_speed_of_gust"],
            windDirDeg: i["wind_from_direction"])
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    // MARK: Decoding

    struct Document: Decodable {
        var properties: Properties
        struct Properties: Decodable {
            var meta: Meta?
            var timeseries: [Entry]
        }
        struct Meta: Decodable {
            var updatedAt: String?
            enum CodingKeys: String, CodingKey { case updatedAt = "updated_at" }
        }
    }

    struct Entry: Decodable {
        var time: String
        var data: Block
    }

    struct Block: Decodable {
        var instant: Details?
        var next1Hours: Details?
        var next6Hours: Details?
        enum CodingKeys: String, CodingKey {
            case instant
            case next1Hours = "next_1_hours"
            case next6Hours = "next_6_hours"
        }
    }

    /// `{ "details": { name: number } }`; non-numeric entries are ignored.
    struct Details: Decodable {
        var details: [String: Double]?
        enum CodingKeys: String, CodingKey { case details }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            details = try? c.decodeIfPresent([String: Double].self, forKey: .details)
        }
    }
}
