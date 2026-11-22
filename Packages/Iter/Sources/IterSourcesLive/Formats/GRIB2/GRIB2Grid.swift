import Foundation

// Section 3: grid definition (templates 3.0 regular lat/lon and 3.30 Lambert conformal) and geolocation.

public struct GRIB2ScanningMode: Sendable, Equatable {
    public let rawValue: Int
    /// Bit 1: points scan in the -i direction (east to west).
    public var iNegative: Bool { rawValue & 0x80 != 0 }
    /// Bit 2: points scan in the +j direction (south to north).
    public var jPositive: Bool { rawValue & 0x40 != 0 }
    /// Bit 3: adjacent points in the j direction are consecutive (column-major).
    public var jConsecutive: Bool { rawValue & 0x20 != 0 }
}

public struct GRIB2Grid: Sendable, Equatable {
    public struct LatLon: Sendable, Equatable {
        /// Degrees; longitudes as stored (0...360 for GFS).
        public let la1, lo1, la2, lo2: Double
        /// Increments in degrees, always positive; the scanning mode gives the direction.
        public let di, dj: Double
    }

    public struct Lambert: Sendable, Equatable {
        public let la1, lo1, laD, loV: Double  // degrees
        public let dx, dy: Double  // metres
        public let latin1, latin2: Double  // degrees
        public let southPoleLat, southPoleLon: Double
        public let projectionCentreFlag: Int
        // Snyder's cone constants on a sphere of the grid's radius, and the first point's projected position.
        fileprivate let n, f, rho0, x1, y1: Double
    }

    public enum Projection: Sendable, Equatable { case latLon(LatLon), lambertConformal(Lambert) }

    public let templateNumber: Int
    /// Section 3 "resolution and component flags" (octet 55 of template 3.0, octet 47 of template 3.30).
    public let resolutionAndComponentFlags: Int
    public let nx: Int
    public let ny: Int
    public let scanning: GRIB2ScanningMode
    /// Code table 3.2 earth shape and the sphere radius in metres used for projection (major axis for oblate shapes).
    public let earthShape: Int
    public let earthRadius: Double
    public let projection: Projection

    /// Flag bit 5 (0x08): vector components (u, v) are relative to the grid's x and y axes, not to east and north.
    public var vectorComponentsAreGridRelative: Bool { resolutionAndComponentFlags & 0x08 != 0 }

    /// The angle in radians by which the grid's x axis is turned counter-clockwise from true east at a longitude:
    /// n · (lon − LoV) for a Lambert conformal grid (n the cone constant), 0 for a regular lat/lon grid.
    public func gridRotation(atLongitude lon: Double) -> Double {
        guard case .lambertConformal(let g) = projection else { return 0 }
        var d = lon - g.loV
        d -= 360 * (d / 360).rounded(.down)
        if d > 180 { d -= 360 }
        return g.coneConstant * d * .pi / 180
    }

    /// Turns a (u, v) pair read from this grid into eastward and northward components. When the grid's flags say the
    /// components are already earth-relative (or the grid is regular lat/lon) the pair is returned unchanged.
    public func earthRelativeVector(u: Double, v: Double, atLongitude lon: Double) -> (u: Double, v: Double) {
        guard vectorComponentsAreGridRelative else { return (u, v) }
        let a = gridRotation(atLongitude: lon)
        guard a != 0 else { return (u, v) }
        return (u * cos(a) + v * sin(a), -u * sin(a) + v * cos(a))
    }

    public var pointCount: Int { nx * ny }  // nx, ny are validated so the product cannot overflow

