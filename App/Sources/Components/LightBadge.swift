import SwiftUI
import IterCore
import IterDesign

/// The Light Index as shown everywhere: the window name always beside the number ("Sunset · 38"), the band word,
/// the confidence, and a hollow dashed ring instead of a number when there is no forecast (plan 2.3, 6.4-A).
struct LightBadge: View {
    enum Style { case compact, regular, large }

    let window: LightWindow
    var style: Style = .regular
    /// Show "Sample data" beside a score made from sample weather. Off by default for rows and pins: lists say it
    /// once in their header (and the sidebar banner says it on every screen), so it does not repeat on every row.
    var showsSource = false

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.accessibilityDescription(window))
    }

    @ViewBuilder private var content: some View {
        switch window.assessment {
        case .scored(let score):
            scored(score)
        case .noForecast(let reason):
            noForecast(reason)
        }
    }

    @ViewBuilder private func scored(_ score: LightScore) -> some View {
        switch style {
        case .compact:
            HStack(spacing: IterSpace.xs) {
                ScoreChip(score: score, size: .compact)
                Text(LightText.shortName(window.kind)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        case .regular:
            HStack(spacing: IterSpace.sm) {
                ScoreChip(score: score, size: .regular)
                VStack(alignment: .leading, spacing: 0) {
                    Text(LightText.name(window.kind)).font(IterFont.subheadline).foregroundStyle(IterColor.textPrimary)
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

    @ViewBuilder private func noForecast(_ reason: ForecastUnavailableReason) -> some View {
        switch style {
        case .compact:
            HStack(spacing: IterSpace.xs) {
                NoForecastRing(diameter: IterSize.badgeHeightCompact)
                Text(LightText.shortName(window.kind)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        case .regular:
            HStack(spacing: IterSpace.sm) {
                NoForecastRing(diameter: IterSize.badgeHeight)
                VStack(alignment: .leading, spacing: 0) {
                    Text(LightText.name(window.kind)).font(IterFont.subheadline).foregroundStyle(IterColor.textPrimary)
                    Text(LightText.noForecast).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                }
            }
        case .large:
            HStack(alignment: .center, spacing: IterSpace.md) {
                NoForecastRing(diameter: IterSize.lightRingLarge)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(LightText.headline(window)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    Text(LightText.noForecastReason(reason))
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

/// "No forecast": a hollow dashed ring, no colour band, no number (plan P1.2).
struct NoForecastRing: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .strokeBorder(IterColor.noForecast,
                          style: StrokeStyle(lineWidth: IterStroke.regular, dash: [IterStroke.dashLength, IterStroke.dashGap]))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// Three small bars: how far to trust the score.
struct ConfidenceMark: View {
    let confidence: Confidence

    var body: some View {
        HStack(alignment: .bottom, spacing: IterStroke.thin) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: IterStroke.thin)
                    .fill(i < filled ? IterColor.textSecondary : IterColor.separator)
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
