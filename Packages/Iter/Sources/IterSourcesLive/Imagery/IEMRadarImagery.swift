import Foundation
import IterModel
import IterSources

/// NEXRAD composite radar (base reflectivity N0Q) as Web Mercator tiles from the Iowa Environmental Mesonet. Descriptor only.
///
/// Verified (SOURCES.md §2.3): `.../nexrad-n0q-900913/6/10/25.png` returned a 6 KB PNG. New scans arrive about every 5
/// minutes; the URL always serves the latest composite (older frames use IEM's `-m05m`, `-m10m` layer suffixes, not modelled
/// here). Coverage is the contiguous US. IEM's terms have not been read; the catalogue entry is off by default.
public struct IEMRadarImagery: ImageryProvider {
    public let descriptor: SourceDescriptor
    public let allLayers: [ImageryLayer]

    public init(descriptor: SourceDescriptor = SourceCatalogue.iemNEXRAD) {
        self.descriptor = descriptor
        self.allLayers = [
            ImageryLayer(
                id: "iem.nexrad.n0q", source: descriptor.id, title: "NEXRAD radar (IEM)", kind: .radar, scheme: .xyz,
                urlTemplate: "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png",
                minZoom: 2, maxZoom: 10, tileSize: 256, timeStep: .seconds(300), coverage: descriptor.coverage,
                attribution: "Radar: NOAA NWS NEXRAD via Iowa Environmental Mesonet", licence: descriptor.licence)
        ]
    }

    public func layers(at coordinate: Coordinate) -> [ImageryLayer] {
        allLayers.filter { $0.coverage.contains(coordinate) }
    }
}
