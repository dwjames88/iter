import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// How a pin looks while it is carried: up a little, with a soft shadow below it. Shared by the live map and the
/// snapshot stand-in, so what the snapshot shows is what the map draws. Reduce Motion keeps the lift but drops the motion.
struct LiftedPin: ViewModifier {
    let isLifted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(isLifted ? 0.3 : 0), radius: isLifted ? IterSpace.sm : 0, y: isLifted ? IterSpace.sm : 0)
            .offset(y: isLifted ? -IterSpace.md : 0)
            .animation(reduceMotion ? nil : .smooth, value: isLifted)
    }
}

/// The exact point of one of your own spots, under its pin: the pointer ends here, so the place is never read off the pin.
struct PinTipDot: View {
    var body: some View {
        Circle()
            .fill(IterColor.mapPin)
            .frame(width: IterSpace.sm, height: IterSpace.sm)
            .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Snapshot renders cannot draw a live map. This draws the same pins, with the same pin views, lift and tip dot, on a flat
/// ground at the framed region, so a pin in the middle of a drag can be reviewed.
struct ExploreMapLayerStandIn: View {
    @Bindable var explore: ExploreModel

    var body: some View {
        GeometryReader { geo in
            let region = MapCameraPolicy.fit(explore.fitCoordinates)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(IterColor.backgroundControl)
                if let region {
                    ForEach(explore.mapItems) { item in
                        switch item {
                        case .pin(let pin):
                            let at = project(explore.displayCoordinate(for: pin.id, stored: pin.coordinate), region, geo.size)
                            let lifted = explore.dragging?.id == pin.id
                            if explore.canMove(pin.id), pin.style == .selected || lifted {
                                PinTipDot().position(at)
                            }
                            // The live map anchors the pin's tip on the coordinate; here the pin's bottom edge is the tip.
                            ExplorePinView(pin: pin)
                                .fixedSize()
                                .modifier(LiftedPin(isLifted: lifted))
                                .position(x: at.x, y: at.y - pinHeight(pin) / 2)
                        case .cluster(let cluster):
                            ExploreClusterView(cluster: cluster).position(project(cluster.coordinate, region, geo.size))
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

    private func pinHeight(_ pin: ExplorePin) -> CGFloat {
        pin.style == .dot ? 0 : EventScore.height(.pin) + IterSpace.xs
    }

    private func project(_ c: Coordinate, _ r: GeoRegion, _ size: CGSize) -> CGPoint {
        let x = (c.longitude - (r.center.longitude - r.longitudeDelta / 2)) / r.longitudeDelta
        let y = ((r.center.latitude + r.latitudeDelta / 2) - c.latitude) / r.latitudeDelta
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}
