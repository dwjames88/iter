import SwiftUI
import MapKit
import IterFeatures

extension MapStyleChoice {
    /// The name shown in the menus.
    var title: String {
        switch self {
        case .standard: String(localized: "Standard", comment: "Map style")
        case .satellite: String(localized: "Satellite", comment: "Map style")
        case .hybrid: String(localized: "Hybrid", comment: "Map style: satellite imagery with labels")
        }
    }

    /// The MapKit style for this choice. Points of interest stay off, as on every Iter map.
    func mapStyle(elevation: MapStyle.Elevation = .flat) -> MapStyle {
        switch self {
        case .standard: .standard(elevation: elevation, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: elevation)
        case .hybrid: .hybrid(elevation: elevation, pointsOfInterest: .excludingAll)
        }
    }
}

/// The compact map style control: a system menu button with Standard, Satellite and Hybrid (checkmark on the current
/// one), writing the shared `iter.map.style` setting that every map reads.
struct MapStyleMenu: View {
    @AppStorage(MapStyleChoice.storageKey) private var raw = MapStyleChoice.default.rawValue

    var body: some View {
        Menu {
            Picker(selection: $raw) {
                ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                Text("Map Style", comment: "Map control")
            }
            .pickerStyle(.inline)
        } label: {
            #if os(iOS)
            RoundGlassLabel(systemImage: "map")
            #else
            Image(systemName: "map")
                .frame(width: 24, height: 24)
            #endif
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        #endif
        .accessibilityLabel(Text("Map Style", comment: "Map control"))
    }
}
