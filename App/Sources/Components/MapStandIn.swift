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
                        VStack(spacing: IterSpace.xxs) {
                            Circle()
                                .fill(pin.selected ? IterColor.accent : IterColor.textSecondary)
                                .frame(width: pin.selected ? IterSize.mapPinSelected : IterSize.mapPin,
                                       height: pin.selected ? IterSize.mapPinSelected : IterSize.mapPin)
                            Text(pin.label).font(IterFont.caption).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                        }
                        .fixedSize()
                        .position(p)
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
