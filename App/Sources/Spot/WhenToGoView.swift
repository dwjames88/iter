import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The lead of the page: "when should I be here?" The best window over the next ten days for the chosen intent,
/// then the outlook strip. With no score it says why and shows the sun times, which are always exact.
struct WhenToGoSection: View {
    let page: SpotModel
    @Environment(\.spotDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            let layout = density == .compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: IterSpace.sm))
                                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                SpotSectionTitle(LightText.whenToGo)
                if density == .page { Spacer() }
                Picker(selection: Binding(get: { page.intent }, set: { page.selectIntent($0) })) {
                    ForEach(LightIntent.allCases) { intent in
                        Label(LightText.name(intent), systemImage: LightText.symbol(intent)).tag(intent)
                    }
                } label: { Text("Shoot", comment: "Intent picker label on the spot page") }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(String(localized: "Which light to plan for. Scores on this page follow this choice.", comment: "Help"))
            }
            SpotCard { lead }
            OutlookStrip(page: page)
        }
    }

    @ViewBuilder private var lead: some View {
        if let best = page.best {
            bestLead(best)
        } else if page.isLoadingForecast {
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text(LightText.checkingForecast).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
            }
            SunTimesLine(page: page)
        } else {
            noScore
        }
    }

    private func bestLead(_ best: BestWindow) -> some View {
        let layout = density == .compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: IterSpace.md))
                                         : AnyLayout(HStackLayout(alignment: .top, spacing: IterSpace.lg))
        return layout {
            LightBadge(window: best.window, style: .large)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(LightText.bestIn(days: SpotModel.outlookDays, intent: page.intent))
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if density == .compact {
                    Text(LightText.relativeDay(best.day, today: page.today)).font(IterFont.headline)
                    Text(TimeText.timeRange(best.window.span, in: page.timeZone)).font(IterFont.headline).monospacedDigit()
                } else {
                    Text("\(LightText.relativeDay(best.day, today: page.today)) · \(TimeText.timeRange(best.window.span, in: page.timeZone))")
                        .font(IterFont.headline)
                        .monospacedDigit()
                }
                if let score = best.window.assessment.lightScore {
                    if let top = score.contributors.first {
                        Text(LightText.sentence(top, kind: best.window.kind))
                            .font(IterFont.callout)
                            .foregroundStyle(IterColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(TimeText.updated(score.forecastFetchedAt))
                        .font(IterFont.footnote)
                        .foregroundStyle(IterColor.textSecondary)
                }
                if best.day != page.day || best.window.kind != page.selectedWindow {
                    Button(LightText.showThisDay) { page.showBest() }
                        .controlSize(.small)
                }
            }
            if density == .page { Spacer(minLength: 0) }
        }
    }

    private var noScore: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .top, spacing: IterSpace.md) {
                NoForecastRing(diameter: IterSize.lightRingLarge)
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    Text(LightText.noScoredWindow(intent: page.intent, days: SpotModel.outlookDays))
                        .font(IterFont.headline)
                    if let reason = page.unavailableReason {
                        Text(LightText.noForecastReason(reason))
                            .font(IterFont.callout)
                            .foregroundStyle(IterColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let reason = page.unavailableReason, LightText.canRetry(reason) {
                        Button { page.retry() } label: { Label(LightText.retry, systemImage: "arrow.clockwise") }
                            .controlSize(.small)
                            .keyboardShortcut("r", modifiers: [.command, .option])
                    }
                }
                Spacer(minLength: 0)
            }
            Divider()
            SunTimesLine(page: page)
        }
    }
}

/// Next sunrise and sunset, or the polar statement. Geometry is always available.
struct SunTimesLine: View {
    let page: SpotModel

