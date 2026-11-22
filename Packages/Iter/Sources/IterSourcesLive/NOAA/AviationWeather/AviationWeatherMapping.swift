import Foundation
import IterModel
import IterSources

/// Pure mapping from aviationweather.gov JSON (`/api/data/metar?format=json`) and raw TAF text to `StationReport`s.
///
/// Units: wind knots to m/s (×0.514444), visibility statute miles to km (×1.609344), cloud bases feet AGL to metres.
/// JSON `wdir` may be a number or "VRB" (nil direction); `visib` may be a number or a capped string such as "10+".
/// A capped string is replaced by the raw report's own value when that is at least as large (9999 m is 10 km, while
/// the feed's "6+" would give 9.7 km). Missing values stay nil: a record without `temp`, `wdir` or sky data
/// produces nil fields (the partial KNID report has no wind, visibility or sky).
public enum AviationWeatherMapping {
    /// One decoded METAR record (internal shape of the feed's JSON).
    struct Record: Decodable {
        var icaoId: String?
        var obsTime: Double?
        var rawOb: String?
        var lat: Double?
        var lon: Double?
        var elev: Double?
        var name: String?
        var temp: Double?
        var dewp: Double?
        var wdir: Flexible?
        var wspd: Double?
        var wgst: Double?
        var visib: Flexible?
        var cover: String?
        var clouds: [Cloud]?
        var fltCat: String?
        var wxString: String?

        struct Cloud: Decodable {
            var cover: String?
            var base: Double?
            var type: String?
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            icaoId = try? c.decodeIfPresent(String.self, forKey: .icaoId)
            obsTime = try? c.decodeIfPresent(Double.self, forKey: .obsTime)
            rawOb = try? c.decodeIfPresent(String.self, forKey: .rawOb)
            lat = try? c.decodeIfPresent(Double.self, forKey: .lat)
            lon = try? c.decodeIfPresent(Double.self, forKey: .lon)
            elev = try? c.decodeIfPresent(Double.self, forKey: .elev)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            temp = try? c.decodeIfPresent(Double.self, forKey: .temp)
            dewp = try? c.decodeIfPresent(Double.self, forKey: .dewp)
            wdir = try? c.decodeIfPresent(Flexible.self, forKey: .wdir)
            wspd = try? c.decodeIfPresent(Double.self, forKey: .wspd)
            wgst = try? c.decodeIfPresent(Double.self, forKey: .wgst)
            visib = try? c.decodeIfPresent(Flexible.self, forKey: .visib)
            cover = try? c.decodeIfPresent(String.self, forKey: .cover)
            clouds = try? c.decodeIfPresent([Cloud].self, forKey: .clouds)
            fltCat = try? c.decodeIfPresent(String.self, forKey: .fltCat)
            wxString = try? c.decodeIfPresent(String.self, forKey: .wxString)
        }

        enum Keys: String, CodingKey {
            case icaoId, obsTime, rawOb, lat, lon, elev, name, temp, dewp, wdir, wspd, wgst, visib, cover, clouds, fltCat, wxString
        }
    }