    init(section s: GRIB2Section) throws(GRIB2Error) {
        let template = try s.int(13, 2)
        guard template == 0 || template == 30 else { throw .unsupportedGridTemplate(template) }
        templateNumber = template
        resolutionAndComponentFlags = try s.int(template == 0 ? 55 : 47, 1)
        earthShape = try s.int(15, 1)
        let radiusScale = try s.int(16, 1)
        let radiusScaled = try s.int(17, 4)
        let majorScale = try s.int(21, 1)
        let majorScaled = try s.int(22, 4)
        switch earthShape {
        case 0: earthRadius = 6_367_470
        case 1: earthRadius = Double(radiusScaled) / pow(10, Double(radiusScale))
        case 2: earthRadius = 6_378_160
        case 3: earthRadius = Double(majorScaled) / pow(10, Double(majorScale)) * 1000
        case 4, 5: earthRadius = 6_378_137
        case 6: earthRadius = 6_371_229
        case 7: earthRadius = Double(majorScaled) / pow(10, Double(majorScale))
        case 8: earthRadius = 6_371_200
        default: earthRadius = 6_378_137
        }
        guard earthRadius.isFinite, earthRadius > 1000 else { throw .invalidGrid("earth radius") }
        nx = try s.int(31, 4)
        ny = try s.int(35, 4)
        guard nx >= 1, ny >= 1, nx <= GRIB2SimplePacking.maxPoints, ny <= GRIB2SimplePacking.maxPoints,
            nx * ny <= GRIB2SimplePacking.maxPoints
        else { throw .invalidGrid("grid size \(nx) x \(ny)") }
        guard try s.int(7, 4) == nx * ny else { throw .invalidGrid("point count does not match Nx * Ny") }

        if template == 0 {
            let basic = try s.int(39, 4), subdivisions = try s.int(43, 4)
            var unit = 1e-6
            if basic != 0 && basic != 0xFFFF_FFFF {
                guard subdivisions != 0, subdivisions != 0xFFFF_FFFF else { throw .invalidGrid("angle subdivisions") }
                unit = Double(basic) / Double(subdivisions)
            }
            let la1 = Double(try s.signed(47, 4)) * unit, lo1 = Double(try s.signed(51, 4)) * unit
            let la2 = Double(try s.signed(56, 4)) * unit, lo2 = Double(try s.signed(60, 4)) * unit
            let rawDi = try s.int(64, 4), rawDj = try s.int(68, 4)
            scanning = try Self.scanningMode(try s.int(72, 1))
            // Increments may be missing (all ones); derive them from the corner points then.
            let di = rawDi == 0xFFFF_FFFF ? abs(lo2 - lo1) / Double(max(nx - 1, 1)) : Double(rawDi) * unit
            let dj = rawDj == 0xFFFF_FFFF ? abs(la2 - la1) / Double(max(ny - 1, 1)) : Double(rawDj) * unit
            guard di > 0 || nx == 1, dj > 0 || ny == 1 else { throw .invalidGrid("zero increment") }
            projection = .latLon(LatLon(la1: la1, lo1: lo1, la2: la2, lo2: lo2, di: di, dj: dj))
        } else {
            let micro = 1e-6
            let la1 = Double(try s.signed(39, 4)) * micro, lo1 = Double(try s.signed(43, 4)) * micro
            let laD = Double(try s.signed(48, 4)) * micro, loV = Double(try s.signed(52, 4)) * micro
            let dx = Double(try s.int(56, 4)) / 1000, dy = Double(try s.int(60, 4)) / 1000
            let flag = try s.int(64, 1)
            scanning = try Self.scanningMode(try s.int(65, 1))
            let latin1 = Double(try s.signed(66, 4)) * micro, latin2 = Double(try s.signed(70, 4)) * micro
            let spLat = Double(try s.signed(74, 4)) * micro, spLon = Double(try s.signed(78, 4)) * micro
            guard dx > 0, dy > 0 else { throw .invalidGrid("zero Dx/Dy") }
            // Snyder, Map Projections: A Working Manual, eqs. 15-3, 15-2, 15-1a (sphere).
            let p1 = latin1 * .pi / 180, p2 = latin2 * .pi / 180
            guard abs(latin1) < 90, abs(latin2) < 90, cos(p1) > 1e-9, cos(p2) > 1e-9 else { throw .invalidGrid("standard parallels") }
            let t = { (p: Double) in tan(.pi / 4 + p / 2) }
            let n = abs(p1 - p2) < 1e-12 ? sin(p1) : log(cos(p1) / cos(p2)) / log(t(p2) / t(p1))
            guard n.isFinite, abs(n) > 1e-9 else { throw .invalidGrid("cone constant") }
            let f = cos(p1) * pow(t(p1), n) / n
            let rho0 = earthRadius * f / pow(t(laD * .pi / 180), n)
            var lam = Lambert(
                la1: la1, lo1: lo1, laD: laD, loV: loV, dx: dx, dy: dy, latin1: latin1, latin2: latin2,
                southPoleLat: spLat, southPoleLon: spLon, projectionCentreFlag: flag, n: n, f: f, rho0: rho0, x1: 0, y1: 0)
            guard let first = lam.forward(lat: la1, lon: lo1, radius: earthRadius) else { throw .invalidGrid("first point") }
            lam = Lambert(
                la1: la1, lo1: lo1, laD: laD, loV: loV, dx: dx, dy: dy, latin1: latin1, latin2: latin2,
                southPoleLat: spLat, southPoleLon: spLon, projectionCentreFlag: flag, n: n, f: f, rho0: rho0,
                x1: first.x, y1: first.y)
            projection = .lambertConformal(lam)
        }
    }

