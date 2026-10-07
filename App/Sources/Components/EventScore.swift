#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// How the time inside an event unit reads.
enum TimeStyle: Sendable {
    /// "18:09"
    case start
    /// "18:09–18:43"
    case range
}

/// The event unit: a light window's score, symbol and time as ONE rounded rectangle in one continuous fill.
///
/// A scored unit is filled with the band's ramp colour (corner radius a quarter of the height, not a capsule). On the
/// left sits the score as a very large, heavy, monospaced-digit numeral that takes nearly the full height; on the
/// right a column centred vertically: the window's symbol above, the start time below in a thin weight, about a third
/// of the numeral's size. Everything is white, which every ramp fill passes at 4.5:1 (see `ContrastTests`). A window
/// without a score is the same size with no fill and a hairline outline, the symbol over the time in the text
/// colours (and a mini spinner beside the symbol while the forecast loads). The numeral and the stack take fixed
/// measured widths per variant and time style (`unitWidth`), so units stack and align. Sizes are fixed points from the
/// `event/*` tokens, not Dynamic Type: the unit is a fixed-height badge. The `pin` variant is the compact unit over the
/// map, with a pointer, a shadow and a selected scale; an unscored pin is a material so the time stays legible over any map.
struct EventScore: View {
    enum Variant: Sendable { case compact, regular, large, pin }

    /// What the unit draws. A window gives all of it; a map pin carries only these fields (`ExplorePinLight`), so a
    /// pin that did not change stays equal and is not redrawn.
    struct Mark: Equatable, Sendable {
        var value: Int
        var band: LightBand
        var confidence: Confidence
    }

    let kind: LightWindowKind
    let span: TimeSpan
    let score: Mark?
    /// The spot's zone: the time is shown there.
    let zone: TimeZone
    var timeStyle: TimeStyle = .start
    var variant: Variant = .regular
    /// The forecast is being fetched: an unscored window shows a small spinner beside its symbol.
    var isLoading = false
    /// For VoiceOver and the tooltip only: the window falls on tomorrow.
    var isTomorrow = false
    /// Pin only.
    var isSelected = false
    /// VoiceOver's description of the window, before the time.
    private let spokenBase: String

    @Environment(\.renderMode) private var renderMode

    init(window: LightWindow, zone: TimeZone, timeStyle: TimeStyle = .start, variant: Variant = .regular,
         isLoading: Bool = false, isTomorrow: Bool = false, isSelected: Bool = false) {
        self.kind = window.kind
        self.span = window.span
        self.score = window.assessment.lightScore.map { Mark(value: $0.value, band: $0.band, confidence: $0.confidence) }
        self.spokenBase = LightText.accessibilityDescription(window)
        self.zone = zone
        self.timeStyle = timeStyle
        self.variant = variant
        self.isLoading = isLoading
        self.isTomorrow = isTomorrow
        self.isSelected = isSelected
    }

    /// The unscored form, for a place that knows only a window's kind and start (a trip's next session).
    init(kind: LightWindowKind, start: Date, zone: TimeZone, variant: Variant = .compact, isTomorrow: Bool = false) {
        self.init(window: LightWindow(kind: kind, span: TimeSpan(start: start, end: start), assessment: .noForecast(.beyondHorizon)),
                  zone: zone, timeStyle: .start, variant: variant, isTomorrow: isTomorrow)
    }

    /// A map pin, from the few fields the cached pin carries (start time only).
    init(pin light: ExplorePinLight, zone: TimeZone, isSelected: Bool) {
        self.kind = light.kind
        self.span = TimeSpan(start: light.start, end: light.start)
        self.score = light.score.map { Mark(value: $0.value, band: $0.band, confidence: $0.confidence) }
        self.spokenBase = light.score.map {
            String(localized: "\(LightText.name(light.kind)), Light Index \($0.value), \(LightText.name($0.band)), \(LightText.name($0.confidence))",
                   comment: "VoiceOver: window, score, band, confidence")
        } ?? LightText.name(light.kind)
        self.zone = zone
        self.timeStyle = .start
        self.variant = .pin
        self.isLoading = light.isLoading
        self.isTomorrow = light.isTomorrow
        self.isSelected = isSelected
    }

