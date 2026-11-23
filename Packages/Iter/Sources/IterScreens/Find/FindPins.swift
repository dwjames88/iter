import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// One map pin: a solid plate (never material) so live and snapshot renders match. Results show their rank, saved places a
/// bookmark, typed matches a magnifier, and your own spots a pin with a tip. The selected result and the best few carry their
/// score chip once it is known; a pin with no score shows its rank, and the map never draws a number it does not have.
struct FindPinView: View, Equatable {
    let pin: FindPin
    var isSelected = false

    static let plate: CGFloat = 28

    /// Pins with a tip anchor at the bottom; round plates at the centre.
    static func anchor(for pin: FindPin, isSelected: Bool = false) -> UnitPoint {
        pin.kind == .own || pin.showsChip(isSelected: isSelected) ? .bottom : .center
    }

    var body: some View {
        Group {
            switch pin.kind {
            case .result(let rank):
                if pin.showsChip(isSelected: isSelected), let score = pin.score {
                    FindScoreChip(score: score, size: .pin, isSelected: isSelected)
                } else {
                    plate { Text(rank, format: .number).font(IterFont.captionStrong).monospacedDigit() }
                }
            case .saved: plate { Image(systemName: "bookmark.fill").font(.system(size: 12, weight: .semibold)) }
            case .match: plate { Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)) }
            case .own: ownPin
            }
        }
        .modifier(PlateEffects(isSelected: isSelected, applies: !pin.showsChip(isSelected: isSelected), anchor: Self.anchor(for: pin, isSelected: isSelected)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: pin.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func plate(@ViewBuilder _ glyph: () -> some View) -> some View {
        glyph()
            .foregroundStyle(isSelected ? IterColor.onAccent : IterColor.textPrimary.color)
            .frame(width: Self.plate, height: Self.plate)
            .background(isSelected ? IterColor.accent : IterColor.backgroundContent, in: Circle())
            .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }

    private var ownPin: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(IterColor.onAccent)
                .frame(width: Self.plate, height: Self.plate)
                .background(IterColor.mapPin, in: Circle())
                .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            FindPinTip().fill(IterColor.mapPin).frame(width: IterSpace.sm, height: IterSpace.xs)
        }
    }
}

/// Plates get a scale and shadow; a score chip pin brings its own.
private struct PlateEffects: ViewModifier {
    let isSelected: Bool
    let applies: Bool
    let anchor: UnitPoint
    func body(content: Content) -> some View {
        if applies {
            content
                .scaleEffect(isSelected ? IterEvent.pinScaleSelected : 1, anchor: anchor)
                .shadow(color: .black.opacity(0.25), radius: isSelected ? IterEvent.pinShadowRadiusSelected : IterEvent.pinShadowRadius, y: 1)
        } else {
            content
        }
    }
}

private struct FindPinTip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Several result pins too close to tell apart at this zoom, as one count on a solid plate. Clicking zooms to fit its members.
struct FindClusterView: View, Equatable {
    let cluster: FindCluster

    var body: some View {
        Text(cluster.count, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(IterColor.textPrimary)
            .frame(minWidth: IterSize.badgeHeight, minHeight: IterSize.badgeHeight)
            .padding(.horizontal, IterSpace.xs)
            .background(IterColor.backgroundContent, in: Capsule())
            .overlay(Capsule().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .shadow(color: .black.opacity(0.25), radius: IterEvent.pinShadowRadius, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(cluster.count) places"))
            .accessibilityAddTraits(.isButton)
    }
}
