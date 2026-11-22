import IterModel
import SwiftUI

/// The score chip: a light window's symbol, time and score as ONE continuous rounded rectangle in one fill.
/// Figma part: score chip (Large and Small are the component set; compact and pin are derived).
///
/// A scored chip is filled with `IterColor.ramp(score:)`. On the left a leading-aligned column: the window's symbol
/// above its time; on the right the score numeral in a fixed-width field (as wide as "100"), so every chip of a size
/// and time style is the same width at any score, unscored included. Symbol, time and score share
/// `IterColor.rampText(score:)` (white on every chip in dark mode, from the tokens). Scores below
/// `IterRamp.hairlineBelowScore` get a hairline. An unscored chip has no fill and no number, a hairline outline, the
/// symbol in its standalone colour, and a mini spinner while loading. Sizes are fixed points, not Dynamic Type.
public struct ScoreChip: View {
    public enum Size: Sendable, CaseIterable, Hashable { case compact, small, large, pin }

    /// How the time inside the chip reads.
    public enum TimeStyle: Hashable, Sendable {
        /// "18:09"
        case start
        /// "18:09–18:43" (falls back to the start when no end is given)
        case range
        /// No time line: the symbol alone over nothing.
        case none
    }

    public let kind: LightWindowKind
    public let start: Date
    public let end: Date?
    public let score: Int?
    public let zone: TimeZone
    public let locale: Locale
    public var size: Size
    public var timeStyle: TimeStyle
    public var isLowConfidence: Bool
    public var isTomorrow: Bool
    /// The forecast is being fetched: an unscored chip shows a small spinner beside its symbol.
    public var isLoading: Bool
    /// Pin only: scale and larger shadow.
    public var isSelected: Bool

    public init(kind: LightWindowKind, start: Date, end: Date? = nil, score: Int?, zone: TimeZone,
                locale: Locale = .current, size: Size = .small, timeStyle: TimeStyle = .start,
                isLowConfidence: Bool = false, isTomorrow: Bool = false, isLoading: Bool = false,
                isSelected: Bool = false) {
        self.kind = kind
        self.start = start
        self.end = end
        self.score = score.map { IterRamp.clamp($0) }
        self.zone = zone
        self.locale = locale
        self.size = size
        self.timeStyle = timeStyle
        self.isLowConfidence = isLowConfidence
        self.isTomorrow = isTomorrow
        self.isLoading = isLoading
        self.isSelected = isSelected
    }

