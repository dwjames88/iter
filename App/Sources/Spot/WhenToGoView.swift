import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import IterCore
import IterDesign
import IterFeatures

/// The lead of the page: "when should I be here?" The best window over the days the forecast covers, then the
/// outlook strip. With no score it shows the sun times, which are always exact; the screen's banner says why.
struct WhenToGoSection: View {
    let page: SpotModel
    @Environment(\.spotDensity) private var density

    var body: some View {
        ModuleCard(title: LightText.whenToGo, symbol: "calendar") {
            VStack(alignment: .leading, spacing: IterGrid.inset) {
                lead
                OutlookStrip(page: page)
            }
        }
    }

    @ViewBuilder private var lead: some View {
        if let best = page.best {
            bestLead(best)
        } else if page.isLoadingForecast {
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text(LightText.checkingForecast).font(IterFont.body).foregroundStyle(IterColor.textSecondary)
            }
            SunTimesLine(page: page)
        } else {
            noScore
        }
    }

    /// The one strong fact: the best window as the large event unit, beside (page) or above (compact) a text column:
    /// the caption, the day, the top reason, the forecast age, and the way to open that day.
    private func bestLead(_ best: BestWindow) -> some View {
        let layout = density == .compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: IterSpace.sm))
                                         : AnyLayout(HStackLayout(alignment: .top, spacing: IterGrid.inset))
        return layout {
            EventScore(window: best.window, zone: page.timeZone, timeStyle: .range, variant: .large,
                       isLoading: page.isLoadingForecast)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(LightText.bestIn(days: page.outlookStripDays.count, intent: page.intent))
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LightText.relativeDay(best.day, today: page.today))
                    .font(IterFont.headline)
                    .monospacedDigit()
                if let top = best.window.assessment.lightScore?.contributors.first {
                    Text(LightText.sentence(top, kind: best.window.kind))
                        .font(IterFont.body)
                        .foregroundStyle(IterColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let score = best.window.assessment.lightScore {
                    Text(TimeText.updated(score.forecastFetchedAt))
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                }
                if best.day != page.day || best.window.kind != page.selectedWindow {
                    Button(LightText.showThisDay) { page.showBest() }
                        .controlSize(.small)
                        .padding(.top, IterSpace.xs)
                }
            }
            if density == .page { Spacer(minLength: 0) }
        }
    }

    private var noScore: some View {
        SunTimesLine(page: page)
    }
}

/// Next sunrise and sunset, or the polar statement. Geometry is always available.
struct SunTimesLine: View {
    let page: SpotModel

    var body: some View {
        let times = page.nextSunTimes
        switch times.kind {
        case .polarNight:
            Label(LightText.polarNight, systemImage: "moon.stars").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
        case .polarDay:
            Label(LightText.polarDay, systemImage: "sun.max").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
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
            .font(IterFont.body)
            .monospacedDigit()
        }
    }
}

// MARK: - Outlook

/// The days the forecast covers, each with the intent's headline chip (pattern #22): fainter and with a range as
/// confidence falls, an empty slot where a day has no score, "Best" on the best day.
struct OutlookStrip: View {
    let page: SpotModel
    @Environment(\.spotDensity) private var density

