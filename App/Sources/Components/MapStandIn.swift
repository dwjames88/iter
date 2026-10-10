import SwiftUI
import IterCore
import IterDesign

/// Live MapKit content cannot be rendered offscreen. Snapshot renders draw this instead: a plain ground with the
/// same pins at their projected positions, labelled "Map" so nobody mistakes it for the real map.
struct MapStandIn: View {
    struct Pin: Identifiable {
        var id: String
        var coordinate: Coordinate
        var label: String
        var selected = false
        /// An event-unit pin (as on the Explore and Locations maps) instead of the plain marker.
        var event: Event?
        /// Carried (a pin of yours mid-drag): lifted with a shadow, the exact point marked under it.
        var lifted = false
    }

    struct Event {
        var window: LightWindow
        var zone: TimeZone
        var isLoading = false
        var isTomorrow = false
    }

    let pins: [Pin]
    var route: [Coordinate] = []

    var body: some View {
        GeometryReader { geo in
            let region = GeoRegion.enclosing(pins.map(\.coordinate) + route, padding: 0.4, minimumDelta: 0.2)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(IterColor.backgroundControl)
                if let region {
                    Path { path in
                        for (i, c) in route.enumerated() {
                            let p = project(c, region, geo.size)
                            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                    }
                    .stroke(IterColor.route, lineWidth: IterStroke.route)
                    ForEach(pins) { pin in
                        let p = project(pin.coordinate, region, geo.size)
                        if pin.lifted { PinTipDot().position(p) }
                        if let event = pin.event {
                            // The pin's bottom tip sits on the coordinate, like the live map's bottom-anchored annotation.
                            EventScore(window: event.window, zone: event.zone, timeStyle: .start, variant: .pin,
                                       isLoading: event.isLoading, isTomorrow: event.isTomorrow, isSelected: pin.selected)
                                .fixedSize()
                                .modifier(LiftedPin(isLifted: pin.lifted))
                                .position(x: p.x, y: p.y - (EventScore.height(.pin) + IterSpace.xs) / 2)
                        } else {
                        VStack(spacing: IterSpace.xxs) {
                            Circle()
                                .fill(pin.selected ? IterColor.mapPin : IterColor.mapPinInactive)
                                .frame(width: pin.selected ? IterSize.mapPinSelected : IterSize.mapPin,
                                       height: pin.selected ? IterSize.mapPinSelected : IterSize.mapPin)
                            Text(pin.label).font(IterFont.caption).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                        }
                        .fixedSize()
                        .position(p)
                        }
                    }
                }
                Text("Map (snapshot stand-in)", comment: "Label on the static map used in snapshot renders")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
                    .padding(IterSpace.sm)
            }
        }
        .accessibilityHidden(true)
    }

    private func project(_ c: Coordinate, _ r: GeoRegion, _ size: CGSize) -> CGPoint {
        let x = (c.longitude - (r.center.longitude - r.longitudeDelta / 2)) / r.longitudeDelta
        let y = ((r.center.latitude + r.latitudeDelta / 2) - c.latitude) / r.latitudeDelta
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}