    public var body: some View {
        content
            .help(accessibilityText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        if size == .pin { pin } else { chip }
    }

    // MARK: Chip

    private var chipSize: Size { size == .pin ? .compact : size }

    private var textColor: Color { score.map { IterColor.rampText(score: $0) } ?? IterColor.textPrimary.color }

    private var chip: some View {
        let s = chipSize
        let shape = RoundedRectangle(cornerRadius: Self.radius(s), style: .continuous)
        return HStack(spacing: Self.gap(s)) {
            column
            // One fixed width per size (wide enough for "100"), number trailing-aligned; unscored keeps the field.
            ZStack(alignment: .trailing) {
                Color.clear
                if let score {
                    Text(score, format: .number.locale(locale))
                        .font(IterFont.eventScore(size: Self.scoreSize(s)))
                        .monospacedDigit()
                        .foregroundStyle(IterColor.rampText(score: score))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: Self.scoreFieldWidth(s))
        }
        .padding(.horizontal, Self.padding(s))
        .padding(.vertical, Self.paddingV(s))
        .frame(height: Self.height(s))
        .background(chipFill, in: shape)
        .overlay {
            if score.map({ IterColor.rampNeedsHairline(score: $0) }) ?? true {
                shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline)
            }
        }
        .opacity(isLowConfidence ? IterEvent.lowConfidenceOpacity : 1)
    }

    private var column: some View {
        let s = chipSize
        let symbolFont = Font.system(size: Self.timeSize(s), weight: .semibold)
        return VStack(alignment: .leading, spacing: 0) {
            if score != nil {
                Image(systemName: LightText.symbol(kind))
                    .symbolRenderingMode(.monochrome)
                    .font(symbolFont)
                    .foregroundStyle(textColor)
            } else {
                HStack(spacing: IterSpace.xs) {
                    WindowSymbol(kind: kind, font: symbolFont)
                    if isLoading { ProgressView().controlSize(.mini) }
                }
            }
            if timeStyle != .none {
                Text(timeString)
                    .font(IterFont.eventTime(size: Self.timeSize(s)))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// The one fill: the ramp colour; none when unscored (a pin gets the solid content colour).
    private var chipFill: AnyShapeStyle {
        if let score { return AnyShapeStyle(IterColor.ramp(score: score)) }
        return size == .pin ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(Color.clear)
    }

    private var timeString: String { Self.timeText(style: timeStyle, start: start, end: end, zone: zone, locale: locale) }

    private static func timeText(style: TimeStyle, start: Date, end: Date?, zone: TimeZone, locale: Locale) -> String {
        switch style {
        case .none: ""
        case .start: TimeText.time(start, in: zone, locale: locale)
        case .range:
            if let end { TimeText.timeRange(TimeSpan(start: start, end: end), in: zone, locale: locale) }
            else { TimeText.time(start, in: zone, locale: locale) }
        }
    }

    // MARK: Pin

    private var pin: some View {
        VStack(spacing: 0) {
            chip
            PinPointer()
                .fill(chipFill)
                .frame(width: IterSpace.sm, height: IterSpace.xs)
                .opacity(isLowConfidence ? IterEvent.lowConfidenceOpacity : 1)
        }
        .shadow(radius: isSelected ? IterEvent.pinShadowRadiusSelected : IterEvent.pinShadowRadius, y: 1)
        .scaleEffect(isSelected ? IterEvent.pinScaleSelected : 1, anchor: .bottom)
        .animation(.spring, value: isSelected)
    }

    // MARK: Words

    /// "Sunset, 18:14, score 64"; "Sunset, tomorrow at 18:14, score 64"; no score part when unscored.
    public var accessibilityText: String { Self.accessibilityText(kind: kind, start: start, zone: zone, locale: locale,
                                                                  score: score, isTomorrow: isTomorrow,
                                                                  isLowConfidence: isLowConfidence) }

    public static func accessibilityText(kind: LightWindowKind, start: Date, zone: TimeZone, locale: Locale = .current,
                                         score: Int?, isTomorrow: Bool = false, isLowConfidence: Bool = false) -> String {
        let name = LightText.name(kind)
        let time = TimeText.time(start, in: zone, locale: locale)
        var text = isTomorrow
            ? String(localized: "\(name), tomorrow at \(time)", bundle: .module, locale: locale,
                     comment: "VoiceOver: a window tomorrow, with its time")
            : String(localized: "\(name), \(time)", bundle: .module, locale: locale,
                     comment: "VoiceOver: a window with its time")
        if let score {
            let n = score.formatted(.number.locale(locale))
            text += String(localized: ", score \(n)", bundle: .module, locale: locale, comment: "VoiceOver: appended score")
            if isLowConfidence {
                text += String(localized: ", low confidence", bundle: .module, locale: locale, comment: "VoiceOver: appended confidence")
            }
        }
        return text
    }

    // MARK: Metrics

    private static func pick(_ v: Size, _ compact: CGFloat, _ small: CGFloat, _ large: CGFloat) -> CGFloat {
        switch v { case .compact, .pin: compact; case .small: small; case .large: large }
    }
    public static func height(_ v: Size) -> CGFloat { pick(v, IterEvent.heightCompact, IterEvent.heightSmall, IterEvent.heightLarge) }
    public static func radius(_ v: Size) -> CGFloat { pick(v, IterEvent.radiusCompact, IterEvent.radiusSmall, IterEvent.radiusLarge) }
    static func scoreSize(_ v: Size) -> CGFloat { pick(v, IterEvent.scoreCompact, IterEvent.scoreSmall, IterEvent.scoreLarge) }
    /// The time and the window symbol share one point size.
    static func timeSize(_ v: Size) -> CGFloat { pick(v, IterEvent.timeCompact, IterEvent.timeSmall, IterEvent.timeLarge) }
    static func gap(_ v: Size) -> CGFloat { pick(v, IterEvent.gapCompact, IterEvent.gapSmall, IterEvent.gapLarge) }
    static func padding(_ v: Size) -> CGFloat { pick(v, IterEvent.paddingCompact, IterEvent.paddingSmall, IterEvent.paddingLarge) }
    static func paddingV(_ v: Size) -> CGFloat { pick(v, IterEvent.paddingVCompact, IterEvent.paddingVSmall, IterEvent.paddingVLarge) }

    // MARK: Lane width

    private struct WidthKey: Hashable, Sendable {
        var size: Size
        var style: TimeStyle
        var locale: String
    }
    private static let widths = WidthCache<WidthKey>()
    private static let fieldWidths = WidthCache<Size>()

    /// The width of every chip of this size and time style: padding, the symbol-and-time column, the gap and the
    /// numeral field. Lists that stack chips reserve this as a lane and trail-align each chip in it.
    public static func maxWidth(size: Size, timeStyle: TimeStyle, locale: Locale = .current) -> CGFloat {
        let s = size == .pin ? .compact : size
        let key = WidthKey(size: s, style: timeStyle, locale: "\(locale.identifier)|\(locale.hourCycle)")
        return widths.value(for: key) {
            let column = max(ceil(timeSize(s) * 1.25), timeLaneWidth(timeStyle, size: s, locale: locale))
            return ceil(padding(s) * 2 + column + gap(s) + scoreFieldWidth(s))
        }
    }

    /// The fixed width of the score field: "100" in the size's semibold monospaced-digit font, measured once.
    public static func scoreFieldWidth(_ size: Size) -> CGFloat {
        let s = size == .pin ? .compact : size
        return fieldWidths.value(for: s) {
            ceil(ScoreChipMeasure.width("100", size: scoreSize(s), weight: IterFont.eventScoreWeight()))
        }
    }

    /// The widest time label of the style the locale can produce, sampled at :58 past every hour.
    private static func timeLaneWidth(_ style: TimeStyle, size: Size, locale: Locale) -> CGFloat {
        guard style != .none else { return 0 }
        let utc = TimeZone(identifier: "UTC")!
        let midnight = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
        let weight = IterFont.eventTimeWeight()
        let widest = (0..<24).map { hour -> CGFloat in
            let s = midnight.addingTimeInterval(Double(hour) * 3600 + 58 * 60)
            let text = timeText(style: style, start: s, end: s.addingTimeInterval(59 * 60), zone: utc, locale: locale)
            return ScoreChipMeasure.width(text, size: timeSize(size), weight: weight)
        }.max() ?? 0
        return ceil(widest) + 1
    }
}

private struct PinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Previews

#Preview("Score chip, light") { ScoreChipPreview().preferredColorScheme(.light) }
#Preview("Score chip, dark") { ScoreChipPreview().preferredColorScheme(.dark) }

private struct ScoreChipPreview: View {
    var body: some View {
        let start = Date(timeIntervalSince1970: 1_791_290_700)
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            ForEach([ScoreChip.Size.large, .small, .compact], id: \.self) { size in
                HStack(spacing: IterSpace.lg) {
                    ForEach([0, 50, 100] as [Int?] + [nil], id: \.self) { score in
                        ScoreChip(kind: .goldenMorning, start: start, score: score, zone: .gmt, size: size)
                    }
                }
            }
        }
        .padding(IterSpace.xl)
        .background(IterColor.backgroundWindow)
    }
}
