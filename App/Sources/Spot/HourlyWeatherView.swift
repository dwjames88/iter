import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The day's weather hour by hour, on the same x-axis as the light timeline (critique C19 to C21): symbol,
/// temperature in the user's unit, cloud, rain where it matters, wind; golden and blue hours tinted.
struct HourlyWeatherSection: View {
    let page: SpotModel
    @AppStorage(AppSettings.temperatureUnit) private var temperatureUnit = "system"

    private static let rainThreshold = 0.2
    /// Millimetres per hour worth showing when only an amount is known.
    private static let rainMmThreshold = 0.1
    private static let rowCount = 5

    var body: some View {
        let hours = page.hours.filter { page.domain.contains($0.date) || page.domain.contains($0.date.addingTimeInterval(3599)) }
        if page.forecast != nil, !hours.isEmpty {
            VStack(alignment: .leading, spacing: IterSpace.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LightText.hourlyTitle).font(IterFont.titleSection)
                    Spacer()
                    if let forecast = page.forecast {
                        ForecastSourceLine(info: ForecastSourceInfo(forecast))
                    }
                }
                SpotCard {
                    VStack(alignment: .leading, spacing: IterSpace.sm) {
                        strip(hours)
                            .frame(height: SpotLayout.hourlyRow * CGFloat(Self.rowCount))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilitySummary(hours))
                        HStack(alignment: .firstTextBaseline) {
                            WeatherAttributionView(source: page.forecast?.source ?? ForecastSourceInfo.configured(app: page.app))
                            Spacer()
                            Text(hours.contains { $0.precipitationChance == nil && $0.precipitationMm != nil }
                                 ? String(localized: "Rain in mm/h · Wind in \(LightText.windUnit)", comment: "Hourly strip footnote naming the rain and wind units when rain is an amount")
                                 : String(localized: "Wind in \(LightText.windUnit)", comment: "Hourly strip footnote naming the wind unit"))
                                .font(IterFont.caption)
                                .foregroundStyle(IterColor.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func strip(_ hours: [HourlyConditions]) -> some View {
        GeometryReader { geo in
            let plotW = max(1, geo.size.width - SpotLayout.gutter - SpotLayout.rightInset)
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
                        Text(title).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
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
                .font(IterFont.subheadline)
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
