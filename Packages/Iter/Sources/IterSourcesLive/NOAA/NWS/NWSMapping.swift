import Foundation
import IterModel
import IterSources

/// Pure mapping for api.weather.gov (GeoJSON): alerts, the observation-station list and the latest observation.
///
/// Observation values arrive as `{unitCode, value}` in SI-like WMO units and are converted: `degC`, `km_h-1` and
/// `m_s-1` to m/s, `m` visibility to km, `percent` as is, pressure ignored. A null value stays nil; nothing is computed
/// for a missing field.
public enum NWSMapping {
    public struct Alerts: Sendable, Hashable {
        public var alerts: [WeatherAlert]
        /// The collection's `updated` time.
        public var updated: Date?
    }

    public struct Station: Sendable, Hashable {
        public var id: String
        public var name: String?
        public var coordinate: Coordinate
    }

    public struct LatestObservation: Sendable, Hashable {
        public var stationID: String?
        public var observation: WeatherObservation
        public var rawMessage: String?
    }

    // MARK: Alerts

    public static func alerts(from data: Data) throws -> Alerts {
        let doc: AlertCollection = try decode(data, "alerts")
        let alerts = doc.features.compactMap { f -> WeatherAlert? in
            let p = f.properties
            guard let id = p.id ?? p.atID, let event = p.event else { return nil }
            return WeatherAlert(
                id: id, event: event, headline: p.headline, severity: severity(p.severity), urgency: p.urgency,
                certainty: p.certainty, areaDescription: p.areaDesc, onset: NWSDates.parse(p.onset),
                ends: NWSDates.parse(p.ends), expires: NWSDates.parse(p.expires), senderName: p.senderName,
                description: p.description, instruction: p.instruction, url: (p.atID ?? p.id).flatMap(URL.init(string:)))
        }
        return Alerts(alerts: alerts, updated: NWSDates.parse(doc.updated))
    }

    static func severity(_ s: String?) -> WeatherAlert.Severity {
        switch s?.lowercased() {
        case "extreme": .extreme
        case "severe": .severe
        case "moderate": .moderate
        case "minor": .minor
        default: .unknown
        }
    }

    // MARK: Points and stations

    /// `properties.observationStations` from a `/points/{lat},{lon}` response.
    public static func observationStationsURL(fromPoints data: Data) throws -> URL {
        let doc: PointsDocument = try decode(data, "points")
        guard let s = doc.properties.observationStations, let url = URL(string: s), url.scheme == "https" else {
            throw SourceError.decoding("api.weather.gov points: no observationStations URL")
        }
        return url
    }

    /// The stations of a `/gridpoints/.../stations` response, in the feed's order.
    public static func stations(from data: Data) throws -> [Station] {
        let doc: StationCollection = try decode(data, "stations")
        return doc.features.compactMap { f in
            guard let id = f.properties.stationIdentifier, let c = f.geometry?.coordinates, c.count >= 2 else { return nil }
            return Station(id: id, name: f.properties.name, coordinate: Coordinate(latitude: c[1], longitude: c[0]))
        }
    }

    // MARK: Observation

    /// The `/stations/{id}/observations/latest` feature. Nil when it has no timestamp.
    public static func latestObservation(from data: Data) throws -> LatestObservation? {
        let doc: ObservationFeature = try decode(data, "observation")
        let p = doc.properties
        guard let time = NWSDates.parse(p.timestamp) else { return nil }

        let layers: [CloudLayer] = (p.cloudLayers ?? []).compactMap { l in
            guard let cover = cover(l.amount) else { return nil }
            return CloudLayer(cover: cover, baseM: l.base?.si(.meters))
        }
        let conditions = ObservedSky.conditions(
            time: time, tempC: p.temperature?.si(.celsius), dewpointC: p.dewpoint?.si(.celsius),
            windDirDeg: p.windDirection?.value, windMs: p.windSpeed?.si(.metresPerSecond),
            gustMs: p.windGust?.si(.metresPerSecond), visibilityKm: p.visibility?.si(.meters).map { $0 / 1000 },
            layers: layers, hasSkyGroup: !layers.isEmpty, precipMm: p.precipitationLastHour?.si(.millimetres),
            rhPercent: p.relativeHumidity?.value, computeHumidity: false)
        return LatestObservation(
            stationID: p.stationId, observation: WeatherObservation(time: time, stationName: p.stationName, conditions: conditions),
            rawMessage: p.rawMessage)
    }

