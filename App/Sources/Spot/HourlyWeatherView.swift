import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The day's weather hour by hour, on the same x-axis as the light timeline (critique C19 to C21): symbol,
/// temperature in the user's unit, cloud, rain where it matters, wind; golden and blue hours tinted.
struct HourlyWeatherSection: View {
    let page: SpotModel
    @AppStorage(AppSettings.temperatureUnit) private var temperatureUnit = "system"
    @Environment(\.spotDensity) private var density

    private static let rainThreshold = 0.2
    /// Millimetres per hour worth showing when only an amount is known.
    private static let rainMmThreshold = 0.1
    private static let rowCount = 5

    var body: some View {
        let hours = page.hours.filter { page.domain.contains($0.date) || page.domain.contains($0.date.addingTimeInterval(3599)) }
        if page.forecast != nil, !hours.isEmpty {
            ModuleCard(title: LightText.hourlyTitle, symbol: "cloud.sun") {
                if density == .page, let forecast = page.forecast {
                    ForecastSourceLine(info: ForecastSourceInfo(forecast))
                }
            } content: {
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    stripBody(hours)
                        .frame(height: SpotLayout.hourlyRow * CGFloat(Self.rowCount))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilitySummary(hours))
                    if density == .compact, let visibility = visibilityText(hours) {
                        Label(visibility, systemImage: "eye")
                            .font(IterFont.secondary)
                            .foregroundStyle(IterColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    footer(hours)
                }
            }
        }
    }

    @ViewBuilder private func footer(_ hours: [HourlyConditions]) -> some View {
        let units = Text(hours.contains { $0.precipitationChance == nil && $0.precipitationMm != nil }
                         ? String(localized: "Rain in mm/h · Wind in \(LightText.windUnit)", comment: "Hourly strip footnote naming the rain and wind units when rain is an amount")
                         : String(localized: "Wind in \(LightText.windUnit)", comment: "Hourly strip footnote naming the wind unit"))
            .font(IterFont.secondary)
            .foregroundStyle(IterColor.textSecondary)
        units
    }

