import Foundation
import Testing
import IterModel
import IterSourcesLive

// NOMADSMapping on the recorded GRIB2 fixtures. The expected numbers come from the ecCodes reference JSONs beside the
// fixtures (nearest value, and bilinear computed independently from the reference grid latitudes and longitudes), with the
// documented unit conversions and, for HRRR, the Lambert wind rotation computed separately in Python.

private let W = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let S = Coordinate(latitude: 46.5586, longitude: 8.5610)

private struct Expect {
    enum Point { case W, S }
    let file: String
    let model: NOMADSModel
    let point: Point
    let bilinear: Bool
    let cloudTotal, low, mid, high, visKm, tempC, dewC, rh, gust, wind, dir, precip: Double
    let precipSource: NOMADSSample.PrecipSource
    let smoke, aod: Double?

    var coordinate: Coordinate { point == .W ? W : S }
}

/// ecCodes gives no bilinear value on the Lambert grid: the HRRR bilinear numbers were computed independently in
/// latitude/longitude space, the code interpolates in the projection plane, so those agree only to about 1e-3.
private func close(_ a: Double?, _ b: Double?, _ what: String, _ tag: String, rel: Double = 2e-5) {
    guard let a, let b else { #expect(a == nil && b == nil, "\(tag) \(what): \(String(describing: a)) vs \(String(describing: b))"); return }
    #expect(abs(a - b) <= 1e-7 + rel * abs(b), "\(tag) \(what): \(a) vs \(b)")
}

private let expectations: [Expect] = [
        Expect(file: "hrrr-W-20261122t12z-f01", model: .hrrr, point: .W, bilinear: false, cloudTotal: 0, low: 0, mid: 0, high: 0, visKm: 50.5, tempC: -15.3935303, dewC: -23.5030731, rh: 39.0000008, gust: 12.9296282, wind: 8.36471685, dir: 227.706317, precip: 0, precipSource: .accumulation, smoke: 0.02, aod: 6e-05),
        Expect(file: "hrrr-W-20261122t12z-f01", model: .hrrr, point: .W, bilinear: true, cloudTotal: 0.00465734806, low: 0, mid: 0, high: 0.00465734806, visKm: 52.6757731, tempC: -14.6083611, dewC: -23.1961756, rh: 37.6307221, gust: 13.0595492, wind: 8.85004564, dir: 231.301821, precip: 0, precipSource: .accumulation, smoke: 0.02, aod: 6.36613716e-05),
        Expect(file: "hrrr-W-20261122t12z-f06", model: .hrrr, point: .W, bilinear: false, cloudTotal: 1, low: 0, mid: 0, high: 1, visKm: 58.8, tempC: -13.3989624, dewC: -24.4928802, rh: 33.6000008, gust: 17.0649958, wind: 11.2198781, dir: 228.281124, precip: 0, precipSource: .accumulation, smoke: 0.032, aod: 6.99999952e-05),
        Expect(file: "hrrr-W-20261122t12z-f06", model: .hrrr, point: .W, bilinear: true, cloudTotal: 1, low: 0, mid: 0.171518535, high: 1, visKm: 59.1093373, tempC: -12.8915695, dewC: -24.1939389, rh: 33.4541106, gust: 17.0287725, wind: 11.7204254, dir: 231.258012, precip: 0, precipSource: .accumulation, smoke: 0.0366363218, aod: 7.17769253e-05),
        Expect(file: "hrrr-W-20261122t12z-f12", model: .hrrr, point: .W, bilinear: false, cloudTotal: 1, low: 0, mid: 1, high: 0, visKm: 33.5, tempC: -14.3620972, dewC: -19.6609711, rh: 55.9, gust: 12.2706308, wind: 6.99993135, dir: 242.408238, precip: 0, precipSource: .accumulation, smoke: 0.24, aod: 0.0002),
        Expect(file: "hrrr-W-20261122t12z-f12", model: .hrrr, point: .W, bilinear: true, cloudTotal: 0.824092896, low: 0, mid: 0.824092896, high: 0, visKm: 36.5432123, tempC: -13.8000096, dewC: -19.8225923, rh: 53.1467497, gust: 12.6168912, wind: 7.86264427, dir: 246.292886, precip: 0, precipSource: .accumulation, smoke: 0.200744502, aod: 0.0002),
        Expect(file: "gfs-W-20261122t06z-f003", model: .gfs, point: .W, bilinear: false, cloudTotal: 1, low: 0.007, mid: 1, high: 1, visKm: 24.1350156, tempC: -5.15333984, dewC: -8.89681641, rh: 75.9, gust: 2.80291138, wind: 3.4240435, dir: 258.199804, precip: 0, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-W-20261122t06z-f003", model: .gfs, point: .W, bilinear: true, cloudTotal: 0.990914975, low: 0.0118545592, mid: 0.990286975, high: 0.983543946, visKm: 24.1350156, tempC: -4.42301934, dewC: -8.52030408, rh: 74.520411, gust: 2.22639474, wind: 2.43633387, dir: 256.529572, precip: 0, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-W-20261122t06z-f006", model: .gfs, point: .W, bilinear: false, cloudTotal: 0.579, low: 0, mid: 0.579, high: 0.05, visKm: 24.1347324, tempC: -7.13207031, dewC: -13.5519336, rh: 61.7, gust: 3.00672607, wind: 3.83479921, dir: 261.024887, precip: 0, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-W-20261122t06z-f006", model: .gfs, point: .W, bilinear: true, cloudTotal: 0.560264909, low: 0.0022266368, mid: 0.559839878, high: 0.0526516672, visKm: 24.1347324, tempC: -6.01322002, dewC: -12.1449792, rh: 63.4222367, gust: 2.46455351, wind: 2.54887774, dir: 257.940328, precip: 0, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-W-20261122t06z-f012", model: .gfs, point: .W, bilinear: false, cloudTotal: 1, low: 0, mid: 1, high: 1, visKm: 24.1353652, tempC: -1.71556641, dewC: -12.560625, rh: 43.5, gust: 3.51816225, wind: 2.48881055, dir: 213.845592, precip: 0, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-W-20261122t06z-f012", model: .gfs, point: .W, bilinear: true, cloudTotal: 1, low: 0, mid: 0.999628098, high: 1, visKm: 24.1353652, tempC: -1.07562885, dewC: -12.5015369, rh: 41.734505, gust: 2.72480729, wind: 1.73618096, dir: 209.95961, precip: 0, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-S-20261122t06z-f003", model: .gfs, point: .S, bilinear: false, cloudTotal: 1, low: 0.996, mid: 1, high: 1, visKm: 0.417414001, tempC: -3.75333984, dewC: -4.54681641, rh: 94.9000061, gust: 2.30291138, wind: 2.3004901, dir: 167.999518, precip: 0.59904, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-S-20261122t06z-f003", model: .gfs, point: .S, bilinear: true, cloudTotal: 1, low: 0.996377181, mid: 1, high: 1, visKm: 0.642747281, tempC: -3.20142877, dewC: -4.104747, rh: 94.0428339, gust: 2.76538882, wind: 2.58951984, dir: 165.99002, precip: 0.584235113, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-S-20261122t06z-f006", model: .gfs, point: .S, bilinear: false, cloudTotal: 1, low: 1, mid: 1, high: 0.97, visKm: 0.253931018, tempC: -2.48205078, dewC: -3.22195312, rh: 95, gust: 1.70672612, wind: 1.78417415, dir: 187.660858, precip: 0.60768, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-S-20261122t06z-f006", model: .gfs, point: .S, bilinear: true, cloudTotal: 1, low: 0.969374877, mid: 1, high: 0.982636192, visKm: 0.769399757, tempC: -1.95736969, dewC: -2.73744752, rh: 94.6699632, gust: 1.83284164, wind: 1.76096315, dir: 181.809754, precip: 0.623782453, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-S-20261122t06z-f012", model: .gfs, point: .S, bilinear: false, cloudTotal: 1, low: 0.705, mid: 1.00000003, high: 1, visKm: 0.1061646, tempC: -1.53554687, dewC: -2.290625, rh: 94.8, gust: 4.31816225, wind: 4.11040385, dir: 321.189895, precip: 0.64224, precipSource: .rate, smoke: nil, aod: nil),
        Expect(file: "gfs-S-20261122t06z-f012", model: .gfs, point: .S, bilinear: true, cloudTotal: 1, low: 0.789092512, mid: 0.985242325, high: 1, visKm: 1.80399104, tempC: -1.34537855, dewC: -1.98252145, rh: 95.6331149, gust: 4.24268545, wind: 3.71352112, dir: 323.208265, precip: 0.779526835, precipSource: .rate, smoke: nil, aod: nil),
]

@Suite struct NOMADSMappingTests {
    private func sample(_ e: Expect) throws -> NOMADSSample {
        let file = try GRIB2File(data: GRIB2Fixtures.data(e.file))
        return try #require(NOMADSMapping.sample(file, model: e.model, at: e.coordinate, interpolation: e.bilinear ? .bilinear : .nearest))
    }

    @Test func everyFixtureMatchesTheReferenceNumbers() throws {
        for e in expectations {
            let tag = "\(e.file) \(e.bilinear ? "bilinear" : "nearest")"
            let rel = e.model == .hrrr && e.bilinear ? 1e-3 : 2e-5
            let s = try sample(e), c = s.conditions
            close(c.cloudTotal, e.cloudTotal, "cloudTotal", tag, rel: rel)
            close(c.cloudLow, e.low, "cloudLow", tag, rel: rel)
            close(c.cloudMid, e.mid, "cloudMid", tag, rel: rel)
            close(c.cloudHigh, e.high, "cloudHigh", tag, rel: rel)
            close(c.visibilityKm, e.visKm, "visibilityKm", tag, rel: rel)
            close(c.tempC, e.tempC, "tempC", tag, rel: rel)
            close(c.dewpointC, e.dewC, "dewpointC", tag, rel: rel)
            close(c.rhPercent, e.rh, "rh", tag, rel: rel)
            close(c.gustMs, e.gust, "gust", tag, rel: rel)
            close(c.windMs, e.wind, "wind", tag, rel: rel)
            close(c.windDirDeg, e.dir, "windDir", tag, rel: rel)
            close(c.precipMm, e.precip, "precip", tag, rel: rel)
            #expect(s.precipSource == e.precipSource, "\(tag) precip source")
            close(c.smokeUgm3, e.smoke, "smoke", tag, rel: rel)
            close(c.aod550, e.aod, "aod550", tag, rel: rel)
            #expect(c.precipChance == nil && c.cloudBaseM == nil && c.pm25 == nil, "\(tag)")
        }
        #expect(expectations.count == 18)
    }

    @Test func validTimesAreTheFilesOwn() throws {
        let f01 = try GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f01"))
        let f12 = try GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f12"))
        let g = try GRIB2File(data: GRIB2Fixtures.data("gfs-W-20261122t06z-f006"))
        // 2026-11-22T12:00:00Z is 1795348800.
        #expect(NOMADSMapping.cycleTime(of: f01) == Date(timeIntervalSince1970: 1_795_348_800))
        #expect(NOMADSMapping.validTime(of: f01) == Date(timeIntervalSince1970: 1_795_348_800 + 3600))
        #expect(NOMADSMapping.validTime(of: f12) == Date(timeIntervalSince1970: 1_795_348_800 + 12 * 3600))
        #expect(NOMADSMapping.validTime(of: g) == Date(timeIntervalSince1970: 1_795_348_800 - 6 * 3600 + 6 * 3600))
        let s = try #require(NOMADSMapping.sample(f01, model: .hrrr, at: W))
        #expect(s.conditions.time == NOMADSMapping.validTime(of: f01))
    }

    /// HRRR's U/V are grid-relative: the rotation changes direction, not speed.
    @Test func hrrrWindIsRotatedToEarthRelative() throws {
        let file = try GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f01"))
        let u = try #require(file.field(parameter: .uWind, level: .height10m, forecastHour: 1, statistical: false))
        #expect(u.grid.vectorComponentsAreGridRelative)
        #expect(u.grid.resolutionAndComponentFlags == 8)
        // Raw nearest components (ecCodes): u 7.291025, v 4.099932 -> unrotated direction 240.6 degrees.
        let raw = (u: 7.291025, v: 4.099932)
        let unrotated = atan2(-raw.u, -raw.v) * 180 / .pi + 360
        #expect(abs(unrotated - 240.6) < 0.1)
        let s = try #require(NOMADSMapping.sample(file, model: .hrrr, at: W, interpolation: .nearest))
        #expect(abs((s.conditions.windMs ?? 0) - (raw.u * raw.u + raw.v * raw.v).squareRoot()) < 1e-4, "speed unchanged by rotation")
        let dir = try #require(s.conditions.windDirDeg)
        // The grid is turned by n * (lon - LoV) = sin(38.5 deg) * (-118.2923 + 97.5) = -12.94 degrees there.
        #expect(abs((dir - unrotated.truncatingRemainder(dividingBy: 360)) - (-12.94)) < 0.05, "rotated by \(dir - unrotated)")
        let angle = u.grid.gridRotation(atLongitude: W.longitude) * 180 / .pi
        #expect(abs(angle - (-12.9435)) < 1e-3)
        let e = u.grid.earthRelativeVector(u: raw.u, v: raw.v, atLongitude: W.longitude)
        #expect(abs(hypot(e.u, e.v) - hypot(raw.u, raw.v)) < 1e-9)
    }

    @Test func gfsWindIsNotRotated() throws {
        let file = try GRIB2File(data: GRIB2Fixtures.data("gfs-W-20261122t06z-f003"))
        let u = try #require(file.field(parameter: .uWind, level: .height10m, forecastHour: 3, statistical: false))
        #expect(!u.grid.vectorComponentsAreGridRelative || u.grid.gridRotation(atLongitude: W.longitude) == 0)
        let e = u.grid.earthRelativeVector(u: 1, v: 2, atLongitude: 100)
        #expect(e.u == 1 && e.v == 2)
    }

    /// Averaged (0-3 h, 0-6 h) cloud messages must never be used when the instantaneous one is gone.
    @Test func onlyInstantaneousCloudIsUsed() throws {
        let file = try GRIB2File(data: GRIB2Fixtures.data("gfs-S-20261122t06z-f006"))
        // Reference JSON, f006 at S nearest: low cloud instantaneous 100 %, averaged 93.8 %.
        let s = try #require(NOMADSMapping.sample(file, model: .gfs, at: S, interpolation: .nearest))
        #expect(s.conditions.cloudLow == 1.0)
        #expect(file.fields(parameter: .lowCloudCover).count == 2)
        #expect(file.fields(parameter: .lowCloudCover).filter(\.isStatistical).count == 1)
    }

    @Test func gfsFilesCarryNoSmokeAndHRRRDoes() throws {
        let g = try #require(NOMADSMapping.sample(GRIB2File(data: GRIB2Fixtures.data("gfs-W-20261122t06z-f003")), model: .gfs, at: W))
        #expect(g.conditions.smokeUgm3 == nil && g.conditions.aod550 == nil)
        let h = try #require(NOMADSMapping.sample(GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f12")), model: .hrrr, at: W))
        #expect(h.conditions.smokeUgm3 != nil && h.conditions.aod550 != nil)
        let row = try #require(NOMADSMapping.smokeRow(h.conditions))
        #expect(row.presentFields.sorted { $0.rawValue < $1.rawValue } == [.aod550, .smokeUgm3])
        #expect(NOMADSMapping.smokeRow(g.conditions) == nil)
    }

    @Test func distanceToNearestGridPoint() throws {
        let h = try #require(NOMADSMapping.sample(GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f01")), model: .hrrr, at: W))
        let g = try #require(NOMADSMapping.sample(GRIB2File(data: GRIB2Fixtures.data("gfs-W-20261122t06z-f003")), model: .gfs, at: W))
        // ecCodes reports 9.51 km to the nearest GFS point; HRRR cells are 3 km, so at most about 2.2 km.
        #expect(abs((g.distanceKm ?? 0) - 9.512085) < 0.05)
        #expect((h.distanceKm ?? 99) < 2.5)
    }

    @Test func outsideTheBoxGivesNoRow() throws {
        let file = try GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f01"))
        #expect(NOMADSMapping.sample(file, model: .hrrr, at: Coordinate(latitude: 10, longitude: 10)) == nil)
    }

    @Test func nowcastStepCarriesRainAndCloud() {
        let c = HourlyConditions(time: Date(timeIntervalSince1970: 0), cloudTotal: 0.4, precipMm: 1.2)
        let s = NOMADSMapping.nowcastStep(c)
        #expect(s.precipMmPerHour == 1.2 && s.cloudTotal == 0.4 && s.time == c.time)
    }
}
