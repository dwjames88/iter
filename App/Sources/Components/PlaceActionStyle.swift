import SwiftUI
import IterDesign

extension View {
    /// A place card's action, as Maps lays out its action row: the icon over a short title, an equal share of the row.
    /// The row sits in the card's content, so it isn't Liquid Glass (the HIG keeps glass out of the content layer): the
    /// main action is the prominent bordered style in the accent, as Maps' Plan; the rest are bordered with monochrome
    /// labels, since the card's content (the light scores) is already full of the accent.
    func placeAction(isProminent: Bool = false) -> some View {
        modifier(PlaceAction(isProminent: isProminent))
    }
}

private struct PlaceAction: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent {
            #if os(macOS)
            // A Mac menu button ignores the prominent style's fill, so it draws the same accent fill itself.
            content.labelStyle(PlaceActionLabelStyle()).buttonStyle(ProminentMenuButtonStyle())
            #else
            styled(content).buttonStyle(.borderedProminent).tint(IterColor.accent)
            #endif
        } else {
            styled(content).buttonStyle(.bordered).tint(.primary)
        }
    }

    private func styled(_ content: Content) -> some View {
        content
            .labelStyle(PlaceActionLabelStyle())
            .buttonSizing(.flexible)
            .buttonBorderShape(.roundedRectangle)
            // The label sets the height (52 pt, a 44 pt hit region and more); the regular size keeps the side insets
            // narrow enough for four actions across an iPhone.
            .controlSize(.regular)
    }
}

#if os(macOS)
/// The prominent bordered style (an accent fill, white content) for a menu button on the Mac.
private struct ProminentMenuButtonStyle: ButtonStyle {
    static let shape = ConcentricRectangle(corners: .concentric(minimum: 10), isUniform: true)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, IterSpace.sm)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(IterColor.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Self.shape)
            .contentShape(Self.shape)
    }
}
#endif

private struct PlaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.font(.system(size: 17, weight: .semibold))
                .frame(height: 22)
            configuration.title.font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.vertical, 2)
    }
}
