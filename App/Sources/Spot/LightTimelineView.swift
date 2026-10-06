import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Everything the timeline canvas draws, captured as plain values (the canvas closure never reads the model).
struct TimelineData {
    var zone: TimeZone
    var day: LocalDay
    var domain: ClosedRange<Date>
    var windows: [LightWindow]
    var selected: LightWindowKind?
    var sky: [(date: Date, altitude: Double)]
    var hours: [HourlyConditions]
    var hasLayers: Bool
    var marker: Date
    var scrubbing: Bool
    var tiers: Int
    var tickEveryHours: Int
    var hasWeather: Bool

    var span: TimeInterval { max(1, domain.upperBound.timeIntervalSince(domain.lowerBound)) }
}

/// The 24-hour light timeline (pattern #16): a sky band coloured by sun altitude, the five windows as labelled
/// brackets with their scores, cloud by altitude and rain chance on a 0 to 100 percent scale, and a scrubber.
/// One shared selection and marker time with the arc and the hourly strip (critique C06).
struct LightTimelineSection: View {
    let page: SpotModel
    @State private var width: CGFloat = 0

    var body: some View {
        let data = Self.data(page)
        VStack(alignment: .leading, spacing: IterSpace.md) {
            header
            SpotCard {
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    readout
                    Canvas { ctx, size in TimelineRenderer.draw(&ctx, size: size, data: data) }
                        .frame(height: Self.height(data))
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): page.scrub = date(atX: point.x, data: data)
                            case .ended: page.scrub = nil
                            }
                        }
                        .gesture(DragGesture(minimumDistance: IterSpace.xs).onChanged { page.scrub = date(atX: $0.location.x, data: data) }
                            .onEnded { _ in page.scrub = nil })
                        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                            let t = date(atX: tap.location.x, data: data)
                            if let hit = page.dayLight.windows.first(where: { $0.span.contains(t) }) { page.selectWindow(hit.kind) }
                        })
                        .accessibilityElement()
                        .accessibilityLabel(accessibilitySummary)
                        .accessibilityValue(page.selectedLightWindow.map { LightText.accessibilityDescription($0) } ?? "")
                        .accessibilityAdjustableAction { direction in stepWindow(direction) }
                    if data.hasWeather { legend(data) } else { noWeather }
                }
            }
        }
    }

    // MARK: Pieces

    @Environment(\.spotDensity) private var density

    private var header: some View {
        let layout = density == .compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: IterSpace.sm))
                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            SpotSectionTitle(LightText.timelineTitle)
            if density == .page { Spacer() }
            if page.availableFoci.count > 1 {
                Picker(selection: Binding(get: { page.focus }, set: { page.setFocus($0) })) {
                    ForEach(page.availableFoci) { focus in Text(label(focus)).tag(focus) }
                } label: { Text("Zoom", comment: "Timeline zoom picker label") }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(String(localized: "Zoom the timeline, arc and hourly strip to sunrise or sunset", comment: "Help"))
            }
        }
    }

    private var readout: some View {
        let t = page.markerTime
        let r = page.readout(at: t)
        let window = page.window(at: t)
        return HStack(spacing: IterSpace.sm) {
            Text(LightText.readout(hour: TimeText.time(t, in: page.timeZone), cloud: r.cloud, rain: r.rain,
                                         rainMm: r.rain == nil ? page.forecast?.hour(at: t)?.precipitationMm : nil))
                .font(IterFont.bodyEmphasis)
                .monospacedDigit()
            if let window {
                Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                Text(LightText.name(window.kind)).font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
            }
            Spacer()
            if page.scrub == nil {
                Text("Hover or drag to read any time", comment: "Hint on the timeline")
                    .font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
            }
        }
        .frame(minHeight: IterSize.badgeHeight)
    }

    private func legend(_ data: TimelineData) -> some View {
        HStack(spacing: IterSpace.md) {
            if data.hasLayers {
                swatch(IterColor.cloudHigh, LightText.cloudHighLegend)
                swatch(IterColor.cloudMid, LightText.cloudMidLegend)
                swatch(IterColor.cloudLow, LightText.cloudLowLegend)
            } else {
                swatch(IterColor.cloudMid, LightText.cloudTotalLegend)
            }
            swatch(IterColor.skyBlue, data.hours.contains { $0.precipitationChance != nil } ? LightText.rainLegend : LightText.rainAmountLegend)
            Spacer()
        }
        .font(IterFont.caption)
        .foregroundStyle(IterColor.textSecondary)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: IterSpace.xs) {
            RoundedRectangle(cornerRadius: IterSpace.xxs).fill(color).frame(width: IterSpace.md, height: IterSpace.md)
                .overlay(RoundedRectangle(cornerRadius: IterSpace.xxs).strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            Text(title)
        }
    }

    /// Without hourly weather the timeline has nothing to chart; the screen's banner says why.
    @ViewBuilder private var noWeather: some View {
        if page.isLoadingForecast {
            Label { Text(LightText.checkingForecast) } icon: { ProgressView().controlSize(.small) }
                .font(IterFont.subheadline)
                .foregroundStyle(IterColor.textSecondary)
        }
    }

    private func label(_ focus: TimelineFocus) -> String {
        switch focus {
        case .fullDay: LightText.zoomFullDay
        case .aroundSunrise: LightText.zoomSunrise
        case .aroundSunset: LightText.zoomSunset
        }
    }

    // MARK: Interaction

    private func date(atX x: CGFloat, data: TimelineData) -> Date {
        let plotWidth = max(1, width - SpotLayout.gutter - SpotLayout.rightInset)
        let fraction = min(1, max(0, (x - SpotLayout.gutter) / plotWidth))
        return data.domain.lowerBound.addingTimeInterval(data.span * Double(fraction))
    }

    private func stepWindow(_ direction: AccessibilityAdjustmentDirection) {
        let kinds = page.dayLight.windows.map(\.kind)
        guard !kinds.isEmpty else { return }
        let current = page.selectedWindow.flatMap { kinds.firstIndex(of: $0) } ?? -1
        switch direction {
        case .increment: page.selectWindow(kinds[min(kinds.count - 1, current + 1)])
        case .decrement: page.selectWindow(kinds[max(0, current - 1)])
        @unknown default: break
        }
    }

    private var accessibilitySummary: String {
        let zone = page.timeZone
        let windows = page.dayLight.windows.map { "\(LightText.accessibilityDescription($0)), \(TimeText.timeRange($0.span, in: zone))" }
        let title = String(localized: "Light timeline for \(TimeText.longDay(page.day))", comment: "VoiceOver: timeline label")
        return ([title] + windows).joined(separator: ". ")
    }

    // MARK: Data and size

    static func data(_ page: SpotModel) -> TimelineData {
        let domain = page.domain
        let sun = page.paths.sun
        let sky = sun.filter { $0.date >= domain.lowerBound.addingTimeInterval(-3600) && $0.date <= domain.upperBound.addingTimeInterval(3600) }
            .map { (date: $0.date, altitude: $0.position.altitude) }
        let hasWeather = page.forecast != nil && !page.hours.isEmpty
        return TimelineData(zone: page.timeZone, day: page.day, domain: domain, windows: page.dayLight.windows,
                            selected: page.selectedWindow, sky: sky, hours: page.hours, hasLayers: page.hasCloudLayers,
                            marker: page.markerTime, scrubbing: page.scrub != nil,
                            tiers: page.focus == .fullDay ? 3 : 2,
                            tickEveryHours: page.focus == .fullDay ? 3 : 1, hasWeather: hasWeather)
    }

    static func height(_ data: TimelineData) -> CGFloat {
        TimelineRenderer.layout(data, width: 100).totalHeight
    }
}

