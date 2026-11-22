import Foundation
import IterModel
import IterSources

/// Meteosat imagery from EUMETSAT's view WMS, as a layer descriptor. No requests are made here.
///
/// Verified (SOURCES.md §2.3): `layers=msg_fes:ir108`, `crs=EPSG:4326`, `bbox=45,7,48,10`, 256x256 PNG over the Alps. WMS 1.3.0
/// with EPSG:4326 takes the bbox as `minLat,minLon,maxLat,maxLon`: use `WMSBBox.epsg4326` / `ImageryURL.wms`. The request has no
/// time parameter, so it returns the latest image (the layer is refreshed about every 15 minutes). The licence for real-time
/// imagery in a sold app has not been read; the catalogue entry is off by default.
public struct EUMETSATImagery: ImageryProvider {
    public let descriptor: SourceDescriptor
    public let allLayers: [ImageryLayer]

    public init(descriptor: SourceDescriptor = SourceCatalogue.eumetsatView) {
        self.descriptor = descriptor
        self.allLayers = [
            ImageryLayer(
                id: "eumetsat.msg-fes.ir108", source: descriptor.id, title: "Meteosat infrared 10.8 um", kind: .satelliteInfrared,
                scheme: .wms,
                urlTemplate: "https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.3.0&request=GetMap&layers=msg_fes:ir108&styles=&crs=EPSG:4326&bbox={bbox}&width={width}&height={height}&format=image/png",
                minZoom: 0, maxZoom: 9, tileSize: 256, coverage: descriptor.coverage,
                attribution: "Imagery: EUMETSAT Meteosat", licence: descriptor.licence)
        ]
    }

    public func layers(at coordinate: Coordinate) -> [ImageryLayer] {
        allLayers.filter { $0.coverage.contains(coordinate) }
    }
}
