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

/// The event unit: a light window's symbol, its score and its time as ONE capsule in one continuous fill.
///
/// A scored unit is filled with the band's ramp colour, and the symbol, the number and the time all sit on it in the
/// band's ramp text colour, on one first baseline. The number is semibold; the time is regular (medium in the large
/// variant), so the score stays the strongest element. Poor and Fair (pale fills) carry one hairline around the
/// capsule. A window without a score is one neutral capsule with the symbol in its standalone colour (and a mini
/// spinner while the forecast loads) and the time in primary text. The symbol and number take a fixed measured width
/// and the time another, per variant and time style (`unitWidth`), so units stack and align. The `pin` variant is
/// the compact unit over the map, with a pointer, a shadow and a selected scale; an unscored pin is a material so the
/// time stays legible over any map.
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
        let headWidth = Self.laneWidth(v)
        let tailWidth = Self.tailWidth(v, timeStyle)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            head
                .frame(width: headWidth)
            timeText
                .frame(width: tailWidth)
        }
        .frame(height: Self.height(v))
        .background(unitFill, in: Capsule())
        .overlay {
            if let score, score.band <= .fair { Capsule().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline) }
        }
        .opacity(score?.confidence == .low ? IterEvent.lowConfidenceOpacity : 1)
    }

    /// The head: symbol and number on one first baseline, or the unscored symbol.
    @ViewBuilder private var head: some View {
        let v = unitVariant
        if let score {
            HStack(alignment: .firstTextBaseline, spacing: IterEvent.gap) {
                Image(systemName: LightText.symbol(kind))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: Self.symbolSize(v)))
                Text(score.value, format: .number)
                    .font(Self.numberFont(v))
                    .monospacedDigit()
            }
            .foregroundStyle(IterColor.rampText(score.band))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: IterEvent.gap) {
                WindowSymbol(kind: kind, font: .system(size: Self.symbolSize(v)))
                if isLoading { ProgressView().controlSize(.mini) }
            }
        }
    }

    private var timeText: some View {
        Text(timeString)
            .font(Self.timeFont(unitVariant))
            .monospacedDigit()
            .foregroundStyle(score.map { IterColor.rampText($0.band) } ?? IterColor.textPrimary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The one fill: the band's ramp colour, or neutral when unscored.
    private var unitFill: AnyShapeStyle {
        if let score { return AnyShapeStyle(IterColor.ramp(score.band)) }
        return variant == .pin ? pinFill : AnyShapeStyle(IterColor.backgroundModule)
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

    static func height(_ v: Variant) -> CGFloat {
        switch v { case .compact, .pin: IterEvent.heightCompact; case .regular: IterEvent.heightRegular; case .large: IterEvent.heightLarge }
    }
    static func symbolSize(_ v: Variant) -> CGFloat {
        switch v { case .compact, .pin: IterEvent.symbolCompact; case .regular: IterEvent.symbolRegular; case .large: IterEvent.symbolLarge }
    }
    static func padding(_ v: Variant) -> CGFloat {
        switch v { case .compact, .pin: IterEvent.paddingCompact; case .regular, .large: IterEvent.padding }
    }
    static func numberFont(_ v: Variant) -> Font {
        switch v { case .compact, .pin: IterFont.scoreBadge; case .regular: IterFont.headline; case .large: IterFont.scoreLarge }
    }
    static func timeFont(_ v: Variant) -> Font {
        switch v { case .compact, .pin: IterFont.timeSmall; case .regular: IterFont.time; case .large: IterFont.headline.weight(.medium) }
    }

    // MARK: Measured widths

    /// The width of one whole unit of the variant and time style: the symbol-and-number lane and the time lane, both fixed, so every unit
    /// of a variant and style is as wide as the widest it can be and stacks align perfectly.
    static func unitWidth(_ variant: Variant, timeStyle: TimeStyle) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        return laneWidth(v) + tailWidth(v, timeStyle)
    }

    /// The head: the widest "100" and a symbol, with the variant's padding either side. The symbol's width is taken
    /// as its point size times 1.25 (SF Symbols are wider than tall; this covers the widest window symbol).
    static func laneWidth(_ variant: Variant) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        let number = ceil(measure("100", font: numberNSFont(v)))
        return ceil(padding(v) * 2 + symbolSize(v) * 1.25 + IterEvent.gap + number)
    }

    /// The tail: the widest time of the style, with the variant's padding either side.
    static func tailWidth(_ variant: Variant, _ style: TimeStyle) -> CGFloat {
        let v = variant == .pin ? .compact : variant
        return padding(v) * 2 + timeLaneWidth(style, variant: v)
    }

    /// The widest time label of the style that the current locale and clock format can produce, sampled at :58 past
    /// every hour, in the variant's time font.
    static func timeLaneWidth(_ style: TimeStyle, variant: Variant) -> CGFloat {
        let font: NSFont
        switch variant {
        case .compact, .pin:
            font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
        case .regular:
            font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        case .large:
            font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .headline).pointSize, weight: .medium)
        }
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

    /// AppKit has no `.largeTitle` style on every OS we measure on, so the large number is measured at the larger of
    /// `.title1` and 26 pt (the macOS largeTitle size); measured values only need to be at least as wide as drawn ones.
    private static func numberNSFont(_ v: Variant) -> NSFont {
        let style: NSFont.TextStyle
        switch v { case .compact, .pin: style = .caption1; case .regular: style = .headline; case .large: style = .title1 }
        let size = NSFont.preferredFont(forTextStyle: style).pointSize
        return NSFont.monospacedDigitSystemFont(ofSize: v == .large ? max(size, 26) : size, weight: .semibold)
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