// MARK: - Renderer

enum TimelineRenderer {
    struct Layout {
        var tiersHeight: CGFloat
        var bracketY: CGFloat
        var skyTop: CGFloat
        var skyBottom: CGFloat
        var axisBottom: CGFloat
        var plotTop: CGFloat
        var plotBottom: CGFloat
        var totalHeight: CGFloat
    }

    static func layout(_ d: TimelineData, width: CGFloat) -> Layout {
        let tiersHeight = CGFloat(d.tiers) * SpotLayout.labelTier
        let bracketY = tiersHeight + IterSpace.xxs
        let skyTop = bracketY + SpotLayout.bracketDrop + IterSpace.xxs
        let skyBottom = skyTop + IterSize.timelineHeight
        let axisBottom = skyBottom + IterSize.timelineAxisHeight
        let plotTop = axisBottom + IterSpace.sm
        let plotBottom = plotTop + (d.hasWeather ? SpotLayout.plotHeight : 0)
        return Layout(tiersHeight: tiersHeight, bracketY: bracketY, skyTop: skyTop, skyBottom: skyBottom, axisBottom: axisBottom,
                      plotTop: plotTop, plotBottom: plotBottom, totalHeight: d.hasWeather ? plotBottom + IterSpace.xxs : axisBottom)
    }

