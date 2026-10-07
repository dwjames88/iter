import SwiftUI
import IterCore
import IterDesign

/// "What the scores mean": the five bands as swatches in the event unit's own look, the five light windows and their
/// symbols, how far to trust a score, and where the forecast comes from. Shared by the Mac sidebar popover and the iOS
/// Settings page. The band names and score ranges come from the engine (`LightBand`), the fills from the ramp tokens.
struct ScoreLegend: View {
    /// The provider behind the forecasts, for the source line. nil or sample data: no source line.
    var source: ForecastSource?

    /// The bands, worst to best, with the engine's score ranges.
    nonisolated static var bands: [(band: LightBand, range: ClosedRange<Int>)] {
        LightBand.allCases.map { ($0, $0.scoreRange) }
    }

    /// The windows in the order of a day.
    nonisolated static let windows: [LightWindowKind] = [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening, .night]

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            section(String(localized: "Colours and scores", comment: "Score legend heading")) {
                rampBar
                ForEach(Self.bands, id: \.band) { row in
                    HStack(spacing: IterSpace.md) {
                        swatch(row.band, range: row.range)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                                Text(LightText.name(row.band)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                                Text(Self.rangeText(row.range)).font(IterFont.secondary).monospacedDigit()
                                    .foregroundStyle(IterColor.textSecondary)
                            }
                            Text(Self.meaning(row.band)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            section(String(localized: "Light windows", comment: "Score legend heading")) {
                ForEach(Self.windows, id: \.self) { kind in
                    HStack(spacing: IterSpace.md) {
                        Image(systemName: LightText.symbol(kind))
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: IterEvent.symbolLarge))
                            .foregroundStyle(IterColor.textPrimary)
                            .frame(width: IterGrid.disclosureLane + IterSpace.md)
                            .accessibilityHidden(true)
                        Text(LightText.name(kind)).font(IterFont.body).foregroundStyle(IterColor.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            section(String(localized: "How sure", comment: "Score legend heading")) {
                Text("Scores further out are less certain. A score is high confidence within about 36 hours of the forecast, medium to about 72 hours, and low beyond that. It is also low for days built from a daily summary and for days past the end of the forecast, where the last forecast day's weather is carried forward. Missing forecast fields or three-hourly data lower it a step. A low-confidence score is drawn slightly faded.", comment: "Score legend: how confidence works")
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source, source != .sample {
                Text("Light Index modified from \(LightText.name(source)) forecast data.", comment: "Score legend: the forecast source")
                    .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(title).font(IterFont.moduleTitle).foregroundStyle(IterColor.textPrimary)
            content()
        }
    }

    /// A tiny event unit: the ramp fill at the band's midpoint score, with that score in ink in the unit's numeral.
    private func swatch(_ band: LightBand, range: ClosedRange<Int>) -> some View {
        let height = IterEvent.heightCompact
        let score = IterRamp.midpoint(band)
        let shape = RoundedRectangle(cornerRadius: height * IterEvent.cornerRatio, style: .continuous)
        return Text(score, format: .number)
            .font(IterFont.eventScore(size: IterEvent.scoreCompact))
            .monospacedDigit()
            .foregroundStyle(IterColor.rampText(score: score))
            .frame(width: height * 1.5, height: height)
            .background(IterColor.ramp(score: score), in: shape)
            .overlay { if IterColor.rampNeedsHairline(score: score) { shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline) } }
            .accessibilityHidden(true)
    }

    /// The whole ramp as a thin gradient bar, 0 (no light) to 100, built from the same score colours.
    private var rampBar: some View {
        let shape = RoundedRectangle(cornerRadius: IterRadius.badge, style: .continuous)
        return VStack(alignment: .leading, spacing: IterSpace.xs) {
            LinearGradient(colors: stride(from: 0, through: 100, by: 5).map { IterColor.ramp(score: $0) }, startPoint: .leading, endPoint: .trailing)
                .frame(height: IterSpace.sm)
                .clipShape(shape)
                .overlay(shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            HStack {
                Text("No light", comment: "Score legend: the low end of the colour bar").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                Spacer()
                Text("Full light", comment: "Score legend: the high end of the colour bar").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }

    static func rangeText(_ range: ClosedRange<Int>) -> String {
        String(localized: "\(range.lowerBound)–\(range.upperBound)", comment: "Score range, e.g. 74–87")
    }

    static func meaning(_ band: LightBand) -> String {
        switch band {
        case .poor: String(localized: "Flat, blocked or wet. Not worth the trip.", comment: "Score legend: Poor")
        case .fair: String(localized: "Workable, but nothing special.", comment: "Score legend: Fair")
        case .good: String(localized: "Good light for most pictures.", comment: "Score legend: Good")
        case .great: String(localized: "Strong colour and clean skies. Worth planning around.", comment: "Score legend: Great")
        case .epic: String(localized: "Rare, dramatic light. Be there.", comment: "Score legend: Epic")
        }
    }
}

/// The "i" button's content on the Mac: the legend in a scroll view sized for a popover.
struct ScoreLegendPopover: View {
    var source: ForecastSource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                Text("What the scores mean", comment: "Popover title").font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                ScoreLegend(source: source)
            }
            .padding(IterSpace.lg)
        }
        .frame(width: 340, height: 700)
    }
}
