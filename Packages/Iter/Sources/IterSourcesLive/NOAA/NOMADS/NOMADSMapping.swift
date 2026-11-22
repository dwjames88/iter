import Foundation
import IterModel
import IterSources

/// One decoded NOMADS file read at a coordinate.
public struct NOMADSSample: Sendable, Hashable {
    public var conditions: HourlyConditions
    /// Distance from the coordinate to the nearest grid point, km.
    public var distanceKm: Double?
    /// Which message supplied `precipMm`.
    public var precipSource: PrecipSource

    public enum PrecipSource: String, Sendable, Hashable {
        /// A 1-hour accumulation (APCP) ending at the valid time.
        case accumulation
        /// The instantaneous rate (PRATE, kg/m²/s) × 3600 = mm/h.
        case rate
        case none
    }
}

/// `GRIB2File` to `HourlyConditions` at a coordinate. Pure: bytes in, value types out.
///
/// Field choices:
/// - Cloud layers (LCDC, MCDC, HCDC) and total (TCDC, entire atmosphere): the instantaneous message only
///   (`statistical: false`). The GFS filter output holds both an instantaneous and a 0-6 h averaged message for each; an
///   average describes a different time, so when only an average exists the field is nil, never the average.
/// - Precipitation: a 1-hour accumulation (APCP, product template 4.8, range exactly 1 h, ending at the valid time) when
///   the file has one, else the instantaneous PRATE × 3600 (mm/h). HRRR files carry the 1-hour accumulation (`0-1`,
///   `5-6`, `11-12`), so HRRR rows use APCP. GFS accumulates over 3 or 6 h buckets (and over 1 h only up to its first
///   hours), so GFS rows use PRATE × 3600 unless a 1-hour accumulation is there. A negative value is clamped to 0.
/// - Visibility: VIS at the surface, m to km. Temperature and dew point: 2 m, K to °C. Relative humidity: 2 m, %.
/// - Wind: 10 m UGRD/VGRD. HRRR's Lambert grid stores grid-relative components (resolution flag bit 5); they are
///   rotated to east/north first (angle n·(lon − LoV), see `GRIB2Grid.earthRelativeVector`), then speed is the vector
///   length and direction is meteorological (degrees the wind blows FROM). Calm air (speed 0) has no direction (nil).
/// - Gust: GUST at the surface, m/s.
/// - Smoke: HRRR MASSDEN at 8 m above ground, kg/m³ × 1e9 = µg/m³ (`smokeUgm3`). AOTK is HRRR's aerosol optical
///   thickness (an optical depth of the smoke-aerosol column, taken as `aod550`). Both are nil for GFS files, which do not
///   carry them. COLMD (column smoke) is requested but has no field in the row model.
/// - A value that cannot be read (outside the box, a missing grid point) stays nil, never 0.
public enum NOMADSMapping {
    /// The valid time of a file: that of its first instantaneous field (every instantaneous field of a filter file shares it).
    public static func validTime(of file: GRIB2File) -> Date? {
        file.fields.first { !$0.isStatistical }?.validTime
    }

    /// The reference (cycle) time of the file.
    public static func cycleTime(of file: GRIB2File) -> Date? { file.fields.first?.identification.referenceTime }

