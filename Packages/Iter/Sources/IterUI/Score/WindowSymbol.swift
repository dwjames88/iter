import IterModel
import SwiftUI

/// A light window named by its symbol (list rows, pins, cards, trip stops). The word stays available as the tooltip
/// and the VoiceOver label. Figma part: window symbol.
public struct WindowSymbol: View {
    /// Default point size outside a chip.
    public static let defaultSize: CGFloat = 16

    public let kind: LightWindowKind
    public var font: Font
    /// nil: the standalone colour, `light/blueHour` for the blue-hour windows and `text/secondary` otherwise.
    public var color: AnyShapeStyle?

    public init(kind: LightWindowKind, font: Font = .system(size: WindowSymbol.defaultSize), color: AnyShapeStyle? = nil) {
        self.kind = kind
        self.font = font
        self.color = color
    }

    private var standaloneColor: AnyShapeStyle {
        switch kind {
        case .blueMorning, .blueEvening: AnyShapeStyle(IterColor.blueHour)
        case .goldenMorning, .goldenEvening, .night: AnyShapeStyle(IterColor.textSecondary)
        }
    }

    public var body: some View {
        Image(systemName: LightText.symbol(kind))
            .symbolRenderingMode(.monochrome)
            .font(font)
            .foregroundStyle(color ?? standaloneColor)
            .help(LightText.name(kind))
            .accessibilityLabel(LightText.name(kind))
    }
}
