import Foundation

/// How NOMADS boxes are cut: each model's coordinates snap to a tile of `tile` degrees, and the box is the tile plus
/// `margin` degrees on every side. Every point in a tile (a whole area, a list of nearby spots) shares one download per
/// (model, cycle, forecast hour), and the margin is just big enough that bilinear neighbours of any point in the tile are
/// inside the box. The tile origin is a multiple of the tile size, and the GFS tile (2 degrees) is a multiple of the HRRR
/// tile (1 degree), so each HRRR tile lies inside exactly one GFS tile.
///
/// Bytes per box, scaled from the recorded fixtures (area scales the size: HRRR about 18.9 KB per square degree, from
/// the 0.75 degree fixture box of 10.6 KB; GFS about 1.9 KB per square degree, from the 1.5 degree box of 4.2 KB):
///
/// | geometry | HRRR box | HRRR bytes | GFS box | GFS bytes |
/// |---|---|---|---|---|
/// | `.legacy` (old per-cell) | 0.75 x 0.75 | about 10.6 KB | 1.5 x 1.5 | about 4.2 KB |
/// | `.standard` | 1.2 x 1.2 | about 27 KB | 2.6 x 2.6 | about 13 KB |
public struct NOMADSTiling: Sendable, Hashable {
    public struct Spec: Sendable, Hashable {
        /// Tile size in degrees (the snap grid).
        public var tile: Double
        /// Margin in degrees added on every side of the tile.
        public var margin: Double
        public init(tile: Double, margin: Double) {
            self.tile = tile
            self.margin = margin
        }
    }

    public var hrrr: Spec
    public var gfs: Spec

    public init(hrrr: Spec, gfs: Spec) {
        self.hrrr = hrrr
        self.gfs = gfs
    }

    /// HRRR 1 degree tiles with 0.1 margin (one 3 km spacing is at most 0.05 degrees), GFS 2 degree tiles with 0.3
    /// margin (one 0.25 degree spacing plus a little).
    public static let standard = NOMADSTiling(hrrr: Spec(tile: 1, margin: 0.1), gfs: Spec(tile: 2, margin: 0.3))

    /// The earlier geometry: HRRR 0.25 degree cells with 0.25 margin, GFS 0.5 with 0.5. Kept for tests and comparisons.
    public static let legacy = NOMADSTiling(hrrr: Spec(tile: 0.25, margin: 0.25), gfs: Spec(tile: 0.5, margin: 0.5))

    public func spec(_ model: NOMADSModel) -> Spec { model == .hrrr ? hrrr : gfs }
}