    private static func scanningMode(_ raw: Int) throws(GRIB2Error) -> GRIB2ScanningMode {
        guard raw & 0x1F == 0 else { throw .unsupportedScanningMode(raw) }  // alternating rows etc.
        return GRIB2ScanningMode(rawValue: raw)
    }

    // MARK: Index mapping

    /// Storage index to scan coordinates (si along the i direction, sj along the j direction).
    private func scanCoordinates(ofIndex k: Int) -> (si: Int, sj: Int)? {
        guard k >= 0, k < pointCount else { return nil }
        return scanning.jConsecutive ? (k / ny, k % ny) : (k % nx, k / nx)
    }

    private func index(si: Int, sj: Int) -> Int { scanning.jConsecutive ? si * ny + sj : sj * nx + si }

    /// Latitude and longitude (longitude in -180..<180) of a grid point, by storage index.
    public func coordinate(ofIndex k: Int) -> (latitude: Double, longitude: Double)? {
        guard let (si, sj) = scanCoordinates(ofIndex: k) else { return nil }
        let sx = scanning.iNegative ? -1.0 : 1.0, sy = scanning.jPositive ? 1.0 : -1.0
        switch projection {
        case .latLon(let g):
            return (g.la1 + Double(sj) * g.dj * sy, Self.normalise(g.lo1 + Double(si) * g.di * sx))
        case .lambertConformal(let g):
            return g.inverse(x: g.x1 + Double(si) * g.dx * sx, y: g.y1 + Double(sj) * g.dy * sy, radius: earthRadius)
        }
    }

    // MARK: Geolocation

    /// Fractional scan coordinates (i, j) of a point, unbounded; nil if the point cannot be projected.
    private func fractionalScan(lat: Double, lon: Double) -> (i: Double, j: Double)? {
        guard lat.isFinite, lon.isFinite, abs(lat) <= 90 else { return nil }
        let sx = scanning.iNegative ? -1.0 : 1.0, sy = scanning.jPositive ? 1.0 : -1.0
        switch projection {
        case .latLon(let g):
            var d = (lon - g.lo1) * sx
            d -= 360 * (d / 360).rounded(.down)
            if d > 360 - 1e-9 { d -= 360 }
            return (d / g.di, (lat - g.la1) / (g.dj * sy))
        case .lambertConformal(let g):
            guard let p = g.forward(lat: lat, lon: lon, radius: earthRadius) else { return nil }
            return ((p.x - g.x1) / (g.dx * sx), (p.y - g.y1) / (g.dy * sy))
        }
    }

    /// True for global regular lat/lon grids whose rows close on themselves.
    private var wrapsInI: Bool {
        if case .latLon(let g) = projection { return abs(Double(nx) * g.di - 360) < 1e-6 }
        return false
    }