    static func cover(_ amount: String?) -> CloudLayer.Cover? {
        switch amount?.uppercased() {
        case "SKC": .skc
        case "CLR": .clr
        case "NSC": .nsc
        case "FEW": .few
        case "SCT": .sct
        case "BKN": .bkn
        case "OVC": .ovc
        case "VV", "OVX": .vv
        default: nil
        }
    }

    // MARK: Decoding

    private static func decode<T: Decodable>(_ data: Data, _ what: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw SourceError.decoding("api.weather.gov \(what): \(error)")
        }
    }

    struct Quantity: Decodable {
        var unitCode: String?
        var value: Double?

        enum Target { case celsius, metresPerSecond, meters, millimetres }

        /// The value converted to the target unit, from its `unitCode`; nil when null or the unit is unknown.
        func si(_ target: Target) -> Double? {
            guard let value else { return nil }
            let unit = (unitCode ?? "").replacingOccurrences(of: "wmoUnit:", with: "").replacingOccurrences(of: "unit:", with: "")
            switch (target, unit) {
            case (.celsius, "degC"): return value
            case (.celsius, "degF"): return (value - 32) * 5 / 9
            case (.celsius, "K"): return value - 273.15
            case (.metresPerSecond, "km_h-1"): return value / 3.6
            case (.metresPerSecond, "m_s-1"): return value
            case (.metresPerSecond, "kt"), (.metresPerSecond, "[kn_i]"): return value * 0.514444
            case (.meters, "m"): return value
            case (.meters, "km"): return value * 1000
            case (.meters, "[ft_i]"): return value * 0.3048
            case (.millimetres, "mm"): return value
            case (.millimetres, "m"): return value * 1000
            default: return nil
            }
        }
    }

    struct AlertCollection: Decodable {
        var features: [AlertFeature]
        var updated: String?
    }
    struct AlertFeature: Decodable { var properties: AlertProperties }
    struct AlertProperties: Decodable {
        var atID: String?
        var id: String?
        var areaDesc: String?
        var onset: String?
        var ends: String?
        var expires: String?
        var severity: String?
        var certainty: String?
        var urgency: String?
        var event: String?
        var senderName: String?
        var headline: String?
        var description: String?
        var instruction: String?
        enum CodingKeys: String, CodingKey {
            case atID = "@id", id, areaDesc, onset, ends, expires, severity, certainty, urgency, event, senderName, headline,
                 description, instruction
        }
    }

    struct PointsDocument: Decodable {
        var properties: Props
        struct Props: Decodable { var observationStations: String? }
    }

    struct StationCollection: Decodable {
        var features: [StationFeature]
        struct StationFeature: Decodable {
            var geometry: Geometry?
            var properties: Props
        }
        struct Geometry: Decodable { var coordinates: [Double]? }
        struct Props: Decodable {
            var stationIdentifier: String?
            var name: String?
        }
    }

    struct ObservationFeature: Decodable {
        var properties: Props
        struct Props: Decodable {
            var stationId: String?
            var stationName: String?
            var timestamp: String?
            var rawMessage: String?
            var temperature: Quantity?
            var dewpoint: Quantity?
            var windDirection: Quantity?
            var windSpeed: Quantity?
            var windGust: Quantity?
            var visibility: Quantity?
            var relativeHumidity: Quantity?
            var precipitationLastHour: Quantity?
            var cloudLayers: [Layer]?
        }
        struct Layer: Decodable {
            var base: Quantity?
            var amount: String?
        }
    }
}

enum NWSDates {
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
