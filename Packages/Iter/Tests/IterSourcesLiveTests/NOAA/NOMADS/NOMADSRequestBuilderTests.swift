import Foundation
import Testing
import IterModel
import IterSourcesLive

@Suite struct NOMADSRequestBuilderTests {
    private let hrrrW = "https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.20261122%2Fconus&file=hrrr.t12z.wrfsfcf01.grib2&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&var_MASSDEN=on&var_COLMD=on&var_AOTK=on&lev_8_m_above_ground=on&lev_entire_atmosphere_%28considered_as_a_single_layer%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=36.8&leftlon=-118.6&rightlon=-118.0&bottomlat=36.3"
    private let gfsW = "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f003&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=37&leftlon=-119&rightlon=-118&bottomlat=36"

    private let cycle12 = NOMADSTest.at(12)
    private let cycle06 = NOMADSTest.at(6)

    /// The recorded URL, except that the fixture used `-118.0` where numbers here drop the trailing zero.
    @Test func hrrrUrlMatchesTheRecordedForm() throws {
        let box = NOMADSBox(south: 36.3, north: 36.8, west: -118.6, east: -118.0)
        let url = try #require(NOMADSRequestBuilder.url(for: NOMADSFileRef(model: .hrrr, cycle: cycle12, forecastHour: 1), box: box))
        #expect(url.absoluteString == hrrrW.replacingOccurrences(of: "rightlon=-118.0", with: "rightlon=-118"))
    }

    @Test func gfsUrlMatchesTheRecordedForm() throws {
        let box = NOMADSBox(south: 36, north: 37, west: -119, east: -118)
        let url = try #require(NOMADSRequestBuilder.url(for: NOMADSFileRef(model: .gfs, cycle: cycle06, forecastHour: 3), box: box))
        #expect(url.absoluteString == gfsW)
    }

    @Test func gfsFileNamesUseThreeDigitsAndHrrrTwo() throws {
        let box = NOMADSBox(south: 0, north: 1, west: 0, east: 1)
        let g = try #require(NOMADSRequestBuilder.url(for: NOMADSFileRef(model: .gfs, cycle: cycle06, forecastHour: 384), box: box))
        #expect(g.absoluteString.contains("file=gfs.t06z.pgrb2.0p25.f384&"))
        let h = try #require(NOMADSRequestBuilder.url(for: NOMADSFileRef(model: .hrrr, cycle: NOMADSTest.at(23), forecastHour: 48), box: box))
        #expect(h.absoluteString.contains("dir=%2Fhrrr.20261122%2Fconus&file=hrrr.t23z.wrfsfcf48.grib2&"))
        // Zero bounds print as plain 0.
        #expect(h.absoluteString.hasSuffix("&toplat=1&leftlon=0&rightlon=1&bottomlat=0"))
    }

    @Test func hrrrRequestsCarrySmokeFieldsAndGfsDoesNot() throws {
        let box = NOMADSBox(south: 0, north: 1, west: 0, east: 1)
        let h = try #require(NOMADSRequestBuilder.url(for: NOMADSFileRef(model: .hrrr, cycle: cycle12, forecastHour: 2), box: box)).absoluteString
        let g = try #require(NOMADSRequestBuilder.url(for: NOMADSFileRef(model: .gfs, cycle: cycle12, forecastHour: 2), box: box)).absoluteString
        for v in ["var_MASSDEN=on", "var_COLMD=on", "var_AOTK=on", "lev_8_m_above_ground=on"] {
            #expect(h.contains(v) && !g.contains(v), "\(v)")
        }
    }

    // MARK: Tiles (NOMADSTiling.standard)