    /// "Visibility 8 km to 16 km" over the shown hours; nil when the provider gives none.
    private func visibilityText(_ hours: [HourlyConditions]) -> String? {
        let values = hours.compactMap(\.visibilityMeters)
        guard let low = values.min(), let high = values.max() else { return nil }
        func format(_ meters: Double) -> String {
            Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        if format(low) == format(high) {
            return String(localized: "Visibility \(format(low))", comment: "Compact hourly weather: horizontal visibility")
        }
        return String(localized: "Visibility \(format(low)) to \(format(high))", comment: "Compact hourly weather: range of horizontal visibility over the day")
    }

    private var rightInset: CGFloat { density == .compact ? IterSpace.xs : SpotLayout.rightInset }

    @ViewBuilder private func stripBody(_ hours: [HourlyConditions]) -> some View {
        if density == .compact { scrollingStrip(hours) } else { strip(hours) }
    }

    /// Narrow host: fixed-width hour columns in a horizontal scroll view beside a pinned label gutter, so
    /// every value stays legible. Scrolls to the hour of the marker.
    private func scrollingStrip(_ hours: [HourlyConditions]) -> some View {
        let marker = page.markerTime
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach([LightText.rowTemp, LightText.rowCloud, LightText.rowRain, LightText.rowWind], id: \.self) { title in
                    Text(title).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        .frame(height: SpotLayout.hourlyRow)
                }
            }
            .padding(.top, SpotLayout.hourlyRow)
            .padding(.trailing, IterSpace.xs)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(hours, id: \.date) { h in
                            let isMarker = marker >= h.date && marker < h.date.addingTimeInterval(3600)
                            column(h)
                                .frame(width: IterSize.controlHeightLarge)
                                .background(tintColor(at: h.date))
                                .background(isMarker ? IterColor.textPrimary.opacity(SpotLayout.selectedFillOpacity / 2) : .clear)
                                .id(h.date)
                        }
                    }
                }
                .onAppear {
                    if let target = hours.first(where: { marker >= $0.date && marker < $0.date.addingTimeInterval(3600) }) ?? hours.first {
                        proxy.scrollTo(target.date, anchor: .center)
                    }
                }
                // Starts beside the gutter, so scrolled columns end at its edge instead of passing under the labels.
                .clipped()
            }
        }
    }

    private func tintColor(at date: Date) -> Color {
        let mid = date.addingTimeInterval(1800)
        guard let w = page.dayLight.windows.first(where: { $0.span.start <= mid && mid < $0.span.end }) else { return .clear }
        return TimelineRenderer.tint(w.kind).opacity(SpotLayout.windowTintOpacity)
    }

    private func strip(_ hours: [HourlyConditions]) -> some View {
        GeometryReader { geo in
            let plotW = max(1, geo.size.width - SpotLayout.gutter - rightInset)
            let domain = page.domain
            let span = max(1, domain.upperBound.timeIntervalSince(domain.lowerBound))
            let colW = plotW * 3600 / span
            let marker = page.markerTime
            let x: (Date) -> CGFloat = { SpotLayout.gutter + CGFloat($0.timeIntervalSince(domain.lowerBound) / span) * plotW }
            ZStack(alignment: .topLeading) {
                // Golden and blue hours tinted, the selected window in the accent.
                ForEach(page.dayLight.windows) { w in
                    tint(w, x0: max(SpotLayout.gutter, x(w.span.start)), x1: min(SpotLayout.gutter + plotW, x(w.span.end)), height: geo.size.height)
                }
                // Row labels in the gutter.
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach([LightText.rowTemp, LightText.rowCloud, LightText.rowRain, LightText.rowWind], id: \.self) { title in
                        Text(title).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                            .frame(height: SpotLayout.hourlyRow)
                    }
                }
                .padding(.top, SpotLayout.hourlyRow)
                .frame(width: SpotLayout.gutter - IterSpace.xs, alignment: .trailing)
                // The hours.
                ForEach(hours, id: \.date) { h in
                    let isMarker = marker >= h.date && marker < h.date.addingTimeInterval(3600)
                    column(h)
                        .frame(width: colW, height: geo.size.height)
                        .background(isMarker ? IterColor.textPrimary.opacity(SpotLayout.selectedFillOpacity / 2) : .clear)
                        .offset(x: x(h.date))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder private func tint(_ w: LightWindow, x0: CGFloat, x1: CGFloat, height: CGFloat) -> some View {
        if x1 > x0 {
            Rectangle()
                .fill(TimelineRenderer.tint(w.kind).opacity(SpotLayout.windowTintOpacity))
                .overlay(w.kind == page.selectedWindow ? IterColor.selection : .clear)
                .frame(width: x1 - x0, height: height)
                .offset(x: x0)
        }
    }

    private func column(_ h: HourlyConditions) -> some View {
        VStack(spacing: 0) {
            Image(systemName: h.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(IterFont.secondary)
                .frame(height: SpotLayout.hourlyRow)
            cell(AppSettings.temperature(h.temperatureC, unitSetting: temperatureUnit))
            cell(Int((h.cloudCover * 100).rounded()).formatted())
            cell(rainText(h), color: AnyShapeStyle(IterColor.accentText))
            cell(LightText.windNumber(kph: h.windSpeedKph))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// The chance when the provider gives one, the amount in mm when it gives only that, "—" when it gives neither.
    private func rainText(_ h: HourlyConditions) -> String {
        if let chance = h.precipitationChance {
            return chance >= Self.rainThreshold ? Int((chance * 100).rounded()).formatted() : ""
        }
        if let mm = h.precipitationMm {
            return mm >= Self.rainMmThreshold ? mm.formatted(.number.precision(.fractionLength(0...1))) : ""
        }
        return "—"
    }

    private func rainSpoken(_ h: HourlyConditions) -> String {
        if let chance = h.precipitationChance, chance >= Self.rainThreshold {
            return ", \(LightText.percent(chance)) rain"
        }
        if h.precipitationChance == nil, let mm = h.precipitationMm, mm >= Self.rainMmThreshold {
            return ", \(LightText.millimetresPerHour(mm)) rain"
        }
        return ""
    }

    private func cell(_ text: String, color: AnyShapeStyle = AnyShapeStyle(IterColor.textPrimary)) -> some View {
        Text(text)
            .font(IterFont.timeSmall)
            .foregroundStyle(color)
            .frame(height: SpotLayout.hourlyRow)
    }

    private func accessibilitySummary(_ hours: [HourlyConditions]) -> String {
        let zone = page.timeZone
        let rows = hours.enumerated().filter { $0.offset % 3 == 0 }.map(\.element).map { h in
            let rain = rainSpoken(h)
            return "\(LightText.hourLabel(h.date, in: zone)): \(AppSettings.temperature(h.temperatureC, unitSetting: temperatureUnit)), \(LightText.percent(h.cloudCover)) cloud\(rain)"
        }
        return ([String(localized: "Hourly weather", comment: "VoiceOver label")] + rows).joined(separator: ". ")
    }
}
