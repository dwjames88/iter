import SwiftUI
import IterDesign

extension View {
    /// A place card's action, as Maps lays out its action row: the icon over a short title, an equal share of the row.
    /// The system's glass button styles draw it; the card's main action is the prominent one.
    func placeAction(isProminent: Bool = false) -> some View {
        modifier(PlaceAction(isProminent: isProminent))
    }
}

private struct PlaceAction: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent {
            // The one main action carries the accent, as Maps' Directions does; the rest stay clear glass.
            #if os(macOS)
            // A Mac menu ignores the prominent glass tint, so the menu button draws that same tinted glass itself.
            content.labelStyle(PlaceActionLabelStyle()).buttonStyle(ProminentGlassMenuButtonStyle())
            #else
            styled(content).buttonStyle(.glassProminent).tint(IterColor.accent)
            #endif
        } else {
            styled(content).buttonStyle(.glass)
        }
    }

    private func styled(_ content: Content) -> some View {
        content
            .labelStyle(PlaceActionLabelStyle())
            .buttonSizing(.flexible)
            .buttonBorderShape(.roundedRectangle)
    }
}

#if os(macOS)
/// The system's prominent glass (glass tinted with the accent, white content) for a menu button on the Mac.
private struct ProminentGlassMenuButtonStyle: ButtonStyle {
    /// Concentric with the card it sits in, as the system's glass buttons are.
    static let shape = ConcentricRectangle(corners: .concentric(minimum: 10), isUniform: true)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, IterSpace.sm)
            .frame(maxWidth: .infinity)
            .contentShape(Self.shape)
            .glassEffect(.regular.tint(IterColor.accent).interactive(), in: Self.shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif

private struct PlaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.font(.system(size: 15, weight: .semibold))
                .frame(height: 20)
            configuration.title.font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}
