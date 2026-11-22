import Foundation
import IterModel
import IterSources

/// A lat/lon box cut out of a model grid by the NOMADS filter. Boxes are snapped to a cell of the model's coarse grid,
/// so every point in the cell shares one box (one request, one cache entry).
public struct NOMADSBox: Sendable, Hashable, CustomStringConvertible {
    public let south: Double, north: Double, west: Double, east: Double

    public init(south: Double, north: Double, west: Double, east: Double) {
        self.south = south
        self.north = north
        self.west = west
        self.east = east
    }

    /// Cache cell id, e.g. "36.25,-118.75,37,-118" (south, west, north, east).
    public var id: String { "\(NOMADSRequestBuilder.number(south)),\(NOMADSRequestBuilder.number(west)),\(NOMADSRequestBuilder.number(north)),\(NOMADSRequestBuilder.number(east))" }
    public var description: String { id }

    public func contains(_ c: Coordinate) -> Bool {
        c.latitude >= south && c.latitude <= north && c.longitude >= west && c.longitude <= east
    }
}

/// Builds NOMADS GRIB-filter URLs in exactly the form recorded in Fixtures/GRIB2/README.md. Pure.
public enum NOMADSRequestBuilder {
    static let host = "https://nomads.ncep.noaa.gov/cgi-bin/"

    /// The variables and levels requested, in the recorded order. HRRR adds smoke (MASSDEN), column smoke (COLMD) and
    /// aerosol optical thickness (AOTK) so the smoke provider needs no extra request.
    static let hrrrVariables = ["LCDC", "MCDC", "HCDC", "TCDC", "VIS", "TMP", "DPT", "RH", "UGRD", "VGRD", "GUST", "APCP", "PRATE",
                                "MASSDEN", "COLMD", "AOTK"]
    static let gfsVariables = ["LCDC", "MCDC", "HCDC", "TCDC", "VIS", "TMP", "DPT", "RH", "UGRD", "VGRD", "GUST", "APCP", "PRATE"]
    static let hrrrLevels = ["8_m_above_ground", "entire_atmosphere_%28considered_as_a_single_layer%29", "low_cloud_layer",
                             "middle_cloud_layer", "high_cloud_layer", "entire_atmosphere", "surface", "2_m_above_ground",
                             "10_m_above_ground"]
    static let gfsLevels = ["low_cloud_layer", "middle_cloud_layer", "high_cloud_layer", "entire_atmosphere", "surface",
                            "2_m_above_ground", "10_m_above_ground"]

    /// Cell size and margin in degrees: HRRR 0.25 and 0.25, GFS 0.5 and 0.5.
    static func cell(_ model: NOMADSModel) -> Double { model == .hrrr ? 0.25 : 0.5 }
    static func margin(_ model: NOMADSModel) -> Double { model == .hrrr ? 0.25 : 0.5 }

    /// The box for a point: its cell plus a margin on every side, so it holds the bilinear neighbours of every point in
    /// the cell. About 0.75 degrees square for HRRR (about 12 KB, 17 messages) and 1.5 for GFS (about 5 KB).
    /// Latitudes are clamped to ±90 and longitudes to ±180; near the antimeridian the box is cut at the edge, where a
    /// bilinear read can come back empty (that field is then nil).
    public static func box(for c: Coordinate, model: NOMADSModel) -> NOMADSBox {
        let size = cell(model), pad = margin(model)
        var lon = c.longitude
        lon = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
        let lat0 = (min(max(c.latitude, -90), 90) / size).rounded(.down) * size
        let lon0 = (lon / size).rounded(.down) * size
        return NOMADSBox(south: max(-90, lat0 - pad), north: min(90, lat0 + size + pad),
                         west: max(-180, lon0 - pad), east: min(180, lon0 + size + pad))
    }

    /// The filter URL for one file and box.
    public static func url(for ref: NOMADSFileRef, box: NOMADSBox) -> URL? {
        let script: String, dir: String, file: String, vars: [String], levels: [String]
        let hh = String(format: "%02d", ref.cycleHourUTC)
        switch ref.model {
        case .hrrr:
            script = "filter_hrrr_2d.pl"
            dir = "%2Fhrrr.\(ref.dateStamp)%2Fconus"
            file = "hrrr.t\(hh)z.wrfsfcf\(String(format: "%02d", ref.forecastHour)).grib2"
            vars = hrrrVariables
            levels = hrrrLevels
        case .gfs:
            script = "filter_gfs_0p25.pl"
            dir = "%2Fgfs.\(ref.dateStamp)%2F\(hh)%2Fatmos"
            file = "gfs.t\(hh)z.pgrb2.0p25.f\(String(format: "%03d", ref.forecastHour))"
            vars = gfsVariables
            levels = gfsLevels
        }
        var q = "dir=\(dir)&file=\(file)"
        q += vars.map { "&var_\($0)=on" }.joined()
        q += levels.map { "&lev_\($0)=on" }.joined()
        q += "&subregion=&toplat=\(number(box.north))&leftlon=\(number(box.west))&rightlon=\(number(box.east))&bottomlat=\(number(box.south))"
        return URL(string: host + script + "?" + q)
    }

    /// 36.8, -118.6, 37 (no trailing zeros, never "-0").
    static func number(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}