    @Test func standardBoxIsTheTilePlusAMargin() {
        let w = Coordinate(latitude: 36.5785, longitude: -118.2923)
        let h = NOMADSRequestBuilder.box(for: w, model: .hrrr)
        #expect(NOMADSTiling.standard.hrrr == .init(tile: 1, margin: 0.1) && NOMADSTiling.standard.gfs == .init(tile: 2, margin: 0.3))
        #expect(h == NOMADSRequestBuilder.box(for: w, model: .hrrr, tiling: .standard))
        #expect(h.id == "35.9,-119.1,37.1,-117.9")
        let g = NOMADSRequestBuilder.box(for: w, model: .gfs)
        #expect(g.id == "35.7,-120.3,38.3,-117.7")
        let s = Coordinate(latitude: 46.5586, longitude: 8.5610)
        #expect(NOMADSRequestBuilder.box(for: s, model: .gfs).id == "45.7,7.7,48.3,10.3")
        #expect(h.contains(w) && g.contains(w))
    }

    /// Every spot of an area shares a tile; the box holds every bilinear neighbour of every point in the tile.
    @Test func spotsOfAnAreaShareOneTile() {
        // Lone Pine and spots up to about 40 km around it: one HRRR tile and one GFS tile.
        let spots = [(36.6, -118.06), (36.58, -118.29), (36.9, -118.9), (36.35, -118.1), (36.99, -118.01)]
            .map { Coordinate(latitude: $0.0, longitude: $0.1) }
        #expect(Set(spots.map { NOMADSRequestBuilder.box(for: $0, model: .hrrr) }).count == 1)
        #expect(Set(spots.map { NOMADSRequestBuilder.box(for: $0, model: .gfs) }).count == 1)
        // Just across a tile edge is another tile.
        let a = NOMADSRequestBuilder.box(for: Coordinate(latitude: 36.99, longitude: -118.5), model: .hrrr)
        let b = NOMADSRequestBuilder.box(for: Coordinate(latitude: 37.01, longitude: -118.5), model: .hrrr)
        #expect(a != b)
        // The corner point of a tile finds a neighbour a grid spacing beyond it inside the box (HRRR 3 km, GFS 0.25 deg).
        let corner = Coordinate(latitude: 36.999, longitude: -118.001)
        let hb = NOMADSRequestBuilder.box(for: corner, model: .hrrr), gb = NOMADSRequestBuilder.box(for: corner, model: .gfs)
        #expect(hb.contains(Coordinate(latitude: 37.05, longitude: -117.95)) && gb.contains(Coordinate(latitude: 37.25, longitude: -117.75)))
        // HRRR tiles nest in GFS tiles, so a point's HRRR fallback to GFS never needs two GFS boxes.
        for lat in stride(from: 30.0, to: 50.0, by: 0.37) {
            for lon in stride(from: -125.0, to: -70.0, by: 0.53) {
                let c = Coordinate(latitude: lat, longitude: lon)
                let h = NOMADSRequestBuilder.box(for: c, model: .hrrr), g = NOMADSRequestBuilder.box(for: c, model: .gfs)
                #expect(g.contains(Coordinate(latitude: h.south + 0.1, longitude: h.west + 0.1)) && g.contains(Coordinate(latitude: h.north - 0.1, longitude: h.east - 0.1)))
            }
        }
    }

    @Test func tileSizeIsAParameter() {
        let w = Coordinate(latitude: 36.5785, longitude: -118.2923)
        let custom = NOMADSTiling(hrrr: .init(tile: 0.5, margin: 0.2), gfs: .init(tile: 4, margin: 0.5))
        #expect(NOMADSRequestBuilder.box(for: w, model: .hrrr, tiling: custom).id == "36.3,-118.7,37.2,-117.8")
        #expect(NOMADSRequestBuilder.box(for: w, model: .gfs, tiling: custom).id == "35.5,-120.5,40.5,-115.5")
    }

    /// The estimates quoted in NOMADSTiling's documentation.
    @Test func boxSizesMatchTheDocumentedEstimates() {
        let w = Coordinate(latitude: 36.5785, longitude: -118.2923)
        func area(_ b: NOMADSBox) -> Double { (b.north - b.south) * (b.east - b.west) }
        let h = area(NOMADSRequestBuilder.box(for: w, model: .hrrr)), g = area(NOMADSRequestBuilder.box(for: w, model: .gfs))
        #expect(abs(h * 18.9 - 27.2) < 0.2 && abs(g * 1.87 - 12.6) < 0.2)
        let hl = area(NOMADSRequestBuilder.box(for: w, model: .hrrr, tiling: .legacy)), gl = area(NOMADSRequestBuilder.box(for: w, model: .gfs, tiling: .legacy))
        #expect(abs(hl * 18.9 - 10.6) < 0.1 && abs(gl * 1.87 - 4.2) < 0.1)
    }

