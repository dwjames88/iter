import SwiftUI
import IterModel
import IterGoActivity
import IterUI

/// "Conditions at <next stop>": the Live Sky Index with what it rests on, current weather here and at the stop, the
/// next hours, and the sources (military-origin data marked). Content cards, no glass. Nothing when there is no stop.
public struct GoConditionsSection: View {
    public let snapshot: GoSnapshot
    public let now: Date

    @Environment(\.locale) private var locale

    public init(snapshot: GoSnapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    private var stop: GoStopInfo? { GoText.subjectStop(snapshot) }

    public var body: some View {
        if stop != nil {
            VStack(alignment: .leading, spacing: IterSpace.md) {
                Text(verbatim: GoText.conditionsTitle(snapshot, locale: locale))
                    .font(IterFont.titleSection)
                    .foregroundStyle(IterColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                skyCard
                if !snapshot.weather.isEmpty { weatherCard }
                if !GoText.hourColumns(snapshot, locale: locale).isEmpty { hoursCard }
                if let sources = snapshot.sourceDetails, !sources.isEmpty { sourcesCard(sources) }
            }
        }
    }

    // MARK: Sky

    @ViewBuilder private var skyCard: some View {
        let sky = snapshot.sky
        let score = sky?.displayScore
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.md) {
                if let kind = sky?.windowKind ?? stop?.windowKind {
                    ScoreChip(kind: kind, start: sky?.windowStart ?? stop?.windowStart ?? now, score: score, zone: GoText.zone(for: stop),
                              locale: locale, size: .large, isLowConfidence: sky?.confidence == .low)
                }
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    Text(verbatim: sky.map { GoText.skyTitle($0, locale: locale) } ?? String(localized: "Live Sky Index"))
                        .font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                    if let score, let sky {
                        Text(verbatim: bandLine(sky, score: score)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                        ConfidenceIndicator(level(sky.confidence), locale: locale)
                        if let t = trendLabel(sky.trend) { t }
                    } else {
                        Label { Text("No live data") } icon: { Image(systemName: "circle.dashed") }
                            .font(IterFont.headline).foregroundStyle(IterColor.textSecondary)
                    }
                    if let sky, let f = GoText.forecastBeside(sky, locale: locale) {
                        Text(verbatim: f).font(IterFont.callout).foregroundStyle(IterColor.textSecondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            Text(verbatim: GoText.skyBasis(snapshot, now: now, locale: locale))
                .font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .goCard()
        .accessibilityElement(children: .combine)
    }

    private func bandLine(_ sky: GoSkyInfo, score: Int) -> String {
        let name = sky.windowKind.map { LightText.name($0) }
        let band = sky.band.map { GoText.bandWord($0, locale: locale) }
        return [band, name].compactMap { $0 }.joined(separator: " · ")
    }

    private func level(_ c: GoConfidence) -> ConfidenceLevel {
        switch c { case .low: .low; case .medium: .medium; case .high: .high }
    }

    private func trendLabel(_ t: GoTrend) -> Label<Text, Image>? {
        guard let word = GoText.trendWord(t, locale: locale), let sym = GoText.trendSymbol(t) else { return nil }
        return Label { Text(verbatim: word) } icon: { Image(systemName: sym) }
    }

    // MARK: Weather

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            ForEach(Array(snapshot.weather.enumerated()), id: \.offset) { index, w in
                if index > 0 { Divider() }
                weatherRow(w)
            }
        }
        .goCard()
        .accessibilityElement(children: .combine)
    }

    private func weatherRow(_ w: GoWeatherInfo) -> some View {
        let f = GoText.facts(w, locale: locale)
        return VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(verbatim: GoText.weatherSubject(w, in: snapshot, locale: locale)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
            HStack(alignment: .top, spacing: IterSpace.xs) {
                fact("thermometer.medium", f.temperature, "Temp")
                fact("cloud", f.cloud, "Cloud")
                fact("wind", f.wind, "Wind")
                fact("eye", f.visibility, "Visibility")
                fact("drop", f.precip, "Rain")
            }
            Text(verbatim: GoText.weatherSource(w, now: now, locale: locale)).font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
        }
    }

    private func fact(_ symbol: String, _ value: String?, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: IterSpace.xxs) {
            Image(systemName: symbol).font(IterFont.callout).foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
            Text(verbatim: value ?? "–").font(IterFont.bodyEmphasis).foregroundStyle(IterColor.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(IterFont.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Hours

    private var hoursCard: some View {
        let cols = GoText.hourColumns(snapshot, locale: locale)
        return VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .top, spacing: IterSpace.xxs) {
                ForEach(cols) { c in hourColumn(c) }
            }
            HStack(spacing: IterSpace.xs) {
                if let kind = stop?.windowKind, cols.contains(where: \.inWindow) {
                    WindowSymbol(kind: kind, font: IterFont.caption)
                    Text(verbatim: LightText.name(kind)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    Text(verbatim: "·").font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
                }
                if let note = GoText.hourBasisNote(snapshot, locale: locale) {
                    Text(verbatim: note).font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
                }
            }
        }
        .goCard()
        .accessibilityElement(children: .combine)
    }

    private func hourColumn(_ c: GoText.HourColumn) -> some View {
        VStack(spacing: IterSpace.xs) {
            Text(verbatim: c.label).font(IterFont.captionStrong).foregroundStyle(IterColor.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            if c.inWindow, let kind = stop?.windowKind {
                WindowSymbol(kind: kind, font: IterFont.caption)
            } else {
                Color.clear.frame(width: 1, height: IterSize.iconSmall)
            }
            HStack(spacing: 2) {
                Image(systemName: "cloud").accessibilityHidden(true)
                Text(verbatim: c.cloud).monospacedDigit()
            }
            HStack(spacing: 2) {
                Image(systemName: "drop").accessibilityHidden(true)
                Text(verbatim: c.precip).monospacedDigit()
            }
            Text(verbatim: c.temperature).monospacedDigit().foregroundStyle(IterColor.textPrimary)
        }
        .font(IterFont.caption)
        .foregroundStyle(IterColor.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .padding(.vertical, IterSpace.xs)
        .background(c.inWindow ? IterColor.selection : Color.clear, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
    }

    // MARK: Sources

    private func sourcesCard(_ sources: [GoSourceInfo]) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            Text("Sources").font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
            ForEach(Array(sources.enumerated()), id: \.offset) { _, src in
                sourceRow(GoText.sourceWords(src, now: now, zone: GoText.zone(for: stop), locale: locale))
            }
        }
        .goCard()
    }

    private func sourceRow(_ w: GoText.SourceWords) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                if w.isStale {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning).accessibilityHidden(true)
                }
                Text(verbatim: w.primary).foregroundStyle(w.isStale ? IterColor.warning : IterColor.textSecondary.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                if w.isMilitary { Image(systemName: "shield.lefthalf.filled").accessibilityHidden(true) }
                Text(verbatim: w.tier)
            }
            .foregroundStyle(IterColor.textTertiary)
        }
        .font(IterFont.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