    /// Sky colour for a sun altitude: night below -18, blue hour -6 to the horizon, golden hour to +6, then day.
    static func skyColor(_ altitude: Double) -> Color {
        let night = IterColor.skyNight, blue = IterColor.skyBlue, golden = IterColor.skyGolden, day = IterColor.skyDay
        switch altitude {
        case ..<(-18): return night
        case -18..<(-6): return night.mix(with: blue, by: (altitude + 18) / 12)
        case -6..<(-0.8): return blue
        case -0.8..<0.8: return blue.mix(with: golden, by: (altitude + 0.8) / 1.6)
        case 0.8..<6: return golden
        case 6..<14: return golden.mix(with: day, by: (altitude - 6) / 8)
        default: return day
        }
    }

    static func tint(_ kind: LightWindowKind) -> Color {
        switch kind {
        case .goldenMorning, .goldenEvening: IterColor.skyGolden
        case .blueMorning, .blueEvening: IterColor.skyBlue
        case .night: IterColor.skyNight
        }
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, data d: TimelineData) {
        let lay = layout(d, width: size.width)
        let left = SpotLayout.gutter
        let right = size.width - SpotLayout.rightInset
        let plotW = right - left
        guard plotW > 0 else { return }
        func x(_ date: Date) -> CGFloat { left + CGFloat(date.timeIntervalSince(d.domain.lowerBound) / d.span) * plotW }

        // Sky band, coloured by sun altitude.
        let skyRect = CGRect(x: left, y: lay.skyTop, width: plotW, height: lay.skyBottom - lay.skyTop)
        let stops = d.sky.map { Gradient.Stop(color: skyColor($0.altitude),
                                              location: min(1, max(0, CGFloat($0.date.timeIntervalSince(d.domain.lowerBound) / d.span)))) }
        ctx.drawLayer { layer in
            layer.clip(to: Path(roundedRect: skyRect, cornerRadius: IterRadius.badge))
            if stops.count > 1 {
                layer.fill(Path(skyRect), with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0)))
            } else {
                layer.fill(Path(skyRect), with: .color(IterColor.skyNight))
            }
        }

        // Hour ticks directly under the strip (C09), in the spot's zone.
        drawAxis(&ctx, d, lay, x: x, left: left, right: right)

        // Weather plot.
        if d.hasWeather { drawPlot(&ctx, d, lay, x: x, left: left, right: right) }

        // Selected window across the whole stack.
        for w in d.windows where w.kind == d.selected {
            let (x0, x1) = extent(w, x: x, left: left, right: right)
            guard x1 > x0 else { continue }
            let rect = CGRect(x: x0, y: lay.skyTop, width: x1 - x0, height: (d.hasWeather ? lay.plotBottom : lay.skyBottom) - lay.skyTop)
            let path = Path(roundedRect: rect.insetBy(dx: -IterStroke.thin, dy: -IterStroke.thin), cornerRadius: IterRadius.badge / 2)
            ctx.stroke(path, with: .color(IterColor.backgroundWindow), lineWidth: IterStroke.thick + IterStroke.thin * 2)
            ctx.stroke(path, with: .color(IterColor.accent), lineWidth: IterStroke.thick)
        }

        drawBrackets(&ctx, d, lay, x: x, left: left, right: right)

        // Scrubber / marker.
        if d.domain.contains(d.marker) {
            let mx = x(d.marker)
            var line = Path()
            line.move(to: CGPoint(x: mx, y: lay.skyTop))
            line.addLine(to: CGPoint(x: mx, y: d.hasWeather ? lay.plotBottom : lay.skyBottom))
            let style = d.scrubbing
                ? StrokeStyle(lineWidth: IterStroke.regular)
                : StrokeStyle(lineWidth: IterStroke.thin, dash: [IterStroke.dashLength, IterStroke.dashGap])
            ctx.stroke(line, with: .color(IterColor.backgroundWindow), style: StrokeStyle(lineWidth: style.lineWidth + IterStroke.thin * 2))
            ctx.stroke(line, with: .color(IterColor.textPrimary.color), style: style)
            let knob = CGRect(x: mx - IterSpace.xs, y: lay.skyBottom - IterSpace.xs, width: IterSpace.sm, height: IterSpace.sm)
            ctx.fill(Path(ellipseIn: knob), with: .color(IterColor.textPrimary.color))
            ctx.stroke(Path(ellipseIn: knob), with: .color(IterColor.backgroundWindow), lineWidth: IterStroke.thin)
        }
    }

    private static func extent(_ w: LightWindow, x: (Date) -> CGFloat, left: CGFloat, right: CGFloat) -> (CGFloat, CGFloat) {
        var x0 = max(left, x(w.span.start))
        var x1 = min(right, x(w.span.end))
        if x1 < x0 { return (x0, x0) }
        if x1 - x0 < IterSize.windowMinWidth {
            let mid = (x0 + x1) / 2
            x0 = max(left, mid - IterSize.windowMinWidth / 2)
            x1 = min(right, x0 + IterSize.windowMinWidth)
        }
        return (x0, x1)
    }

    private static func drawAxis(_ ctx: inout GraphicsContext, _ d: TimelineData, _ lay: Layout, x: (Date) -> CGFloat, left: CGFloat, right: CGFloat) {
        for hour in stride(from: 0, through: 24, by: d.tickEveryHours) {
            let date = d.day.at(hour: hour, in: d.zone)
            guard d.domain.contains(date) else { continue }
            let tx = x(date)
            var tick = Path()
            tick.move(to: CGPoint(x: tx, y: lay.skyBottom))
            tick.addLine(to: CGPoint(x: tx, y: lay.skyBottom + SpotLayout.tickLength))
            ctx.stroke(tick, with: .color(IterColor.textSecondary.color), lineWidth: IterStroke.thin)
            let text = Text(verbatim: LightText.hourLabel(date, in: d.zone)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
            ctx.draw(text, at: CGPoint(x: tx, y: lay.skyBottom + SpotLayout.tickLength), anchor: .top)
        }
    }

    private static func drawPlot(_ ctx: inout GraphicsContext, _ d: TimelineData, _ lay: Layout, x: (Date) -> CGFloat, left: CGFloat, right: CGFloat) {
        let plot = CGRect(x: left, y: lay.plotTop, width: right - left, height: lay.plotBottom - lay.plotTop)
        func y(_ fraction: Double) -> CGFloat { lay.plotBottom - CGFloat(min(1, max(0, fraction))) * plot.height }

        // Window bands behind the data (golden and blue spans shaded; the selected one tinted with the accent).
        for w in d.windows {
            let (x0, x1) = extent(w, x: x, left: left, right: right)
            guard x1 > x0 else { continue }
            let rect = CGRect(x: x0, y: plot.minY, width: x1 - x0, height: plot.height)
            ctx.fill(Path(rect), with: .color(tint(w.kind).opacity(SpotLayout.windowTintOpacity)))
            if w.kind == d.selected { ctx.fill(Path(rect), with: .color(IterColor.selection)) }
        }

        // 0, 50, 100 percent gridlines with labels.
        for fraction in [0.0, 0.5, 1.0] {
            var grid = Path()
            grid.move(to: CGPoint(x: left, y: y(fraction)))
            grid.addLine(to: CGPoint(x: right, y: y(fraction)))
            ctx.stroke(grid, with: .color(IterColor.separator), lineWidth: IterStroke.hairline)
            let label = Text(verbatim: LightText.percent(fraction)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
            ctx.draw(label, at: CGPoint(x: left - IterSpace.xs, y: y(fraction)), anchor: .trailing)
        }

        let hours = d.hours.filter {
            $0.date.addingTimeInterval(3600) >= d.domain.lowerBound.addingTimeInterval(-3600) && $0.date <= d.domain.upperBound.addingTimeInterval(3600)
        }
        ctx.drawLayer { layer in
            layer.clip(to: Path(plot))
            // Cloud layers, layered (not stacked) so each reads against the 0 to 100 percent scale.
            let series: [(Color, (HourlyConditions) -> Double)] = d.hasLayers
                ? [(IterColor.cloudHigh, { $0.cloudHigh ?? 0 }), (IterColor.cloudMid, { $0.cloudMid ?? 0 }), (IterColor.cloudLow, { $0.cloudLow ?? 0 })]
                : [(IterColor.cloudMid, { $0.cloudCover })]
            for (color, value) in series where hours.count > 1 {
                var area = Path()
                var top = Path()
                for (i, h) in hours.enumerated() {
                    let point = CGPoint(x: x(h.date.addingTimeInterval(1800)), y: y(value(h)))
                    if i == 0 {
                        area.move(to: CGPoint(x: point.x, y: lay.plotBottom))
                        area.addLine(to: point)
                        top.move(to: point)
                    } else {
                        area.addLine(to: point)
                        top.addLine(to: point)
                    }
                }
                if let last = hours.last { area.addLine(to: CGPoint(x: x(last.date.addingTimeInterval(1800)), y: lay.plotBottom)) }
                area.closeSubpath()
                layer.fill(area, with: .color(color.opacity(SpotLayout.cloudFillOpacity)))
                layer.stroke(top, with: .color(color), lineWidth: IterStroke.regular)
            }
            // Rain chance as bars.
            // When the provider gives only an amount (Windy), the bar is the amount against a full scale of `rainFullScaleMm`.
            for h in hours {
                let level = rainLevel(h)
                guard level >= 0.1 else { continue }
                let x0 = x(h.date), x1 = x(h.date.addingTimeInterval(3600))
                let inset = (x1 - x0) * 0.2
                let rect = CGRect(x: x0 + inset, y: y(level), width: max(1, x1 - x0 - inset * 2), height: lay.plotBottom - y(level))
                layer.fill(Path(roundedRect: rect, cornerRadius: IterStroke.thin), with: .color(IterColor.skyBlue))
            }
        }
    }

    /// Millimetres per hour that fill the plot's height when the provider gives no chance of rain.
    static let rainFullScaleMm = 2.0

    /// 0–1: the chance when known, else the amount against `rainFullScaleMm`, else 0.
    private static func rainLevel(_ h: HourlyConditions) -> Double {
        if let chance = h.precipitationChance { return chance }
        if let mm = h.precipitationMm { return min(1, mm / rainFullScaleMm) }
        return 0
    }

    private static func drawBrackets(_ ctx: inout GraphicsContext, _ d: TimelineData, _ lay: Layout, x: (Date) -> CGFloat, left: CGFloat, right: CGFloat) {
        var tierEnds = [CGFloat](repeating: -.infinity, count: d.tiers)
        for w in d.windows.sorted(by: { $0.span.start < $1.span.start }) {
            let (x0, x1) = extent(w, x: x, left: left, right: right)
            guard x1 > x0 else { continue }
            let selected = w.kind == d.selected
            let color = selected ? IterColor.accent : IterColor.textSecondary.color
            var bracket = Path()
            bracket.move(to: CGPoint(x: x0, y: lay.bracketY + SpotLayout.bracketDrop))
            bracket.addLine(to: CGPoint(x: x0, y: lay.bracketY))
            bracket.addLine(to: CGPoint(x: x1, y: lay.bracketY))
            bracket.addLine(to: CGPoint(x: x1, y: lay.bracketY + SpotLayout.bracketDrop))
            ctx.stroke(bracket, with: .color(color), lineWidth: selected ? IterStroke.thick : IterStroke.regular)

            let text = Text(verbatim: LightText.windowChartLabel(w))
                .font(selected ? IterFont.captionStrong : IterFont.caption)
                .foregroundStyle(w.score == nil ? IterColor.textSecondary : IterColor.textPrimary)
            let resolved = ctx.resolve(text)
            let measured = resolved.measure(in: CGSize(width: 400, height: SpotLayout.labelTier))
            var lx = x0
            if lx + measured.width > right { lx = right - measured.width }
            lx = max(left - IterSpace.sm, lx)
            let gap = IterSpace.xs
            var tier = 0
            while tier < d.tiers - 1, lx < tierEnds[tier] + gap { tier += 1 }
            tierEnds[tier] = lx + measured.width
            let ty = lay.tiersHeight - CGFloat(tier + 1) * SpotLayout.labelTier
            ctx.draw(resolved, at: CGPoint(x: lx, y: ty), anchor: .topLeading)
            if tier > 0 {
                var leader = Path()
                leader.move(to: CGPoint(x: x0, y: ty + SpotLayout.labelTier - IterStroke.thin))
                leader.addLine(to: CGPoint(x: x0, y: lay.bracketY))
                ctx.stroke(leader, with: .color(IterColor.separator), lineWidth: IterStroke.hairline)
            }
        }
    }
}