    /// Storage index of the grid point nearest to the location, or nil if it lies more than half a cell outside the grid.
    public func nearestIndex(lat: Double, lon: Double) -> Int? {
        guard let f = fractionalScan(lat: lat, lon: lon), f.i.isFinite, f.j.isFinite else { return nil }
        var si = Int(exactly: f.i.rounded()) ?? -1, sj = Int(exactly: f.j.rounded()) ?? -1
        if wrapsInI, si >= 0 { si %= nx }
        guard si >= 0, si < nx, sj >= 0, sj < ny else { return nil }
        return index(si: si, sj: sj)
    }

    /// The four surrounding grid points (storage indices) and their bilinear weights, nil outside the grid.
    public func bilinearStencil(lat: Double, lon: Double) -> (indices: [Int], weights: [Double])? {
        guard let f = fractionalScan(lat: lat, lon: lon), f.i.isFinite, f.j.isFinite else { return nil }
        let eps = 1e-9
        let wrap = wrapsInI
        guard f.j >= -eps, f.j <= Double(ny - 1) + eps, f.i >= -eps, wrap || f.i <= Double(nx - 1) + eps else { return nil }
        let fi = max(0, f.i), fj = min(max(0, f.j), Double(ny - 1))
        var i0 = Int(fi.rounded(.down)), j0 = Int(fj.rounded(.down))
        var ti = fi - Double(i0), tj = fj - Double(j0)
        if !wrap, i0 >= nx - 1 { i0 = max(nx - 2, 0); ti = nx > 1 ? 1 : 0 }
        if j0 >= ny - 1 { j0 = max(ny - 2, 0); tj = ny > 1 ? 1 : 0 }
        i0 %= nx
        let i1 = wrap ? (i0 + 1) % nx : min(i0 + 1, nx - 1), j1 = min(j0 + 1, ny - 1)
        return (
            [index(si: i0, sj: j0), index(si: i1, sj: j0), index(si: i0, sj: j1), index(si: i1, sj: j1)],
            [(1 - ti) * (1 - tj), ti * (1 - tj), (1 - ti) * tj, ti * tj]
        )
    }

    fileprivate static func normalise(_ lon: Double) -> Double {
        var l = lon - 360 * (lon / 360).rounded(.down)  // 0..<360
        if l >= 180 { l -= 360 }
        return l
    }
}

// MARK: Lambert conformal on a sphere

extension GRIB2Grid.Lambert {
    /// The cone constant n (sin of the standard parallel for a tangent cone).
    public var coneConstant: Double { n }

    private static func toRadians(_ d: Double) -> Double { d * .pi / 180 }

    /// Projected (x, y) in metres from the projection origin.
    fileprivate func forward(lat: Double, lon: Double, radius r: Double) -> (x: Double, y: Double)? {
        let phi = Self.toRadians(lat)
        let tanTerm = tan(.pi / 4 + phi / 2)
        guard tanTerm > 0, tanTerm.isFinite else { return nil }
        let rho = r * f / pow(tanTerm, n)
        var dLon = lon - loV
        dLon -= 360 * (dLon / 360).rounded(.down)
        if dLon > 180 { dLon -= 360 }
        let theta = n * Self.toRadians(dLon)
        let x = rho * sin(theta), y = rho0 - rho * cos(theta)
        return x.isFinite && y.isFinite ? (x, y) : nil
    }

    fileprivate func inverse(x: Double, y: Double, radius r: Double) -> (latitude: Double, longitude: Double)? {
        let sign: Double = n < 0 ? -1 : 1
        let dy = rho0 - y
        let rho = sign * (x * x + dy * dy).squareRoot()
        guard rho != 0 else { return (n > 0 ? 90 : -90, GRIB2Grid.normalise(loV)) }
        let theta = atan2(sign * x, sign * dy)
        let phi = 2 * atan(pow(r * f / rho, 1 / n)) - .pi / 2
        let lon = loV + theta / n * 180 / .pi
        return phi.isFinite && lon.isFinite ? (phi * 180 / .pi, GRIB2Grid.normalise(lon)) : nil
    }
}