    var body: some View {
        content
            .help(spoken)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    @ViewBuilder private var content: some View {
        if variant == .pin {
            pin
        } else {
            unit
        }
    }

    // MARK: Unit

    private var unitVariant: Variant { variant == .pin ? .compact : variant }

    private var unit: some View {
        let v = unitVariant
        let height = Self.height(v)
        let shape = RoundedRectangle(cornerRadius: height * IterEvent.cornerRatio, style: .continuous)
        return Group {
            if let score {
                HStack(spacing: Self.gap(v)) {
                    Text(score.value, format: .number)
                        .font(IterFont.eventScore(size: Self.scoreSize(v)))
                        .monospacedDigit()
                        .foregroundStyle(IterColor.rampText(score.band))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: Self.scoreWidth(v))
                    stack(color: IterColor.rampText(score.band))
                        .frame(width: Self.stackWidth(v, timeStyle))
                }
                .padding(.horizontal, Self.padding(v))
            } else {
                stack(color: IterColor.textPrimary.color)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: Self.unitWidth(v, timeStyle: timeStyle), height: height)
        .background(unitFill, in: shape)
        .overlay {
            if score == nil { shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline) }
        }
        .opacity(score?.confidence == .low ? IterEvent.lowConfidenceOpacity : 1)
    }

    /// The symbol above the start time, centred. A scored unit draws both in one colour (white); an unscored one
    /// draws the symbol in its standalone colour and a spinner beside it while loading.
    private func stack(color: Color) -> some View {
        let v = unitVariant
        return VStack(spacing: Self.stackGap(v)) {
            if score != nil {
                Image(systemName: LightText.symbol(kind))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: Self.symbolSize(v)))
                    .foregroundStyle(color)
            } else {
                HStack(spacing: IterSpace.xs) {
                    WindowSymbol(kind: kind, font: .system(size: Self.symbolSize(v)))
                    if isLoading { ProgressView().controlSize(.mini) }
                }
            }
            Text(timeString)
                .font(Self.timeFont(v))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The one fill: the band's ramp colour; none when unscored (a pin gets a material).
    private var unitFill: AnyShapeStyle {
        if let score { return AnyShapeStyle(IterColor.ramp(score.band)) }
        return variant == .pin ? pinFill : AnyShapeStyle(Color.clear)
    }

    private var timeString: String {
        switch timeStyle {
        case .start: TimeText.time(span.start, in: zone)
        case .range: TimeText.timeRange(span, in: zone)
        }
    }

    // MARK: Pin

    private var pin: some View {
        VStack(spacing: 0) {
            unit
            PinPointer()
                .fill(unitFill)
                .frame(width: IterSpace.sm, height: IterSpace.xs)
        }
        .shadow(radius: isSelected ? IterEvent.pinShadowRadiusSelected : IterEvent.pinShadowRadius, y: 1)
        .scaleEffect(isSelected ? IterEvent.pinScaleSelected : 1, anchor: .bottom)
        .animation(.spring, value: isSelected)
    }

    private var pinFill: AnyShapeStyle {
        // An offscreen render has no backdrop for materials.
        renderMode == .snapshot ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(.regularMaterial)
    }

    // MARK: Words

    private var spoken: String {
        let base = spokenBase
        if isTomorrow {
            return String(localized: "\(base), tomorrow at \(timeString)", comment: "VoiceOver: a window tomorrow, with its time")
        }
        return String(localized: "\(base), \(timeString)", comment: "VoiceOver: a window with its time")
    }

    // MARK: Metrics

    private static func pick(_ v: Variant, _ compact: CGFloat, _ regular: CGFloat, _ large: CGFloat) -> CGFloat {
        switch v { case .compact, .pin: compact; case .regular: regular; case .large: large }
    }
    static func height(_ v: Variant) -> CGFloat { pick(v, IterEvent.heightCompact, IterEvent.heightRegular, IterEvent.heightLarge) }
    static func scoreSize(_ v: Variant) -> CGFloat { pick(v, IterEvent.scoreCompact, IterEvent.scoreRegular, IterEvent.scoreLarge) }
    static func timeSize(_ v: Variant) -> CGFloat { pick(v, IterEvent.timeCompact, IterEvent.timeRegular, IterEvent.timeLarge) }
    static func symbolSize(_ v: Variant) -> CGFloat { pick(v, IterEvent.symbolCompact, IterEvent.symbolRegular, IterEvent.symbolLarge) }
    static func stackGap(_ v: Variant) -> CGFloat { pick(v, IterEvent.stackGapCompact, IterEvent.stackGapRegular, IterEvent.stackGapLarge) }
    static func gap(_ v: Variant) -> CGFloat { pick(v, IterEvent.gapCompact, IterEvent.gap, IterEvent.gapLarge) }
    static func padding(_ v: Variant) -> CGFloat { pick(v, IterEvent.paddingCompact, IterEvent.padding, IterEvent.paddingLarge) }
    static func timeFont(_ v: Variant) -> Font { IterFont.eventTime(size: timeSize(v), large: v == .large) }

