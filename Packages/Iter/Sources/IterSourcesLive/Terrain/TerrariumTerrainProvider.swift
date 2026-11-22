import Foundation
import IterModel
import IterSources

/// Elevation and on-device horizon from Terrarium PNG tiles (AWS Open Data, `Terrarium.url(for:)`).
///
/// - `elevation(at:)`: bilinear at z12 (about 30 m pixels at mid latitudes) from the one tile containing the point.
///   Fixture check: Whitney 4412.95 m, Swiss Alps 2106.75 m (EPQS, 1 m DEM, says 4416.23 m at Whitney: a z12 pixel smooths a summit).
/// - `horizon(at:azimuthStep:)`: `HorizonComputer` over z12 tiles within 6 km of the point and z10 tiles (about 150 m
///   pixels) out to 40 km. At mid latitudes that is about 4 to 9 tiles of each zoom; the zoom is lowered one level at a
///   time when a box would need more than 16 tiles (high latitudes, where tiles are narrow on the ground).
///   Tiles are fetched with at most `descriptor.policy.maxConcurrent` requests in flight.
///
/// A tile that does not exist (HTTP 403 or 404) is missing: rays stop where data stops and `provenance.model` says how
/// many tiles were unavailable. If no tile at all can be had the call throws (the first transport error, else `.outsideCoverage`).
///
/// Raw PNG bytes go through the optional `blobCache` (key per tile, kept up to the descriptor's TTL); decoded tiles live in
/// an in-memory LRU of `memoryTiles` tiles (about 200 KB each).
public actor TerrariumTerrainProvider: TerrainProvider {
    public nonisolated let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock
    private let decoder: any RGBImageDecoding
    private let blobCache: (any BlobCaching)?
    private let memoryTiles: Int
    private let computer: HorizonComputer

    private var lru: [TileCoordinate: TerrariumTile] = [:]
    private var lruOrder: [TileCoordinate] = []
    private var knownMissing: Set<TileCoordinate> = []

    /// Radius around the observer served from the high-zoom tiles, metres.
    public static let nearRadiusM = 6_000.0
    public static let nearZoom = 12
    public static let farZoom = 10
    static let maxTilesPerBox = 16

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.terrariumTiles,
                decoder: any RGBImageDecoding = ImageIOPNGDecoder(), blobCache: (any BlobCaching)? = nil,
                memoryTiles: Int = 48, observerHeightM: Double = 2, maxDistanceM: Double = 40_000) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
        self.decoder = decoder
        self.blobCache = blobCache
        self.memoryTiles = max(1, memoryTiles)
        self.computer = HorizonComputer(observerHeightM: observerHeightM, maxDistanceM: maxDistanceM)
    }

    // MARK: TerrainProvider

    public func elevation(at coordinate: Coordinate) async throws -> Sourced<Double> {
        try validate(coordinate)
        let position = Terrarium.position(latitude: coordinate.latitude, longitude: coordinate.longitude, zoom: Self.nearZoom)
        switch try await load(position.tile) {
        case .tile(let tile):
            let metres = tile.bilinearElevation(pixelX: position.pixelX, pixelY: position.pixelY)
            let provenance = descriptor.provenance(fetchedAt: clock.now, model: "Terrarium z\(Self.nearZoom), bilinear",
                                                   url: descriptor.termsURL)
            return Sourced(value: metres, provenance: provenance)
        case .missing: throw SourceError.outsideCoverage
        case .failed(let e): throw e
        }
    }

    public func horizon(at coordinate: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile> {
        try validate(coordinate)
        var computer = self.computer
        computer.azimuthStepDegrees = azimuthStep
        guard computer.azimuthCount != nil else {
            throw SourceError.invalidRequest("azimuth step \(azimuthStep) does not divide 360 degrees into a whole count")
        }
        let nearTiles = Self.tiles(around: coordinate, radiusM: Self.nearRadiusM, zoom: Self.nearZoom)
        let farTiles = Self.tiles(around: coordinate, radiusM: computer.maxDistanceM, zoom: Self.farZoom)
        let wanted = Array(Set(nearTiles.tiles + farTiles.tiles))
        let outcomes = try await loadAll(wanted)

        var firstFailure: SourceError?
        var near: [TerrariumTile] = [], far: [TerrariumTile] = []
        var missing = 0
        for tile in nearTiles.tiles + farTiles.tiles {
            switch outcomes[tile] ?? .missing {
            case .tile(let t): if tile.zoom == nearTiles.zoom { near.append(t) } else { far.append(t) }
            case .missing: missing += 1
            case .failed(let e): missing += 1; firstFailure = firstFailure ?? e
            }
        }
        guard !near.isEmpty || !far.isEmpty else { throw firstFailure ?? SourceError.outsideCoverage }
        let nearMosaic = TerrariumMosaic(tiles: near), farMosaic = TerrariumMosaic(tiles: far)
        let sampler: (Coordinate) -> Double? = { c in
            nearMosaic?.bilinearElevation(latitude: c.latitude, longitude: c.longitude)
                ?? farMosaic?.bilinearElevation(latitude: c.latitude, longitude: c.longitude)
        }
        guard let ground = sampler(coordinate) else {
            throw firstFailure ?? SourceError.outsideCoverage
        }
        guard let result = computer.compute(from: coordinate, groundElevationM: ground, sampler: sampler) else {
            throw SourceError.invalidRequest("azimuth step \(azimuthStep)")
        }
        let total = nearTiles.tiles.count + farTiles.tiles.count
        var model = "Terrarium horizon: z\(nearTiles.zoom) tiles within \(Int(Self.nearRadiusM / 1000)) km, "
            + "z\(farTiles.zoom) tiles to \(Int(computer.maxDistanceM / 1000)) km, eye \(Self.plain(computer.observerHeightM)) m, "
            + "refraction k \(Self.plain(computer.refraction)); tiles \(total - missing) of \(total)"
        if missing > 0 { model += "; coverage reduced: \(missing) tiles unavailable" }
        if result.azimuthsWithoutData > 0 {
            model += "; \(result.azimuthsWithoutData) azimuths had no terrain data (level horizon used)"
        }
        let provenance = descriptor.provenance(fetchedAt: clock.now, model: model, url: descriptor.termsURL)
        return Sourced(value: result.profile, provenance: provenance)
    }

    // MARK: Tiles

    /// The tiles of one zoom that cover a box of `radiusM` around a point, lowering the zoom while there are more than 16.
    static func tiles(around c: Coordinate, radiusM: Double, zoom startZoom: Int) -> (zoom: Int, tiles: [TileCoordinate]) {
        let dLat = radiusM / 111_195
        let latRef = min(85, abs(c.latitude) + dLat)
        let dLon = radiusM / (111_195 * cos(latRef * .pi / 180))
        var zoom = startZoom
        while true {
            let sw = Terrarium.position(latitude: c.latitude - dLat, longitude: c.longitude - dLon, zoom: zoom).tile
            let ne = Terrarium.position(latitude: c.latitude + dLat, longitude: c.longitude + dLon, zoom: zoom).tile
            let n = 1 << zoom
            let west = Terrarium.position(latitude: c.latitude, longitude: c.longitude - dLon, zoom: zoom)
            let east = Terrarium.position(latitude: c.latitude, longitude: c.longitude + dLon, zoom: zoom)
            // Longitude may wrap across the antimeridian: walk from the west tile eastwards.
            let columns = ((east.tile.x - west.tile.x) % n + n) % n + 1
            let xs = (0..<min(columns, n)).map { (west.tile.x + $0) % n }
            let ys = Array(ne.y...max(ne.y, sw.y))
            if xs.count * ys.count <= maxTilesPerBox || zoom <= 4 {
                return (zoom, ys.flatMap { y in xs.map { TileCoordinate(zoom: zoom, x: $0, y: y) } })
            }
            zoom -= 1
        }
    }

    private enum TileOutcome: Sendable {
        case tile(TerrariumTile)
        case missing
        case failed(SourceError)
    }

    private func loadAll(_ coords: [TileCoordinate]) async throws -> [TileCoordinate: TileOutcome] {
        let limit = max(1, descriptor.policy.maxConcurrent)
        var results: [TileCoordinate: TileOutcome] = [:]
        try await withThrowingTaskGroup(of: (TileCoordinate, TileOutcome).self) { group in
            var next = 0
            while next < min(limit, coords.count) {
                let c = coords[next]; next += 1
                group.addTask { (c, try await self.load(c)) }
            }
            while let (c, outcome) = try await group.next() {
                results[c] = outcome
                if next < coords.count {
                    let n = coords[next]; next += 1
                    group.addTask { (n, try await self.load(n)) }
                }
            }
        }
        return results
    }

    private func load(_ coordinate: TileCoordinate) async throws -> TileOutcome {
        try Task.checkCancellation()
        if let hit = lru[coordinate] { touch(coordinate); return .tile(hit) }
        if knownMissing.contains(coordinate) { return .missing }
        let key = CacheKey(source: descriptor.id, kind: .elevation, cell: "z\(coordinate.zoom)/\(coordinate.x)/\(coordinate.y)")
        if let blobCache, let blob = await blobCache.blob(for: key, maxAge: descriptor.cacheTTL),
           let tile = try? TerrariumTile(coordinate: coordinate, png: blob.data, decoder: decoder) {
            remember(tile)
            return .tile(tile)
        }
        let body: Data
        do {
            body = try await http.send(.get(Terrarium.url(for: coordinate), from: descriptor)).body
        } catch {
            let e = SourceError.wrap(error)
            switch e {
            case .cancelled: throw e
            case .http(let status, _) where status == 404 || status == 403:
                knownMissing.insert(coordinate)
                return .missing
            default: return .failed(e)
            }
        }
        let tile: TerrariumTile
        do { tile = try TerrariumTile(coordinate: coordinate, png: body, decoder: decoder) } catch {
            return .failed(.decoding("Terrarium tile \(coordinate.zoom)/\(coordinate.x)/\(coordinate.y): \(error)"))
        }
        if let blobCache { await blobCache.storeBlob(body, for: key, licence: descriptor.licence) }
        remember(tile)
        return .tile(tile)
    }

    private func touch(_ c: TileCoordinate) {
        if let i = lruOrder.firstIndex(of: c) { lruOrder.remove(at: i) }
        lruOrder.append(c)
    }

    private func remember(_ tile: TerrariumTile) {
        lru[tile.coordinate] = tile
        touch(tile.coordinate)
        while lruOrder.count > memoryTiles {
            lru[lruOrder.removeFirst()] = nil
        }
    }

    private func validate(_ c: Coordinate) throws {
        guard c.latitude.isFinite, c.longitude.isFinite, abs(c.latitude) <= 90, abs(c.longitude) <= 360 else {
            throw SourceError.invalidRequest("coordinate out of range")
        }
        guard abs(c.latitude) <= Terrarium.maxLatitude else { throw SourceError.outsideCoverage }
    }

    private static func plain(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
