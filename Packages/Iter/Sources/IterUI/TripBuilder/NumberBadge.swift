import SwiftUI

/// The round stop number: the same coral disc as the stop's pin on the map, or a neutral one for places that are not
/// the plan's own stops. Hidden from VoiceOver (the stop's label includes the number). Figma part: number badge.
public struct NumberBadge: View {
    public enum Style: Sendable { case accent, neutral }

    public let number: Int
    public var style: Style
    public var size: CGFloat

    public init(number: Int, style: Style = .accent, size: CGFloat = 20) {
        self.number = number
        self.style = style
        self.size = size
    }

    public var body: some View {
        Text(number, format: .number)
            .font(BuilderType.bodyStrong)
            .monospacedDigit()
            .foregroundStyle(style == .accent ? IterColor.onAccent : IterColor.textPrimary.color)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        style == .accent ? AnyShapeStyle(IterColor.brandDot) : AnyShapeStyle(.quaternary)
    }
}
