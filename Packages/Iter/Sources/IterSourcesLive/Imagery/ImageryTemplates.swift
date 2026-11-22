import Foundation
import IterModel
import IterSources

/// Filling the URL templates of `ImageryLayer` and the two pieces of arithmetic that make them correct.
public enum ImageryURL {
    /// Replaces every `{name}` with its value. Returns nil if a placeholder is left unfilled or the result is not a URL.
    public static func fill(_ template: String, _ values: [String: String]) -> URL? {
        var s = template
        for (k, v) in values { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        if s.contains("{") { return nil }
        return URL(string: s)
    }

    /// A GIBS WMTS tile URL: `{time}`, `{TileMatrix}`, `{TileRow}`, `{TileCol}`.
    public static func gibsTile(_ layer: ImageryLayer, time: String, matrix: Int, row: Int, col: Int) -> URL? {
        fill(layer.urlTemplate, ["time": time, "TileMatrix": String(matrix), "TileRow": String(row), "TileCol": String(col)])
    }

    /// A slippy-map tile URL: `{z}`, `{x}`, `{y}`.
    public static func xyzTile(_ layer: ImageryLayer, z: Int, x: Int, y: Int) -> URL? {
        fill(layer.urlTemplate, ["z": String(z), "x": String(x), "y": String(y)])
    }

    /// A WMS GetMap URL for a region and pixel size (see `WMSBBox`).
    public static func wms(_ layer: ImageryLayer, region: GeoRegion, width: Int, height: Int) -> URL? {
        fill(layer.urlTemplate, ["bbox": WMSBBox.epsg4326(region), "width": String(width), "height": String(height)])
    }
}

/// WMS 1.3.0 bounding boxes.
public enum WMSBBox {
    /// `minLat,minLon,maxLat,maxLon` for `crs=EPSG:4326`.
    ///
    /// WMS 1.3.0 uses the axis order the CRS defines, and EPSG:4326 is latitude first. (WMS 1.1.1 or `CRS:84` would be
    /// `minLon,minLat,maxLon,maxLat`.) Writing it the 1.1.1 way returns an empty or wrong-place image with no error.
    /// Latitudes are clamped to -90...90; the antimeridian is not handled (a box crossing it needs two requests).
    public static func epsg4326(_ r: GeoRegion) -> String {
        let south = max(-90, r.center.latitude - r.latitudeDelta / 2), north = min(90, r.center.latitude + r.latitudeDelta / 2)
        let west = r.center.longitude - r.longitudeDelta / 2, east = r.center.longitude + r.longitudeDelta / 2
        return [south, west, north, east].map(number).joined(separator: ",")
    }

    /// Up to 6 decimals, trailing zeros dropped (`45`, `7.5`).
    static func number(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}

/// GIBS time dimension and tile-matrix arithmetic.
public enum GIBSTime {
    /// The newest time a time-dimensioned layer likely has: `now - latency`, floored to a multiple of `step` since the
    /// epoch (10-minute GOES and Himawari steps fall on :00, :10, ...).
    public static func snapDate(_ now: Date, step: Duration, latency: Duration) -> Date {
        let stepSeconds = max(1, step.timeInterval)
        let t = now.timeIntervalSince1970 - latency.timeInterval
        return Date(timeIntervalSince1970: (t / stepSeconds).rounded(.down) * stepSeconds)
    }

    /// `snapDate` formatted `yyyy-MM-dd'T'HH:mm:ss'Z'`, the form the GIBS `{time}` placeholder takes.
    public static func snap(_ now: Date, step: Duration, latency: Duration) -> String {
        SWPCUTC.iso(snapDate(now, step: step, latency: latency))
    }
}

/// The GIBS EPSG:4326 tile grid for the 2 km style matrix sets: level `L` has `2^(L+1)` columns and `2^L` rows of
/// `360 / 2^(L+1)` degrees, origin at 180 W, 90 N. Checked against the one verified tile
/// (`2km/4/4/5.png` over the Sierra Nevada at 36.6 N, 118.3 W: level 4 gives 11.25 degree tiles, row 4, column 5).
public enum GIBSTileGrid {
    public static func tile(for c: Coordinate, level: Int) -> (row: Int, col: Int) {
        let degrees = 360 / Double(1 << (level + 1))
        let rows = 1 << level, cols = 1 << (level + 1)
        let row = Int(((90 - c.latitude) / degrees).rounded(.down))
        var lon = (c.longitude + 180).truncatingRemainder(dividingBy: 360)
        if lon < 0 { lon += 360 }
        let col = Int((lon / degrees).rounded(.down))
        return (min(max(row, 0), rows - 1), min(max(col, 0), cols - 1))
    }
}
