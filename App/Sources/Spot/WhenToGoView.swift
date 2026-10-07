import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import IterCore
import IterDesign
import IterFeatures

/// "When should I be here?" The best window over the days the forecast covers, as the first line of Good to know
/// (SpotFactsSection draws it inside that card). With no score it shows the sun times, which are always exact; the
/// screen's banner says why.
struct BestWindowLead: View {
    let page: SpotModel
    @Environment(\.spotDensity) private var density

    var body: some View { lead }

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
        let layout = density == .panel ? AnyLayout(VStackLayout(alignment: .leading, spacing: IterSpace.sm))
                                         : AnyLayout(HStackLayout(alignment: .top, spacing: IterGrid.inset))
        return layout {
            EventScore(window: best.window, zone: page.timeZone, timeStyle: .range, variant: .large,
                       isLoading: page.isLoadingForecast)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(LightText.bestIn(days: page.stripDays.count, intent: page.intent))
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

/// The outlook as its own module: the days the forecast covers, each openable in place (OutlookStrip).
struct OutlookSection: View {
    let page: SpotModel

    var body: some View {
        ModuleCard(title: LightText.outlookTitle(days: page.stripDays.count, intent: page.intent), symbol: "calendar", flush: true) {
            OutlookStrip(page: page)
        }
    }
}

/// The days the forecast covers, today first, each with the intent's headline chip (pattern #22): fainter and with a
/// range as confidence falls, an empty slot where a day has no score, "Best" on the best day. A day is a button on
/// the lane grid: the disclosure chevron, the day, the chip and the range. It opens in place to that day's windows
/// ([DayWindowsList]); one day is open at a time, and opening a day selects it, so the timeline, compass and hourly
/// strip follow. Ten days never fit across a narrow column, so the days stack (the Weather ten-day idiom).
struct OutlookStrip: View {
    let page: SpotModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let best = page.best
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(page.stripDays.enumerated()), id: \.element.day) { index, light in
                if index > 0 { Divider().padding(.leading, WindowLanes.labelStart) }
                dayRow(light, isBest: best?.day == light.day)
                if page.expandedDay == light.day {
                    DayWindowsList(page: page, day: light.day)
                        .transition(.opacity)
                }
            }
            Text(LightText.outlookKey)
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
                .padding(.horizontal, IterGrid.inset)
                .padding(.top, IterSpace.sm)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: page.expandedDay)
    }

    /// The widest state word, "No window", at the secondary text style.
    private static let rangeLane: CGFloat = {
        let font = NSFont.preferredFont(forTextStyle: .subheadline)
        return ceil(("No window" as NSString).size(withAttributes: [.font: font]).width)
    }()

    private func dayRow(_ light: DayLight, isBest: Bool) -> some View {
        let window = rowWindow(light)
        let isOpen = page.expandedDay == light.day
        let selected = light.day == page.day
        let label = light.day == page.today ? LightText.relativeDay(light.day, today: page.today)
                                            : String(localized: "\(TimeText.weekday(light.day)) \(TimeText.dayNumber(light.day))",
                                                     comment: "Outlook row: weekday and day of the month, e.g. Thu 8")
        return Button {
            page.toggleDayExpanded(light.day)
        } label: {
            HStack(alignment: .center, spacing: IterGrid.laneGap) {
                Image(systemName: "chevron.right")
                    .font(IterFont.moduleTitle)
                    .foregroundStyle(IterColor.textSecondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: IterGrid.disclosureLane)
                    .accessibilityHidden(true)
                HStack(spacing: IterSpace.xs) {
                    Text(label).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    if isBest {
                        Text(LightText.bestMarker).font(IterFont.moduleTitle).foregroundStyle(IterColor.accentText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                chip(window)
                // No score range on the row (the range lives in a window's reasons); only a state word when there is no chip.
                Text(window == nil ? caption(light) : "")
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
                    .frame(width: Self.rangeLane, alignment: .trailing)
            }
            .padding(.horizontal, IterGrid.inset)
            .padding(.vertical, IterSpace.sm)
            .frame(minHeight: IterGrid.rowSingle)
            // The open day's own windows carry the selection; a selected, closed day is filled.
            .background(selected && !isOpen ? IterColor.selection : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(light, window: window, isBest: isBest))
        .accessibilityValue(isOpen ? String(localized: "Expanded", comment: "VoiceOver state") : String(localized: "Collapsed", comment: "VoiceOver state"))
        .accessibilityHint(String(localized: "Shows this day's light windows", comment: "VoiceOver hint"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .help(isOpen ? String(localized: "Hide this day's windows", comment: "Help") : String(localized: "Show this day's windows", comment: "Help"))
    }

    /// The day's headline window; nil when it has passed (today) or the sun gives none.
    private func rowWindow(_ light: DayLight) -> LightWindow? {
        let window = light.headline(for: page.intent)
        if case .noForecast(.inThePast)? = window?.assessment { return nil }
        return window
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

    private func caption(_ light: DayLight) -> String {
        light.headline(for: page.intent) == nil ? String(localized: "No window", comment: "Outlook cell when the sun gives no such window")
                                                : LightText.windowPassed
    }

    private func accessibilityLabel(_ light: DayLight, window: LightWindow?, isBest: Bool) -> String {
        var parts = [TimeText.longDay(light.day)]
        if let window { parts.append(LightText.accessibilityDescription(window)) }
        if isBest { parts.append(LightText.bestMarker) }
        return parts.joined(separator: ", ")
    }
}