    var body: some View {
        let best = page.best
        let days = shownDays
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(LightText.outlookTitle(days: days.count, intent: page.intent)).font(IterFont.moduleTitle).foregroundStyle(IterColor.textSecondary)
            if density == .page {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(days, id: \.day) { light in
                        cell(light, isBest: best?.day == light.day).frame(maxWidth: .infinity)
                    }
                }
            } else {
                dayList(days, best: best)
            }
            Text(LightText.outlookKey).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
        }
    }

    // MARK: Compact list

    /// The label lane: the widest "Wed 28" plus the "Best" marker, to the next multiple of the 8 pt unit.
    private static let labelLane: CGFloat = {
        let label = NSFont.preferredFont(forTextStyle: .headline)
        let marker = NSFont.preferredFont(forTextStyle: .subheadline)
        let width = ceil(("Wed 28" as NSString).size(withAttributes: [.font: label]).width
                         + IterSpace.xs + ("Best" as NSString).size(withAttributes: [.font: marker]).width)
        return (width / IterGrid.unit).rounded(.up) * IterGrid.unit
    }()

    /// The widest range, "100–100", at the secondary text style.
    private static let rangeLane: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
        return ceil(("100–100" as NSString).size(withAttributes: [.font: font]).width)
    }()

    /// A vertical list in a narrow host, the Weather ten-day idiom on the light windows' lane grid: the day, the
    /// chip, the range at the trailing edge. Ten days never fit across 296 pt, so the days stack.
    private func dayList(_ days: [DayLight], best: BestWindow?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.day) { index, light in
                if index > 0 { Divider().padding(.leading, IterSpace.sm) }
                listRow(light, isBest: best?.day == light.day)
            }
        }
    }

    private func listRow(_ light: DayLight, isBest: Bool) -> some View {
        let window = light.headline(for: page.intent)
        let selected = light.day == page.day
        let label = light.day == page.today ? LightText.relativeDay(light.day, today: page.today)
                                            : String(localized: "\(TimeText.weekday(light.day)) \(TimeText.dayNumber(light.day))",
                                                     comment: "Outlook row: weekday and day of the month, e.g. Thu 8")
        return Button {
            page.selectDay(light.day)
        } label: {
            HStack(alignment: .center, spacing: IterGrid.laneGap) {
                HStack(spacing: IterSpace.xs) {
                    Text(label).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    if isBest {
                        Text(LightText.bestMarker).font(IterFont.moduleTitle).foregroundStyle(IterColor.accentText)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: Self.labelLane, alignment: .leading)
                chip(window)
                Spacer(minLength: 0)
                Text(caption(window).trimmingCharacters(in: .whitespaces))
                    .font(IterFont.secondary)
                    .monospacedDigit()
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
                    .frame(width: Self.rangeLane, alignment: .trailing)
            }
            .padding(.horizontal, IterSpace.sm)
            .frame(minHeight: IterGrid.rowSingle)
            .background(selected ? IterColor.selection : .clear,
                        in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(light, window: window, isBest: isBest))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The strip's days. A leading day whose window has already passed has no score to show, so the strip starts
    /// at the next day; days are never added past the forecast's horizon.
    private var shownDays: [DayLight] { page.outlookStripDays }

    private func cell(_ light: DayLight, isBest: Bool) -> some View {
        let window = light.headline(for: page.intent)
        let selected = light.day == page.day
        return Button {
            page.selectDay(light.day)
        } label: {
            VStack(spacing: 0) {
                bestBubble(isBest)
                VStack(spacing: IterSpace.xs) {
                    Text(TimeText.weekday(light.day)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                    Text(TimeText.dayNumber(light.day)).font(IterFont.headline).monospacedDigit()
                    chip(window)
                    Text(caption(window)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(minHeight: IterSpace.xl)
                }
            }
            .padding(.bottom, IterSpace.sm)
            .frame(maxWidth: .infinity)
            .background(selected ? IterColor.selection : .clear,
                        in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(light, window: window, isBest: isBest))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// "Best" on the best day, in a capsule on the cell's top edge. Every cell keeps the capsule's height, with no
    /// gap below it, so the weekdays line up.
    private func bestBubble(_ isBest: Bool) -> some View {
        Text(isBest ? LightText.bestMarker : " ")
            .font(IterFont.moduleTitle)
            .foregroundStyle(IterColor.onAccent)
            .padding(.horizontal, IterSpace.xs)
            .background(isBest ? AnyShapeStyle(IterColor.accentEmphasis) : AnyShapeStyle(.clear), in: Capsule())
    }

    @ViewBuilder private func chip(_ window: LightWindow?) -> some View {
        if let window {
            EventScore(window: window, zone: page.timeZone, timeStyle: .start, variant: .compact, isLoading: page.isLoadingForecast)
        } else {
            ZStack {
                if page.isLoadingForecast { ProgressView().controlSize(.small) }
            }
            .frame(width: EventScore.unitWidth(.compact, timeStyle: .start), height: IterEvent.heightCompact)
        }
    }

    private func caption(_ window: LightWindow?) -> String {
        guard let window else { return String(localized: "No window", comment: "Outlook cell when the sun gives no such window") }
        switch window.assessment {
        case .scored(let score): return LightText.range(score) ?? " "
        case .noForecast: return " "
        }
    }

    private func accessibilityLabel(_ light: DayLight, window: LightWindow?, isBest: Bool) -> String {
        var parts = [TimeText.longDay(light.day)]
        if let window { parts.append(LightText.accessibilityDescription(window)) }
        if isBest { parts.append(LightText.bestMarker) }
        return parts.joined(separator: ", ")
    }
}

extension SpotModel {
    /// The outlook strip's days. A leading day whose window has already passed has no score to show, so the strip
    /// starts at the next day; days are never added past the forecast's horizon. The "Best … in the next N days"
    /// caption counts the same days.
    var outlookStripDays: [DayLight] {
        var days = stripDays
        if let first = days.first, days.count > 1, first.day == today,
           case .noForecast(.inThePast)? = first.headline(for: intent)?.assessment {
            days.removeFirst()
        }
        return days
    }
}
