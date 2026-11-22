import Foundation
import IterModel
import IterSources

/// NASA GIBS geostationary imagery as WMTS (EPSG:4326, 512 px PNG tiles) layer descriptors. No requests are made here.
///
/// Verified (SOURCES.md §2.3, probed 2026-11-22): the URL pattern
/// `https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/GOES-West_ABI_Band13_Clean_Infrared/default/{time}/2km/{TileMatrix}/{TileRow}/{TileCol}.png`
/// returned a 512x512 PNG for `2026-11-22T12:00:00Z` at `2km/4/4/5` (level 4 over the Sierra Nevada), while levels 3 and
/// 5 returned 404 for the same spot: only some matrices are populated, so `populatedZooms` is `[4]` for that layer.
/// Cadence 10 minutes, latency about 30 to 40 minutes.
///
/// Assumed, not fetched: the other layer ids and their tile matrix set names follow GIBS's naming pattern
/// (`GOES-East_ABI_Band13_Clean_Infrared`, `Himawari_AHI_Band13_Clean_Infrared`, `*_GeoColor`) and use `2km` for infrared and
/// `1km` for GeoColor, with unknown populated levels (`populatedZooms` nil). Probe each before shipping the layer picker.
/// Each layer's coverage is the usable part of the geostationary disc (`CoverageShapes`).
public struct GIBSImagery: ImageryProvider {
    public let descriptor: SourceDescriptor
    public let allLayers: [ImageryLayer]

    public static let step: Duration = .seconds(600)
    public static let latency: Duration = .seconds(2400)

    public init(descriptor: SourceDescriptor = SourceCatalogue.nasaGIBS) {
        self.descriptor = descriptor
        self.allLayers = Self.makeLayers(descriptor: descriptor)
    }

    /// The layers whose coverage contains the point, in catalogue order.
    public func layers(at coordinate: Coordinate) -> [ImageryLayer] {
        allLayers.filter { $0.coverage.contains(coordinate) }
    }

    /// The layer with an id (`gibs.goes-west.band13`, ...).
    public func layer(id: String) -> ImageryLayer? { allLayers.first { $0.id == id } }

    /// The time string for `{time}` right now.
    public static func currentTime(now: Date) -> String { GIBSTime.snap(now, step: step, latency: latency) }

    private static func makeLayers(descriptor d: SourceDescriptor) -> [ImageryLayer] {
        struct Spec {
            let id: String, title: String, gibs: String, kind: ImageryLayer.Kind, matrixSet: String
            let coverage: Coverage, populated: [Int]?, producer: String
        }
        let specs = [
            Spec(id: "gibs.goes-west.geocolor", title: "GOES-West GeoColor", gibs: "GOES-West_ABI_GeoColor",
                 kind: .satelliteGeoColor, matrixSet: "1km", coverage: CoverageShapes.goesWest, populated: nil, producer: "NOAA GOES-West"),
            Spec(id: "gibs.goes-west.band13", title: "GOES-West clean infrared (band 13)",
                 gibs: "GOES-West_ABI_Band13_Clean_Infrared", kind: .satelliteInfrared, matrixSet: "2km",
                 coverage: CoverageShapes.goesWest, populated: [4], producer: "NOAA GOES-West"),
            Spec(id: "gibs.goes-east.geocolor", title: "GOES-East GeoColor", gibs: "GOES-East_ABI_GeoColor",
                 kind: .satelliteGeoColor, matrixSet: "1km", coverage: CoverageShapes.goesEast, populated: nil, producer: "NOAA GOES-East"),
            Spec(id: "gibs.goes-east.band13", title: "GOES-East clean infrared (band 13)",
                 gibs: "GOES-East_ABI_Band13_Clean_Infrared", kind: .satelliteInfrared, matrixSet: "2km",
                 coverage: CoverageShapes.goesEast, populated: nil, producer: "NOAA GOES-East"),
            Spec(id: "gibs.himawari.geocolor", title: "Himawari GeoColor", gibs: "Himawari_AHI_GeoColor",
                 kind: .satelliteGeoColor, matrixSet: "1km", coverage: CoverageShapes.himawari, populated: nil, producer: "JMA Himawari"),
            Spec(id: "gibs.himawari.band13", title: "Himawari clean infrared (band 13)",
                 gibs: "Himawari_AHI_Band13_Clean_Infrared", kind: .satelliteInfrared, matrixSet: "2km",
                 coverage: CoverageShapes.himawari, populated: nil, producer: "JMA Himawari"),
        ]
        return specs.map { s in
            ImageryLayer(
                id: s.id, source: d.id, title: s.title, kind: s.kind, scheme: .wmtsGeographic,
                urlTemplate: "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/\(s.gibs)/default/{time}/\(s.matrixSet)/{TileMatrix}/{TileRow}/{TileCol}.png",
                minZoom: 0, maxZoom: s.matrixSet == "1km" ? 6 : 5, populatedZooms: s.populated, tileSize: 512,
                timeStep: step, typicalLatency: latency, coverage: s.coverage,
                attribution: "Imagery: \(s.producer) via NASA GIBS (NASA ESDIS)", licence: d.licence)
        }
    }
}
