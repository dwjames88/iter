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

    /// The MapKit style for this choice. Points of interest stay off, as on every Iter map. Realistic elevation by
    /// default: terrain and, zoomed all the way out, Apple Maps' 3D globe.
    func mapStyle(elevation: MapStyle.Elevation = .realistic) -> MapStyle {
        switch self {
        case .standard: .standard(elevation: elevation, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: elevation)
        case .hybrid: .hybrid(elevation: elevation, pointsOfInterest: .excludingAll)
        }
    }
}

/// The map style control (the top of `MapControlStack` on the Mac): a system menu button with Standard, Satellite and Hybrid (checkmark on the current
/// one), writing the shared `iter.map.style` setting that every map reads.
struct MapStyleMenu: View {
    @AppStorage(MapStyleChoice.storageKey) private var raw = MapStyleChoice.default.rawValue
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true
    #if os(iOS)
    /// False inside a control group that draws one glass capsule for all its buttons (Explore's map controls).
    var isGlass = true
    #endif

    var body: some View {
        Menu {
            Picker(selection: $raw) {
                ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                Text("Map Style", comment: "Map control")
            }
            .pickerStyle(.inline)
            Toggle(isOn: $showsDaylight) {
                Text("Show Daylight", comment: "Map style menu: shade the night side of the globe when zoomed out")
            }
        } label: {
            #if os(iOS)
            if isGlass {
                RoundGlassLabel(systemImage: "map")
            } else {
                MapControlLabel(systemImage: "map")
            }
            #else
            Image(systemName: "map")
                .frame(width: MapControlStack<EmptyView>.size, height: MapControlStack<EmptyView>.size)
                .contentShape(.rect)
            #endif
        }
        #if os(macOS)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(String(localized: "Choose the map style", comment: "Tooltip"))
        #endif
        .accessibilityLabel(Text("Map Style", comment: "Map control"))
    }
}
