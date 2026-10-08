import SwiftUI
import IterDesign

/// An action on a place card, as Apple Maps draws its action row: a rounded tile with the icon over a short title,
/// taking an equal share of the row. The card's main action is prominent, filled with the accent; the others are
/// tinted with it. Works on `Button`, `ShareLink` and `Menu` (with `.menuStyle(.button)`).
struct PlaceActionStyle: ButtonStyle {
    var isProminent = false

    static var height: CGFloat { 44 }
    static var cornerRadius: CGFloat { 10 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PlaceActionLabelStyle())
            .foregroundStyle(isProminent ? AnyShapeStyle(IterColor.onAccent) : AnyShapeStyle(IterColor.accentText))
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background(isProminent ? IterColor.accent : IterColor.accent.opacity(0.14),
                        in: .rect(cornerRadius: Self.cornerRadius))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
    }
}

private struct PlaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.font(.system(size: 14, weight: .semibold))
            configuration.title.font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, IterSpace.xs)
    }
}
