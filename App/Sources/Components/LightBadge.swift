import SwiftUI
import IterCore
import IterDesign

/// The Light Index as shown everywhere: the window's symbol beside the number (its name is the tooltip and the
/// VoiceOver label), the band word and the confidence. Without a score the slot stays empty, or shows a spinner
/// while the forecast loads; a screen's weather banner says why (plan 2.3, 6.4-A).
struct LightBadge: View {
    enum Style { case compact, regular, large }

    let window: LightWindow
    var style: Style = .regular
    /// Show "Sample data" beside a score made from sample weather. Off by default for rows and pins: lists say it
    /// once in their header (and the sidebar banner says it on every screen), so it does not repeat on every row.
    var showsSource = false
    /// The forecast for this place is being fetched: an unscored window shows a spinner in the score slot.
    var isLoading = false
    /// Show the window's full name beside its symbol (the spot page's rows); elsewhere the symbol stands alone.
    var showsName = false

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.accessibilityDescription(window))
    }

    @ViewBuilder private var content: some View {
        switch window.assessment {
        case .scored(let score):
            scored(score)
        case .noForecast:
            unscored
        }
    }

    @ViewBuilder private var nameLabel: some View {
        if showsName {
            HStack(spacing: IterSpace.xs) {
                WindowSymbol(kind: window.kind)
                Text(LightText.name(window.kind))
                    .font(IterFont.bodyEmphasis)
                    .foregroundStyle(IterColor.textPrimary)
            }
        } else {
            WindowSymbol(kind: window.kind)
        }
    }

    @ViewBuilder private func scored(_ score: LightScore) -> some View {
        switch style {
        case .compact:
            HStack(spacing: IterSpace.xs) {
                WindowSymbol(kind: window.kind)
                ScoreChip(score: score, size: .compact)
            }
        case .regular:
            HStack(spacing: IterSpace.sm) {
                nameLabel
                ScoreChip(score: score, size: .regular)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: IterSpace.xs) {
                        Text(LightText.name(score.band))
                        ConfidenceMark(confidence: score.confidence)
                        if showsSource, score.source == .sample { SampleDataLabel(style: .inline) }
                    }
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                }
            }
        case .large:
            HStack(alignment: .center, spacing: IterSpace.md) {
                ScoreChip(score: score, size: .large)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(LightText.headline(window)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    HStack(spacing: IterSpace.xs) {
                        Text(LightText.name(score.band))
                        if let range = LightText.range(score) {
                            Text(verbatim: "·")
                            Text("Likely \(range)", comment: "Score range for days further out")
                        }
                    }
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                    HStack(spacing: IterSpace.xs) {
                        ConfidenceMark(confidence: score.confidence)
                        Text(LightText.name(score.confidence))
                        if showsSource, score.source == .sample { SampleDataLabel(style: .inline) }
                    }
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                }
            }
        }
    }

    /// No score: the symbol and an empty slot (a spinner while loading). No ring, no words.
    @ViewBuilder private var unscored: some View {
        switch style {
        case .compact:
            HStack(spacing: IterSpace.xs) {
                WindowSymbol(kind: window.kind)
                scoreSlot(width: IterSize.badgeHeightCompact, height: IterSize.badgeHeightCompact)
            }
        case .regular:
            HStack(spacing: IterSpace.sm) {
                nameLabel
                scoreSlot(width: IterSize.badgeMinWidth, height: IterSize.badgeHeight)
            }
        case .large:
            HStack(alignment: .center, spacing: IterSpace.md) {
                scoreSlot(width: IterSize.lightRingLarge, height: IterSize.lightRingLarge)
                Text(LightText.headline(window)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
            }
        }
    }

    @ViewBuilder private func scoreSlot(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if isLoading { ProgressView().controlSize(.small) }
        }
        .frame(width: width, height: height)
    }
}

/// The number on its ramp fill. The ramp is one hue, ordered by lightness; the fill carries a hairline so pale
/// bands still read against the window.
struct ScoreChip: View {
    enum Size { case compact, regular, large }
    let score: LightScore
    var size: Size = .regular

    var body: some View {
        Text(score.value, format: .number)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(IterColor.rampText(score.band))
            .frame(minWidth: width, minHeight: height)
            .padding(.horizontal, size == .large ? 0 : IterSpace.xs)
            .background(IterColor.ramp(score.band), in: shape)
            .overlay(shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .opacity(score.confidence == .low ? 0.85 : 1)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: size == .large ? IterRadius.card : IterRadius.badge, style: .continuous)
    }
    private var font: Font {
        switch size { case .compact: IterFont.scoreBadge; case .regular: IterFont.scoreMedium; case .large: IterFont.scoreLarge }
    }
    private var height: CGFloat {
        switch size { case .compact: IterSize.badgeHeightCompact; case .regular: IterSize.badgeHeight; case .large: IterSize.lightRingLarge }
    }
    private var width: CGFloat {
        switch size { case .compact: IterSize.badgeHeightCompact; case .regular: IterSize.badgeMinWidth; case .large: IterSize.lightRingLarge }
    }
}

/// Three small bars: how far to trust the score.
struct ConfidenceMark: View {
    let confidence: Confidence

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

/// A window's one-line light for a list row: symbol, score chip (or an empty slot) and its start time in the
/// spot's own zone. The symbol carries the name, so no "Tomorrow" or window word is needed.
struct WindowLightLine: View {
    let window: LightWindow
    let zone: TimeZone
    var isLoading = false
    /// For VoiceOver and the tooltip only: the window falls on tomorrow.
    var isTomorrow = false

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            LightBadge(window: window, style: .compact, isLoading: isLoading)
            Text(TimeText.time(window.span.start, in: zone))
                .font(IterFont.caption)
                .monospacedDigit()
                .foregroundStyle(IterColor.textSecondary)
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        let base = LightText.accessibilityDescription(window)
        let time = TimeText.time(window.span.start, in: zone)
        if isTomorrow {
            return String(localized: "\(base), tomorrow at \(time)", comment: "VoiceOver: a window tomorrow, with its start time")
        }
        return String(localized: "\(base), \(time)", comment: "VoiceOver: a window with its start time")
    }
}