    /// One row for the file's valid time at `coordinate`; nil when the file has no instantaneous field or no field reads.
    public static func sample(_ file: GRIB2File, model: NOMADSModel, at coordinate: Coordinate,
                              interpolation: GRIB2Field.Interpolation = .bilinear) -> NOMADSSample? {
        guard let anchor = file.fields.first(where: { !$0.isStatistical }), let valid = anchor.validTime,
              let fh = anchor.forecastHour else { return nil }
        let lat = coordinate.latitude, lon = coordinate.longitude

        func instantaneous(_ p: GRIB2Parameter, _ level: GRIB2Level) -> GRIB2Field? {
            file.field(parameter: p, level: level, forecastHour: fh, statistical: false)
        }
        func read(_ p: GRIB2Parameter, _ level: GRIB2Level) -> Double? {
            instantaneous(p, level)?.value(atLat: lat, lon: lon, interpolation: interpolation)
        }
        func fraction(_ p: GRIB2Parameter, _ level: GRIB2Level) -> Double? {
            read(p, level).map { min(max($0 / 100, 0), 1) }
        }

        var c = HourlyConditions(time: valid)
        c.cloudTotal = fraction(.totalCloudCover, .entireAtmosphere)
        c.cloudLow = fraction(.lowCloudCover, .lowCloudLayer)
        c.cloudMid = fraction(.midCloudCover, .middleCloudLayer)
        c.cloudHigh = fraction(.highCloudCover, .highCloudLayer)
        c.visibilityKm = read(.visibility, .surface).map { max($0, 0) / 1000 }
        c.tempC = read(.temperature, .height2m).map { $0 - 273.15 }
        c.dewpointC = read(.dewPoint, .height2m).map { $0 - 273.15 }
        c.rhPercent = read(.relativeHumidity, .height2m).map { min(max($0, 0), 100) }
        c.gustMs = read(.windGust, .surface).map { max($0, 0) }

        if let uField = instantaneous(.uWind, .height10m), let vField = instantaneous(.vWind, .height10m),
           let u = uField.value(atLat: lat, lon: lon, interpolation: interpolation),
           let v = vField.value(atLat: lat, lon: lon, interpolation: interpolation) {
            let e = uField.grid.earthRelativeVector(u: u, v: v, atLongitude: lon)
            let speed = (e.u * e.u + e.v * e.v).squareRoot()
            c.windMs = speed
            if speed > 1e-9 {
                var dir = atan2(-e.u, -e.v) * 180 / .pi
                if dir < 0 { dir += 360 }
                if dir >= 360 { dir -= 360 }
                c.windDirDeg = dir
            }
        }

        var precipSource = NOMADSSample.PrecipSource.none
        let accumulation = file.fields(parameter: .totalPrecipitation).first { f in
            guard let s = f.product.statistical, s.isAccumulation, GRIB2Level.surface.matches(f.product.firstSurface),
                  let hours = s.rangeHours else { return false }
            return abs(hours - 1) < 1e-6 && abs(s.endOfInterval.timeIntervalSince(valid)) < 1
        }
        if let v = accumulation?.value(atLat: lat, lon: lon, interpolation: interpolation) {
            c.precipMm = max(v, 0)
            precipSource = .accumulation
        } else if let rate = read(.precipitationRate, .surface) {
            c.precipMm = max(rate, 0) * 3600
            precipSource = .rate
        }

        if model == .hrrr {
            c.smokeUgm3 = read(.massDensity, .height8m).map { max($0, 0) * 1e9 }
            c.aod550 = read(.aerosolOpticalThickness, .entireAtmosphereSingleLayer).map { max($0, 0) }
        }

        guard !c.presentFields.isEmpty else { return nil }
        let km = anchor.nearestIndex(lat: lat, lon: lon).flatMap { i -> Double? in
            guard let la = anchor.latitude(ofIndex: i), let lo = anchor.longitude(ofIndex: i) else { return nil }
            return coordinate.distance(to: Coordinate(latitude: la, longitude: lo)) / 1000
        }
        return NOMADSSample(conditions: c, distanceKm: km, precipSource: precipSource)
    }

    /// The smoke fields only (smokeUgm3, aod550); nil when neither is present.
    public static func smokeRow(_ c: HourlyConditions) -> HourlyConditions? {
        guard c.smokeUgm3 != nil || c.aod550 != nil else { return nil }
        return HourlyConditions(time: c.time, aod550: c.aod550, smokeUgm3: c.smokeUgm3)
    }

    public static func nowcastStep(_ c: HourlyConditions) -> NowcastStep {
        NowcastStep(time: c.time, precipMmPerHour: c.precipMm, cloudTotal: c.cloudTotal)
    }
}

/// Classification of NOMADS error responses.
public enum NOMADSErrors {
    /// NOMADS answers a running or missing file with 404 "Data file is not present", and a date it has not created yet
    /// with 403 "Request for Future Data" (an Akamai page). Both mean "not published yet". Any other status, and a 403
    /// without that text, stays as it is.
    public static func classify(_ error: SourceError, what: String) -> SourceError {
        guard case .http(let status, let excerpt) = error, let text = excerpt?.lowercased() else { return error }
        if status == 404, text.contains("not present") { return .notPublished(what) }
        if status == 403, text.contains("future data") { return .notPublished(what) }
        return error
    }

    /// A 200 body must be GRIB ("GRIB" magic); NOMADS returns HTML text for filter errors.
    public static func checkGRIB(_ data: Data, what: String) throws(SourceError) {
        guard data.count >= 4, data.prefix(4).elementsEqual("GRIB".utf8) else {
            let snippet = String(decoding: data.prefix(80), as: UTF8.self).filter { !$0.isNewline }
            throw .decoding("\(what): response is not GRIB (\(snippet))")
        }
    }
}