    /// A JSON value that is a number in one report and a string ("VRB", "10+") in another.
    enum Flexible: Decodable {
        case number(Double)
        case text(String)

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .number(d) } else { self = .text(try c.decode(String.self)) }
        }

        /// The numeric value, ignoring a trailing "+"; nil for words such as "VRB".
        var number: Double? {
            switch self {
            case .number(let d): d
            case .text(let s): Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "+ ")))
            }
        }

        var isCapped: Bool {
            if case .text(let s) = self { return s.hasSuffix("+") }
            return false
        }
    }

    /// Decodes the JSON array. An empty body or empty array gives no records.
    static func records(from data: Data) throws -> [Record] {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [] }
        do { return try JSONDecoder().decode([Record].self, from: data) } catch {
            throw SourceError.decoding("aviationweather.gov METAR JSON: \(error)")
        }
    }

    /// Reports for every record with an id, a position and an observation time, nearest to `origin` first.
    /// `tafs` maps station id to raw TAF text (a station without one has `rawTAF == nil`).
    public static func reports(from data: Data, origin: Coordinate, tafs: [String: String] = [:]) throws -> [StationReport] {
        try records(from: data).compactMap { report(from: $0, origin: origin, taf: tafs[$0.icaoId ?? ""]) }
            .sorted { $0.distanceKm < $1.distanceKm }
    }

    static func report(from r: Record, origin: Coordinate, taf: String?) -> StationReport? {
        guard let id = r.icaoId, !id.isEmpty, let lat = r.lat, let lon = r.lon, let obs = r.obsTime else { return nil }
        let time = Date(timeIntervalSince1970: obs)
        let raw = r.rawOb ?? ""
        let parsed = METARParser.parse(raw)
        let coordinate = Coordinate(latitude: lat, longitude: lon)

        // Cloud layers: the feed's list, with CB/TCU taken from the raw report's matching group.
        var layers: [CloudLayer] = (r.clouds ?? []).compactMap { c in
            guard let coverText = c.cover, let cover = cover(coverText) else { return nil }
            let base = c.base.map { $0 * METARParser.feetToM }
            let type = c.type ?? parsed.cloudLayers.first { $0.cover == cover && abs(($0.baseM ?? -1) - (base ?? -2)) < 1 }?.type
            return CloudLayer(cover: cover, baseM: base, type: type)
        }
        var hasSky = !layers.isEmpty
        if layers.isEmpty, let coverText = r.cover, let c = cover(coverText) {
            layers = [CloudLayer(cover: c, baseM: nil)]
            hasSky = true
        }

        var visKm = r.visib?.number.map { $0 * METARParser.statuteMileKm }
        if r.visib == nil { visKm = parsed.visibilityKm }  // the feed omits `visib` for "NDV" and some metre groups
        if r.visib?.isCapped == true, let rawKm = parsed.visibilityKm, rawKm >= (visKm ?? 0) { visKm = rawKm }

        var dir: Double?
        if let w = r.wdir, case .number(let d) = w { dir = d }
        let weather = r.wxString.map { $0.split(separator: " ").map(String.init) } ?? parsed.weather

        let conditions = ObservedSky.conditions(
            time: time, tempC: r.temp, dewpointC: r.dewp, windDirDeg: dir,
            windMs: r.wspd.map { $0 * METARParser.knotsToMs }, gustMs: r.wgst.map { $0 * METARParser.knotsToMs },
            visibilityKm: visKm, layers: layers, hasSkyGroup: hasSky)
        return StationReport(
            stationID: id, stationName: r.name, coordinate: coordinate, elevationM: r.elev,
            distanceKm: origin.distance(to: coordinate) / 1000,
            isMilitary: MilitaryStations.isMilitary(icaoID: id, name: r.name), observedAt: time, rawMETAR: raw, rawTAF: taf,
            observation: WeatherObservation(time: time, stationName: r.name, conditions: conditions),
            cloudLayers: layers, weather: weather, flightCategory: r.fltCat)
    }

    private static func cover(_ text: String) -> CloudLayer.Cover? {
        switch text.uppercased() {
        case "SKC": .skc
        case "CLR", "NCD": .clr
        case "NSC": .nsc
        case "FEW": .few
        case "SCT": .sct
        case "BKN": .bkn
        case "OVC": .ovc
        case "VV": .vv
        default: nil
        }
    }

    /// Splits `format=raw` TAF text into one text per station. A report starts on a line beginning with `TAF`;
    /// indented lines continue it. The station id is the token after `TAF` (and `AMD`/`COR`). First report per id wins.
    public static func tafs(fromRaw text: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: [String] = []
        func flush() {
            guard let first = current.first else { return }
            let tokens = first.split(separator: " ").map(String.init)
            if let id = tokens.dropFirst().first(where: { $0 != "AMD" && $0 != "COR" }), result[id] == nil {
                result[id] = current.joined(separator: "\n")
            }
            current = []
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmedTrailing = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if trimmedTrailing.isEmpty { continue }
            if trimmedTrailing.hasPrefix("TAF") {
                flush()
                current = [trimmedTrailing]
            } else if !current.isEmpty {
                current.append("  " + trimmedTrailing.trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        return result
    }
}
