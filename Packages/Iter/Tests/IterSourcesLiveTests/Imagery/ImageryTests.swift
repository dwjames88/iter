import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

@Suite("Imagery descriptors")
struct ImageryTests {
    static let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
    static let swiss = Coordinate(latitude: 46.5586, longitude: 8.5610)
    static let pacific = Coordinate(latitude: 0, longitude: -160)

    let gibs = GIBSImagery()
    let eumetsat = EUMETSATImagery()
    let iem = IEMRadarImagery()

    @Test func gibsLayersAtWhitneyAreTheTwoGOESSatellites() {
        #expect(gibs.layers(at: Self.whitney).map(\.id) == [
            "gibs.goes-west.geocolor", "gibs.goes-west.band13", "gibs.goes-east.geocolor", "gibs.goes-east.band13"])
    }

    @Test func gibsHasNothingOverTheAlps() {
        // Neither GOES disc nor Himawari reaches 8.5 E; Meteosat does (EUMETSAT).
        #expect(gibs.layers(at: Self.swiss).isEmpty)
        #expect(eumetsat.layers(at: Self.swiss).map(\.id) == ["eumetsat.msg-fes.ir108"])
        #expect(iem.layers(at: Self.swiss).isEmpty)
    }

    @Test func gibsOverThePacificIsGOESWestAndHimawari() {
        #expect(gibs.layers(at: Self.pacific).map(\.id) == [
            "gibs.goes-west.geocolor", "gibs.goes-west.band13", "gibs.himawari.geocolor", "gibs.himawari.band13"])
    }

    @Test func radarAndMeteosatCoverage() {
        #expect(iem.layers(at: Self.whitney).map(\.id) == ["iem.nexrad.n0q"])
        #expect(eumetsat.layers(at: Self.whitney).isEmpty)
        #expect(iem.layers(at: Self.pacific).isEmpty)
    }

    @Test func theVerifiedGIBSTileURL() throws {
        let layer = try #require(gibs.layer(id: "gibs.goes-west.band13"))
        let url = ImageryURL.gibsTile(layer, time: "2026-11-22T12:00:00Z", matrix: 4, row: 4, col: 5)
        #expect(url?.absoluteString == "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/GOES-West_ABI_Band13_Clean_Infrared/default/2026-11-22T12:00:00Z/2km/4/4/5.png")
        #expect(layer.scheme == .wmtsGeographic)
        #expect(layer.tileSize == 512)
        #expect(layer.populatedZooms == [4])
        #expect(layer.timeStep == .seconds(600))
        #expect(layer.kind == .satelliteInfrared)
        // The tile grid reproduces the verified row and column for the Sierra Nevada at level 4.
        #expect(GIBSTileGrid.tile(for: Self.whitney, level: 4) == (row: 4, col: 5))
    }

    @Test func tileGridClampsAndWraps() {
        #expect(GIBSTileGrid.tile(for: Coordinate(latitude: 90, longitude: -180), level: 3) == (row: 0, col: 0))
        #expect(GIBSTileGrid.tile(for: Coordinate(latitude: -90, longitude: 179.999), level: 3) == (row: 7, col: 15))
        #expect(GIBSTileGrid.tile(for: Coordinate(latitude: 0, longitude: 180), level: 3) == (row: 4, col: 0))
    }

    @Test func everyLayerCarriesAttributionAndTheDescriptorsLicence() {
        for layer in gibs.allLayers + eumetsat.allLayers + iem.allLayers {
            #expect(!layer.attribution.isEmpty)
            #expect(layer.id.hasPrefix(layer.source == .nasaGIBS ? "gibs." : layer.source == .eumetsatView ? "eumetsat." : "iem."))
        }
        #expect(gibs.allLayers.allSatisfy { $0.licence == SourceCatalogue.nasaGIBS.licence && $0.source == .nasaGIBS })
        #expect(eumetsat.allLayers.allSatisfy { $0.licence == SourceCatalogue.eumetsatView.licence && !$0.licence.mayStore })
        #expect(iem.allLayers.allSatisfy { $0.licence == SourceCatalogue.iemNEXRAD.licence })
        #expect(Set(gibs.allLayers.map(\.id)).count == gibs.allLayers.count)
    }

    @Test func gibsSnapsToTheNewestLikelyTime() {
        let now = w4ISODate("2026-11-22T13:47:30Z")
        #expect(GIBSTime.snap(now, step: .seconds(600), latency: .seconds(2400)) == "2026-11-22T13:00:00Z")
        #expect(GIBSTime.snap(now, step: .seconds(600), latency: .seconds(2100)) == "2026-11-22T13:10:00Z")
        #expect(GIBSTime.snapDate(now, step: .seconds(600), latency: .seconds(2100)) == w4ISODate("2026-11-22T13:10:00Z"))
        // Exactly on a step boundary stays there; one second earlier goes back a step.
        #expect(GIBSTime.snap(w4ISODate("2026-11-22T14:20:00Z"), step: .seconds(600), latency: .seconds(2400)) == "2026-11-22T13:40:00Z")
        #expect(GIBSTime.snap(w4ISODate("2026-11-22T14:19:59Z"), step: .seconds(600), latency: .seconds(2400)) == "2026-11-22T13:30:00Z")
        // Across midnight and a year end.
        #expect(GIBSTime.snap(w4ISODate("2027-01-01T00:10:00Z"), step: .seconds(600), latency: .seconds(2400)) == "2026-12-31T23:30:00Z")
        #expect(GIBSImagery.currentTime(now: now) == "2026-11-22T13:00:00Z")
    }

    @Test func eumetsatBBoxIsLatitudeFirst() throws {
        // The verified example: bbox=45,7,48,10 over the Alps.
        let alps = GeoRegion(center: Coordinate(latitude: 46.5, longitude: 8.5), latitudeDelta: 3, longitudeDelta: 3)
        #expect(WMSBBox.epsg4326(alps) == "45,7,48,10")
        let layer = try #require(eumetsat.allLayers.first)
        #expect(ImageryURL.wms(layer, region: alps, width: 256, height: 256)?.absoluteString
                == "https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.3.0&request=GetMap&layers=msg_fes:ir108&styles=&crs=EPSG:4326&bbox=45,7,48,10&width=256&height=256&format=image/png")
        let andes = GeoRegion(center: Coordinate(latitude: -33.5, longitude: -70.25), latitudeDelta: 2, longitudeDelta: 1.5)
        #expect(WMSBBox.epsg4326(andes) == "-34.5,-71,-32.5,-69.5")
        // Not square: the order is still south, west, north, east.
        let wide = GeoRegion(center: Coordinate(latitude: 10, longitude: 20), latitudeDelta: 4, longitudeDelta: 40)
        #expect(WMSBBox.epsg4326(wide) == "8,0,12,40")
        #expect(layer.scheme == .wms)
    }

    @Test func iemTileURLAndCadence() throws {
        let layer = try #require(iem.allLayers.first)
        #expect(ImageryURL.xyzTile(layer, z: 6, x: 10, y: 25)?.absoluteString
                == "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/6/10/25.png")
        #expect(layer.timeStep == .seconds(300))
        #expect(layer.scheme == .xyz && layer.tileSize == 256)
    }

    @Test func fillRefusesUnfilledPlaceholders() throws {
        let layer = try #require(iem.allLayers.first)
        #expect(ImageryURL.fill(layer.urlTemplate, ["z": "6", "x": "10"]) == nil)
        #expect(ImageryURL.fill("https://example.com/{a}/{a}", ["a": "1"])?.absoluteString == "https://example.com/1/1")
    }
}
