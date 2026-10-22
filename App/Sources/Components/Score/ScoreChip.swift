#if canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif
import SwiftUI
import Synchronization
import IterCore
import IterDesign
import IterFeatures

/// How the time inside an event unit reads.
enum TimeStyle: Hashable, Sendable {
    /// "18:09"
    case start
    /// "18:09–18:43"
    case range
}

/// The score chip: a light window's symbol, time and score as ONE continuous rounded rectangle in one fill.
///
/// A scored chip is filled with the ramp colour of its score (`IterColor.ramp(score:)`: white at 0, "no light", up to
/// the deepest orange at 100; corner radius fixed per size). On the left a leading-aligned column: the window's
/// symbol above its time; on the right the score as a semibold monospaced-digit numeral. Symbol, time and score share
/// one ink (`IterColor.rampText(score:)`: ink in light mode up to the switch score, white above it; cream in dark
/// mode). Scores below `event/hairlineBelowScore` get a hairline, since their fill is too close to the ground. The chip
/// hugs its content; lists that stack chips reserve a lane of `maxWidth(size:timeStyle:)` and trail-align the chip in
/// it. A window without a score is the same size and layout without the numeral: no fill, a hairline outline, the
/// symbol in its standalone colour (and a mini spinner beside it while the forecast loads). Sizes are fixed points
/// from the `event/*` tokens, not Dynamic Type: the chip is a fixed-height badge. The `pin` size is the compact chip
/// over the map, with a pointer, a shadow and a selected scale.
struct ScoreChip: View {
    enum Size: Sendable, CaseIterable { case compact, small, large, pin }

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
    var size: Size = .small
    /// The forecast is being fetched: an unscored window shows a small spinner beside its symbol.
    var isLoading = false
    /// For VoiceOver and the tooltip only: the window falls on tomorrow.
    var isTomorrow = false
    /// Pin only.
    var isSelected = false
    /// VoiceOver's description of the window, before the time.
    private let spokenBase: String


    init(window: LightWindow, zone: TimeZone, timeStyle: TimeStyle = .start, size: Size = .small,
         isLoading: Bool = false, isTomorrow: Bool = false, isSelected: Bool = false) {
        self.kind = window.kind
        self.span = window.span
        self.score = window.assessment.lightScore.map { Mark(value: $0.value, band: $0.band, confidence: $0.confidence) }
        self.spokenBase = LightText.accessibilityDescription(window)
        self.zone = zone
        self.timeStyle = timeStyle
        self.size = size
        self.isLoading = isLoading
        self.isTomorrow = isTomorrow
        self.isSelected = isSelected
    }

    /// The unscored form, for a place that knows only a window's kind and start (a trip's next session).
    init(kind: LightWindowKind, start: Date, zone: TimeZone, size: Size = .compact, isTomorrow: Bool = false) {
        self.init(window: LightWindow(kind: kind, span: TimeSpan(start: start, end: start), assessment: .noForecast(.beyondHorizon)),
                  zone: zone, timeStyle: .start, size: size, isTomorrow: isTomorrow)
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
        self.size = .pin
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
        if size == .pin {
            pin
        } else {
            chip
        }
    }

    // MARK: Chip

    private var chipSize: Size { size == .pin ? .compact : size }

    private var chip: some View {
        let s = chipSize
        let height = Self.height(s)
        let shape = RoundedRectangle(cornerRadius: Self.radius(s), style: .continuous)
        return HStack(spacing: Self.gap(s)) {
            column(color: score.map { IterColor.rampText(score: $0.value) } ?? IterColor.textPrimary.color)
            if let score {
                Text(score.value, format: .number)
                    .font(IterFont.eventScore(size: Self.scoreSize(s)))
                    .monospacedDigit()
                    .foregroundStyle(IterColor.rampText(score: score.value))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Self.padding(s))
        .padding(.vertical, Self.paddingV(s))
        .frame(height: height)
        .background(chipFill, in: shape)
        .overlay {
            if score.map({ IterColor.rampNeedsHairline(score: $0.value) }) ?? true {
                shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline)
            }
        }
        .opacity(score?.confidence == .low ? IterEvent.lowConfidenceOpacity : 1)
    }

    /// The symbol above the time, leading-aligned. A scored chip draws both in one colour (ink); an unscored one
    /// draws the symbol in its standalone colour and a spinner beside it while loading.
    private func column(color: Color) -> some View {
        let s = chipSize
        return VStack(alignment: .leading, spacing: 0) {
            if score != nil {
                Image(systemName: LightText.symbol(kind))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: Self.timeSize(s), weight: .semibold))
                    .foregroundStyle(color)
            } else {
                HStack(spacing: IterSpace.xs) {
                    WindowSymbol(kind: kind, font: .system(size: Self.timeSize(s), weight: .semibold))
                    if isLoading { ProgressView().controlSize(.mini) }
                }
            }
            Text(timeString)
                .font(IterFont.eventTime(size: Self.timeSize(s)))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The one fill: the score's ramp colour; none when unscored (a pin gets the solid content colour).
    private var chipFill: AnyShapeStyle {
        if let score { return AnyShapeStyle(IterColor.ramp(score: score.value)) }
        return size == .pin ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(Color.clear)
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
            chip
            PinPointer()
                .fill(chipFill)
                .frame(width: IterSpace.sm, height: IterSpace.xs)
        }
        .shadow(radius: isSelected ? IterEvent.pinShadowRadiusSelected : IterEvent.pinShadowRadius, y: 1)
        .scaleEffect(isSelected ? IterEvent.pinScaleSelected : 1, anchor: .bottom)
        .animation(.spring, value: isSelected)
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

