import SwiftUI
import MapKit
import IterCore
import IterDesign

/// A small map you pan under a fixed centre pin: the pin's tip is the spot's coordinate. Used by the spot editor (Add
/// Spot) and by Edit Location for your own spots. Typing or pasting coordinates recentres the map; panning the map
/// writes the coordinate back, so the fields and the map always agree. Reset Pin returns to `original`.
/// A Form section: the map, then a footer with the hint, the coordinate and Reset Pin.
struct SpotPinMapSection: View {
    @Binding var coordinate: Coordinate
    /// Where the spot was when the sheet opened; Reset Pin goes back to it.
    let original: Coordinate
    /// The pin's name in a snapshot render, where a static stand-in replaces the live map.
    var label = ""

    @Environment(\.renderMode) private var renderMode
    @State private var position: MapCameraPosition
    /// Where the small map's camera is, so a typed or pasted coordinate recentres it and a drag of the map does not.
    @State private var cameraCenter: Coordinate

    init(coordinate: Binding<Coordinate>, original: Coordinate, label: String = "") {
        _coordinate = coordinate
        self.original = original
        self.label = label
        _position = State(initialValue: Self.cameraPosition(coordinate.wrappedValue))
        _cameraCenter = State(initialValue: coordinate.wrappedValue)
    }

    var body: some View {
        Section {
            pinMap
                #if os(iOS)
                .listRowInsets(EdgeInsets())
                #endif
        } footer: {
            footer
        }
    }

    // MARK: Map

    private var pinMap: some View {
        ZStack {
            if renderMode == .snapshot {
                MapStandIn(pins: [.init(id: "pin", coordinate: coordinate, label: label, selected: true)])
            } else {
                Map(position: $position, interactionModes: [.pan, .zoom])
                    .mapStyle(.standard(elevation: .realistic))
                    .onMapCameraChange(frequency: .onEnd) { context in
                        let c = context.camera.centerCoordinate
                        let moved = Coordinate(latitude: c.latitude, longitude: c.longitude)
                        cameraCenter = moved
                        if moved.distance(to: coordinate) > 1 { coordinate = moved }
                    }
                // The tip of the pin is the centre of the map.
                Image(systemName: "mappin")
                    .font(.largeTitle)
                    .foregroundStyle(IterColor.accent)
                    .shadow(radius: IterStroke.regular)
                    .offset(y: -IterSize.iconLarge)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: IterSize.arcHeight)
        .clipShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous).strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        .onChange(of: coordinate) { _, new in
            if new.distance(to: cameraCenter) > 1 { cameraCenter = new; position = Self.cameraPosition(new) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map with the spot's pin at the centre", comment: "VoiceOver"))
        .accessibilityValue(coordinateText)
    }

    // MARK: Footer

    private var coordinateText: String {
        let lat = coordinate.latitude.formatted(.number.precision(.fractionLength(4)))
        let lon = coordinate.longitude.formatted(.number.precision(.fractionLength(4)))
        return "\(lat), \(lon)"
    }

    private var footer: some View {
        // One line where it fits (the Mac sheet); two on a phone.
        ViewThatFits(in: .horizontal) {
            HStack {
                hint
                Text(coordinateText).monospacedDigit()
                Spacer()
                reset
            }
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                hint
                HStack {
                    Text(coordinateText).monospacedDigit()
                    Spacer()
                    reset
                }
            }
        }
    }

    private var hint: some View {
        Text("Drag the map to move the pin, or type the coordinates.", comment: "Spot editor map hint")
    }

    @ViewBuilder private var reset: some View {
        if coordinate != original {
            Button {
                coordinate = original
                cameraCenter = original
                position = Self.cameraPosition(original)
            } label: { Text("Reset Pin", comment: "Button") }
            .linkButtonStyle()
        }
    }

    private static func cameraPosition(_ c: Coordinate) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                                   span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
    }
}
