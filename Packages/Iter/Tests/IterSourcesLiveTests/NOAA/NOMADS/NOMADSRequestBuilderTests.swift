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

    @Test func boxIsTheCellPlusAMargin() {
        let w = Coordinate(latitude: 36.5785, longitude: -118.2923)
        let h = NOMADSRequestBuilder.box(for: w, model: .hrrr)
        #expect((h.south, h.north, h.west, h.east) == (36.25, 37.0, -118.75, -118.0))
        #expect(h.id == "36.25,-118.75,37,-118")
        let g = NOMADSRequestBuilder.box(for: w, model: .gfs)
        #expect((g.south, g.north, g.west, g.east) == (36.0, 37.5, -119.0, -117.5))
        let s = Coordinate(latitude: 46.5586, longitude: 8.5610)
        let gs = NOMADSRequestBuilder.box(for: s, model: .gfs)
        #expect((gs.south, gs.north, gs.west, gs.east) == (46.0, 47.5, 8.0, 9.5))
        #expect(h.contains(w) && g.contains(w))
    }

    /// Every point in a cell shares one box, and the box holds the point's bilinear neighbours plus a margin.
    @Test func pointsInOneCellShareABox() {
        let a = Coordinate(latitude: 36.51, longitude: -118.49), b = Coordinate(latitude: 36.74, longitude: -118.26)
        #expect(NOMADSRequestBuilder.box(for: a, model: .hrrr) == NOMADSRequestBuilder.box(for: b, model: .hrrr))
        let c = Coordinate(latitude: 36.76, longitude: -118.26)
        #expect(NOMADSRequestBuilder.box(for: a, model: .hrrr) != NOMADSRequestBuilder.box(for: c, model: .hrrr))
        // GFS cells are 0.5 degrees: 36.51 and 36.99 share, 37.01 does not.
        let g1 = NOMADSRequestBuilder.box(for: Coordinate(latitude: 36.51, longitude: -118.4), model: .gfs)
        let g2 = NOMADSRequestBuilder.box(for: Coordinate(latitude: 36.99, longitude: -118.1), model: .gfs)
        let g3 = NOMADSRequestBuilder.box(for: Coordinate(latitude: 37.01, longitude: -118.1), model: .gfs)
        #expect(g1 == g2 && g1 != g3)
        // Neighbours on the 0.25 degree GFS grid and a 3 km HRRR cell are inside the box.
        let p = Coordinate(latitude: 36.99, longitude: -118.01)
        let gbox = NOMADSRequestBuilder.box(for: p, model: .gfs)
        #expect(gbox.contains(Coordinate(latitude: 37.25, longitude: -117.75)) && gbox.contains(Coordinate(latitude: 36.75, longitude: -118.25)))
    }

    @Test func boxesAreClampedAtTheEdges() {
        let n = NOMADSRequestBuilder.box(for: Coordinate(latitude: 89.9, longitude: 179.9), model: .gfs)
        #expect(n.north == 90 && n.east == 180)
        let s = NOMADSRequestBuilder.box(for: Coordinate(latitude: -89.9, longitude: -179.9), model: .gfs)
        #expect(s.south == -90 && s.west == -180)
        // Longitudes are normalised first.
        let w = NOMADSRequestBuilder.box(for: Coordinate(latitude: 10, longitude: 241.7), model: .hrrr)
        #expect((w.west, w.east) == (-118.75, -118.0))
        #expect(NOMADSBox(south: -0.0, north: 1, west: -0.00001, east: 1).id == "0,0,1,1")
    }
}