    private static func nsWeight(_ w: FontWeightName) -> NSFont.Weight {
        switch w {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    // MARK: Measured widths

    /// The width of one whole unit of the variant and time style: padding, numeral lane, gap, stack lane, padding.
    /// Fixed, so every unit of a variant and style is the same size and stacks align perfectly.
    static func unitWidth(_ variant: Variant, timeStyle: TimeStyle) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        return laneWidth(v) + tailWidth(v, timeStyle)
    }

    /// The head: left padding, the numeral lane and the gap to the stack.
    static func laneWidth(_ variant: Variant) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        return padding(v) + scoreWidth(v) + gap(v)
    }

    /// The tail: the stack lane and the right padding.
    static func tailWidth(_ variant: Variant, _ style: TimeStyle) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        return stackWidth(v, style) + padding(v)
    }

    /// The numeral lane: two heavy digits ("88", the widest). A 100 shrinks to fit rather than widening every unit.
    static func scoreWidth(_ v: Variant) -> CGFloat {
        ceil(measure("88", font: NSFont.monospacedDigitSystemFont(ofSize: scoreSize(v), weight: nsWeight(IterFont.eventScoreWeight()))))
    }

    /// The stack lane: the wider of the symbol (point size times 1.25: SF Symbols are wider than tall) and the widest time.
    static func stackWidth(_ v: Variant, _ style: TimeStyle) -> CGFloat {
        max(ceil(symbolSize(v) * 1.25), timeLaneWidth(style, variant: v))
    }

    /// The widest time label of the style that the current locale and clock format can produce, sampled at :58 past
    /// every hour, in the variant's time font. A `.range` is one line, "05:45–06:20", in the time slot.
    static func timeLaneWidth(_ style: TimeStyle, variant: Variant) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        let font = NSFont.monospacedDigitSystemFont(ofSize: timeSize(v), weight: nsWeight(IterFont.eventTimeWeight(large: v == .large)))
        let utc = TimeZone(identifier: "UTC")!
        let midnight = LocalDay(year: 2026, month: 1, day: 1).at(hour: 0, in: utc)
        let widest = (0..<24).map { hour -> CGFloat in
            let start = midnight.addingTimeInterval(Double(hour) * 3600 + 58 * 60)
            let text = style == .start
                ? TimeText.time(start, in: utc)
                : TimeText.timeRange(TimeSpan(start: start, end: start.addingTimeInterval(59 * 60)), in: utc)
            return measure(text, font: font)
        }.max() ?? 0
        return ceil(widest) + 1
    }

    fileprivate static func measure(_ string: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font]).size().width
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

/// The band word and the confidence mark: "Great ▮▮▯", on one first baseline, in the secondary style.
struct BandConfidence: View {
    let score: LightScore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            Text(LightText.name(score.band))
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
                .lineLimit(1)
            ConfidenceMark(confidence: score.confidence)
        }
    }

    /// The widest band word in the current language at the secondary size, a gap and the confidence mark.
    static var laneWidth: CGFloat {
        let base = NSFont.preferredFont(forTextStyle: .subheadline)
        let font = NSFont.systemFont(ofSize: base.pointSize, weight: .regular)
        let word = LightBand.allCases.map { EventScore.measure(LightText.name($0), font: font) }.max() ?? 0
        return ceil(word) + IterSpace.xs + ConfidenceMark.width
    }
}

/// Three small bars: how far to trust the score.
struct ConfidenceMark: View {
    let confidence: Confidence

    /// Three bars and the two hairline gaps between them.
    static let width: CGFloat = IterStroke.thick * 3 + IterStroke.thin * 2

    var body: some View {
        HStack(alignment: .bottom, spacing: IterStroke.thin) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: IterStroke.thin)
                    .fill(i < filled ? IterColor.textSecondary.color : IterColor.separator)
                    .frame(width: IterStroke.thick, height: IterSize.confidenceMark * CGFloat(i + 1) / 3)
            }
        }
        .frame(height: IterSize.confidenceMark, alignment: .bottom)
        .accessibilityLabel(LightText.name(confidence))
    }

    private var filled: Int {
        switch confidence { case .low: 1; case .medium: 2; case .high: 3 }
    }
}
