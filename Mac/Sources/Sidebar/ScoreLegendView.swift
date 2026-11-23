import SwiftUI
import IterModel
import IterSky
import IterUI

/// "What the scores mean": the five bands on the score ramp, the five light windows and their symbols, and how sure a score is.
struct ScoreLegendView: View {
    static let windows: [LightWindowKind] = [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening, .night]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                section("Colours and Scores") {
                    ForEach(LightBand.allCases, id: \.self) { band in
                        HStack(spacing: IterSpace.md) {
                            swatch(band)
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                                    Text(Self.name(band)).font(IterFont.headline)
                                    Text(Self.rangeText(band.scoreRange)).font(IterFont.secondary).monospacedDigit()
                                        .foregroundStyle(IterColor.textSecondary)
                                }
                                Text(Self.meaning(band)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                section("Light Windows") {
                    ForEach(Self.windows, id: \.self) { kind in
                        HStack(spacing: IterSpace.md) {
                            WindowSymbol(kind: kind).frame(width: 24)
                            Text(LightText.name(kind)).font(IterFont.body)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                section("How Sure") {
                    Text("A score is most certain within about 36 hours of the forecast, less so to about 72 hours, and least beyond that. A score that leans on a daily summary, or on missing forecast fields, is less certain too, and is drawn slightly faded.")
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(title).font(IterFont.moduleTitle)
            content()
        }
    }

    private func swatch(_ band: LightBand) -> some View {
        let score = Self.midpoint(band)
        return Text(score, format: .number)
            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
            .foregroundStyle(IterColor.rampText(score: score))
            .frame(width: 44, height: 28)
            .background(IterColor.ramp(score: score), in: RoundedRectangle(cornerRadius: IterRadius.badge, style: .continuous))
            .overlay {
                if IterColor.rampNeedsHairline(score: Double(score)) {
                    RoundedRectangle(cornerRadius: IterRadius.badge, style: .continuous).strokeBorder(.separator)
                }
            }
            .accessibilityHidden(true)
    }

    static func midpoint(_ band: LightBand) -> Int { (band.scoreRange.lowerBound + band.scoreRange.upperBound) / 2 }

    static func name(_ band: LightBand) -> String {
        switch band {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .great: "Great"
        case .epic: "Epic"
        }
    }

    static func rangeText(_ range: ClosedRange<Int>) -> String { "\(range.lowerBound) to \(range.upperBound)" }

    static func meaning(_ band: LightBand) -> String {
        switch band {
        case .poor: "Heavy cloud or haze blocks the light. Look elsewhere."
        case .fair: "Some light gets through. Worth a look if you are close."
        case .good: "A pleasant window. Expect colour at the edges of the sky."
        case .great: "Clear enough, with cloud to catch the light."
        case .epic: "The sky lines up. Plan the day around it."
        }
    }
}