    var body: some View {
        let times = page.nextSunTimes
        switch times.kind {
        case .polarNight:
            Label(LightText.polarNight, systemImage: "moon.stars").font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
        case .polarDay:
            Label(LightText.polarDay, systemImage: "sun.max").font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
        case .normal:
            HStack(spacing: IterSpace.lg) {
                if let rise = times.sunrise {
                    Label(LightText.nextSunrise(LightText.sunTime(rise, in: page.timeZone, today: page.today)), systemImage: "sunrise")
                }
                if let set = times.sunset {
                    Label(LightText.nextSunset(LightText.sunTime(set, in: page.timeZone, today: page.today)), systemImage: "sunset")
                }
                Spacer(minLength: 0)
            }
            .font(IterFont.callout)
            .monospacedDigit()
        }
    }
}

// MARK: - Outlook

/// Ten days, each with the chosen intent's headline chip (pattern #22): fainter and with a range as confidence
/// falls, a dashed ring where there is no forecast, "Best" on the best day.
struct OutlookStrip: View {
    let page: SpotModel
    @Environment(\.spotDensity) private var density

    var body: some View {
        let best = page.best
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(LightText.outlookTitle(intent: page.intent)).font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
            HStack(alignment: .top, spacing: IterSpace.xs) {
                ForEach(page.stripDays, id: \.day) { light in
                    cell(light, isBest: best?.day == light.day)
                }
            }
            Text(LightText.outlookKey).font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
        }
    }

    private func cell(_ light: DayLight, isBest: Bool) -> some View {
        let window = light.headline(for: page.intent)
        let selected = light.day == page.day
        let score = window?.assessment.lightScore
        return Button {
            page.selectDay(light.day)
        } label: {
            VStack(spacing: IterSpace.xxs) {
                bestBubble(isBest)
                Text(TimeText.weekday(light.day)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                Text(TimeText.dayNumber(light.day)).font(IterFont.bodyEmphasis).monospacedDigit()
                chip(window)
                if density == .page {
                    Text(caption(window)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(minHeight: IterSpace.xl)
                }
            }
            .padding(.vertical, IterSpace.xs)
            .frame(maxWidth: .infinity)
            .opacity(fade(score))
            .background(selected ? IterColor.selection : .clear,
                        in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
                .strokeBorder(selected ? IterColor.accent : .clear, lineWidth: IterStroke.regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(light, window: window, isBest: isBest))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// "Best" on the best day; in a narrow host a star, since ten cells leave no room for the word.
    @ViewBuilder private func bestBubble(_ isBest: Bool) -> some View {
        if density == .compact {
            Image(systemName: isBest ? "star.fill" : "star")
                .font(IterFont.captionStrong)
                .foregroundStyle(isBest ? IterColor.accentText : IterColor.textTertiary.color)
                .opacity(isBest ? 1 : 0)
        } else {
            Text(isBest ? LightText.bestMarker : " ")
                .font(IterFont.captionStrong)
                .foregroundStyle(IterColor.onAccent)
                .padding(.horizontal, IterSpace.xs)
                .background(isBest ? AnyShapeStyle(IterColor.accentEmphasis) : AnyShapeStyle(.clear), in: Capsule())
        }
    }

    @ViewBuilder private func chip(_ window: LightWindow?) -> some View {
        if let score = window?.assessment.lightScore {
            ScoreChip(score: score, size: density == .compact ? .compact : .regular)
        } else {
            NoForecastRing(diameter: density == .compact ? IterSize.badgeHeightCompact : IterSize.badgeHeight)
        }
    }

    private func caption(_ window: LightWindow?) -> String {
        guard let window else { return String(localized: "No window", comment: "Outlook cell when the sun gives no such window") }
        switch window.assessment {
        case .scored(let score): return LightText.range(score) ?? " "
        case .noForecast(let reason): return LightText.noForecastShort(reason)
        }
    }

    private func fade(_ score: LightScore?) -> Double {
        switch score?.confidence {
        case .low: SpotLayout.fadeLow
        case .medium: SpotLayout.fadeMedium
        default: 1
        }
    }

    private func accessibilityLabel(_ light: DayLight, window: LightWindow?, isBest: Bool) -> String {
        var parts = [TimeText.longDay(light.day)]
        if let window { parts.append(LightText.accessibilityDescription(window)) }
        if isBest { parts.append(LightText.bestMarker) }
        return parts.joined(separator: ", ")
    }
}