    @Test func legacyBoxIsTheCellPlusAMargin() {
        let w = Coordinate(latitude: 36.5785, longitude: -118.2923)
        let h = NOMADSRequestBuilder.box(for: w, model: .hrrr, tiling: .legacy)
        #expect((h.south, h.north, h.west, h.east) == (36.25, 37.0, -118.75, -118.0))
        #expect(h.id == "36.25,-118.75,37,-118")
        let g = NOMADSRequestBuilder.box(for: w, model: .gfs, tiling: .legacy)
        #expect((g.south, g.north, g.west, g.east) == (36.0, 37.5, -119.0, -117.5))
        let s = Coordinate(latitude: 46.5586, longitude: 8.5610)
        let gs = NOMADSRequestBuilder.box(for: s, model: .gfs, tiling: .legacy)
        #expect((gs.south, gs.north, gs.west, gs.east) == (46.0, 47.5, 8.0, 9.5))
        #expect(h.contains(w) && g.contains(w))
    }

    /// Every point in a cell shares one box, and the box holds the point's bilinear neighbours plus a margin.
    @Test func legacyPointsInOneCellShareABox() {
        let a = Coordinate(latitude: 36.51, longitude: -118.49), b = Coordinate(latitude: 36.74, longitude: -118.26)
        #expect(NOMADSRequestBuilder.box(for: a, model: .hrrr, tiling: .legacy) == NOMADSRequestBuilder.box(for: b, model: .hrrr, tiling: .legacy))
        let c = Coordinate(latitude: 36.76, longitude: -118.26)
        #expect(NOMADSRequestBuilder.box(for: a, model: .hrrr, tiling: .legacy) != NOMADSRequestBuilder.box(for: c, model: .hrrr, tiling: .legacy))
        // GFS cells are 0.5 degrees: 36.51 and 36.99 share, 37.01 does not.
        let g1 = NOMADSRequestBuilder.box(for: Coordinate(latitude: 36.51, longitude: -118.4), model: .gfs, tiling: .legacy)
        let g2 = NOMADSRequestBuilder.box(for: Coordinate(latitude: 36.99, longitude: -118.1), model: .gfs, tiling: .legacy)
        let g3 = NOMADSRequestBuilder.box(for: Coordinate(latitude: 37.01, longitude: -118.1), model: .gfs, tiling: .legacy)
        #expect(g1 == g2 && g1 != g3)
        // Neighbours on the 0.25 degree GFS grid and a 3 km HRRR cell are inside the box.
        let p = Coordinate(latitude: 36.99, longitude: -118.01)
        let gbox = NOMADSRequestBuilder.box(for: p, model: .gfs, tiling: .legacy)
        #expect(gbox.contains(Coordinate(latitude: 37.25, longitude: -117.75)) && gbox.contains(Coordinate(latitude: 36.75, longitude: -118.25)))
    }

    @Test func legacyBoxesAreClampedAtTheEdges() {
        let n = NOMADSRequestBuilder.box(for: Coordinate(latitude: 89.9, longitude: 179.9), model: .gfs, tiling: .legacy)
        #expect(n.north == 90 && n.east == 180)
        let s = NOMADSRequestBuilder.box(for: Coordinate(latitude: -89.9, longitude: -179.9), model: .gfs, tiling: .legacy)
        #expect(s.south == -90 && s.west == -180)
        // Longitudes are normalised first.
        let w = NOMADSRequestBuilder.box(for: Coordinate(latitude: 10, longitude: 241.7), model: .hrrr, tiling: .legacy)
        #expect((w.west, w.east) == (-118.75, -118.0))
        #expect(NOMADSBox(south: -0.0, north: 1, west: -0.00001, east: 1).id == "0,0,1,1")
    }
}