    private static func pick(_ v: Size, _ compact: CGFloat, _ small: CGFloat, _ large: CGFloat) -> CGFloat {
        switch v { case .compact, .pin: compact; case .small: small; case .large: large }
    }
    static func height(_ v: Size) -> CGFloat { pick(v, IterEvent.heightCompact, IterEvent.heightSmall, IterEvent.heightLarge) }
    static func radius(_ v: Size) -> CGFloat { pick(v, IterEvent.radiusCompact, IterEvent.radiusSmall, IterEvent.radiusLarge) }
    static func scoreSize(_ v: Size) -> CGFloat { pick(v, IterEvent.scoreCompact, IterEvent.scoreSmall, IterEvent.scoreLarge) }
    /// The time and the window symbol share one point size.
    static func timeSize(_ v: Size) -> CGFloat { pick(v, IterEvent.timeCompact, IterEvent.timeSmall, IterEvent.timeLarge) }
    static func gap(_ v: Size) -> CGFloat { pick(v, IterEvent.gapCompact, IterEvent.gapSmall, IterEvent.gapLarge) }
    static func padding(_ v: Size) -> CGFloat { pick(v, IterEvent.paddingCompact, IterEvent.paddingSmall, IterEvent.paddingLarge) }
    static func paddingV(_ v: Size) -> CGFloat { pick(v, IterEvent.paddingVCompact, IterEvent.paddingVSmall, IterEvent.paddingVLarge) }

    // MARK: Lane width

    /// The widest a scored chip of this size gets with this time style: padding, the symbol-and-time column, the gap
    /// and the numeral "100". Lists that stack chips (Explore rows, the layout grid, day windows) reserve this as a
    /// lane and trail-align each chip in it, so the lanes line up although the chips hug their content.
    static func maxWidth(size: Size, timeStyle: TimeStyle) -> CGFloat {
        let s = size == .pin ? .compact : size
        let key = WidthKey(size: s, style: timeStyle, locale: "\(Locale.current.identifier)|\(Locale.current.hourCycle)")
        if let hit = widths.withLock({ $0[key] }) { return hit }
        let numeral = measure("100", font: .monospacedDigitSystemFont(ofSize: scoreSize(s), weight: weight(IterFont.eventScoreWeight())))
        let column = max(ceil(timeSize(s) * 1.25), timeLaneWidth(timeStyle, size: s))
        let width = ceil(padding(s) * 2 + column + gap(s) + numeral)
        widths.withLock { $0[key] = width }
        return width
    }

    private struct WidthKey: Hashable {
        var size: Size
        var style: TimeStyle
        var locale: String
    }
    private static let widths = Mutex<[WidthKey: CGFloat]>([:])

    /// The widest time label of the style that the current locale and clock format can produce, sampled at :58 past
    /// every hour, in the size's time font. A `.range` is one line, "05:45–06:20", in the time slot.
    private static func timeLaneWidth(_ style: TimeStyle, size: Size) -> CGFloat {
        let font = PlatformFont.monospacedDigitSystemFont(ofSize: timeSize(size), weight: weight(IterFont.eventTimeWeight()))
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

    private static func weight(_ w: FontWeightName) -> PlatformFont.Weight {
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

    private static func measure(_ string: String, font: PlatformFont) -> CGFloat {
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

// MARK: Previews

private struct ScoreChipGrid: View {
    static let zone = TimeZone(identifier: "UTC")!
    static let sizes: [ScoreChip.Size] = [.large, .small, .compact]

    static func window(_ score: Int?) -> LightWindow {
        let start = LocalDay(year: 2026, month: 10, day: 6).at(hour: 6, minute: 55, in: zone)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(35 * 60))
        guard let score else { return LightWindow(kind: .goldenMorning, span: span, assessment: .noForecast(.beyondHorizon)) }
        let s = LightScore(value: score, band: LightBand(score: score), confidence: .high, range: score...score, contributors: [],
                           source: .sample, forecastFetchedAt: start, leadHours: 12)
        return LightWindow(kind: .goldenMorning, span: span, assessment: .scored(s))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            ForEach(Self.sizes, id: \.self) { size in
                HStack(alignment: .top, spacing: IterSpace.lg) {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { ScoreChip(window: Self.window($0), zone: Self.zone, size: size) }
                    ScoreChip(window: Self.window(nil), zone: Self.zone, size: size)
                }
            }
        }
        .padding(IterSpace.xl)
        .background(IterColor.backgroundWindow)
    }
}

#Preview("Score chip, light") { ScoreChipGrid().preferredColorScheme(.light) }
#Preview("Score chip, dark") { ScoreChipGrid().preferredColorScheme(.dark) }
#Preview("Pin and range") {
    HStack(spacing: IterSpace.lg) {
        ScoreChip(window: ScoreChipGrid.window(88), zone: ScoreChipGrid.zone, size: .pin)
        ScoreChip(window: ScoreChipGrid.window(88), zone: ScoreChipGrid.zone, timeStyle: .range, size: .small)
    }
    .padding(IterSpace.xl)
    .background(IterColor.backgroundWindow)
}
