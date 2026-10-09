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
    /// Panel density: no label gutter, labels inside the plot, a taller band and plot, a time pill on the axis.
    var panel = false

    var span: TimeInterval { max(1, domain.upperBound.timeIntervalSince(domain.lowerBound)) }
}

/// The 24-hour light timeline (pattern #16): a sky band coloured by sun altitude, the five windows as labelled
/// brackets with their scores, cloud by altitude and rain chance on a 0 to 100 percent scale, and a scrubber.
/// One shared selection and marker time with the arc and the hourly strip (critique C06).
struct LightTimelineSection: View {
    let page: SpotModel
    /// Tests inject the rose orientation; the app reads the stored choice.
    var viewUp: Bool?
    @State private var width: CGFloat = 0
    /// Panel: the legend's items and the "Drag to read" hint, measured, to decide which line carries the hint.
    @State private var legendItemsWidth: CGFloat = 0
    @State private var hintWidth: CGFloat = 0

    @Environment(\.spotDensity) private var density
    private var isPanel: Bool { density == .panel }

    var body: some View {
        let data = Self.data(page, panel: isPanel)
        ModuleCard(title: LightText.timelineTitle, symbol: "chart.line.uptrend.xyaxis") {
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    zoomPicker
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
                            .onEnded { _ in page.commitScrub() })
                        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                            let t = date(atX: tap.location.x, data: data)
                            if let hit = page.dayLight.windows.first(where: { $0.span.contains(t) }) { page.selectWindow(hit.kind) }
                        })
                        .accessibilityElement()
                        .accessibilityLabel(accessibilitySummary)
                        .accessibilityValue(page.selectedLightWindow.map { LightText.accessibilityDescription($0) } ?? "")
                        .accessibilityAdjustableAction { direction in stepWindow(direction) }
                    if data.hasWeather { legend(data) } else { noWeather }
                    // The compass shares this module's time: a gap, then the rose block.
                    SkyRoseContent(page: page, viewUp: viewUp)
                        .padding(.top, IterSpace.xl - IterSpace.sm)
                }
        }
    }

    // MARK: Pieces

    /// The zoom control, full width under the module title.

    @ViewBuilder private var zoomPicker: some View {
        if page.availableFoci.count > 1 {
            FullWidthSegmentedPicker(label: LightText.zoomLabel,
                                     options: page.availableFoci.map { ($0, label($0)) },
                                     selection: Binding(get: { page.focus }, set: { page.setFocus($0) }),
                                     help: String(localized: "Zoom the timeline, arc and hourly strip to sunrise or sunset", comment: "Help"))
        }
    }

    /// The panel's "Drag to read any time" hint is shown from `panelHintMinWidth` up.
    private var panelShowsHint: Bool { isPanel && width + IterGrid.inset * 2 >= SpotLayout.panelHintMinWidth }
    /// The legend line has room for its items and the hint.
    private var legendHasRoomForHint: Bool {
        legendItemsWidth == 0 || hintWidth == 0 || legendItemsWidth + hintWidth + IterSpace.sm <= width
    }

    private var hintText: some View {
        Text("Drag to read any time", comment: "Hint at the end of the timeline legend in the Explore panel")
            .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            .lineLimit(1).fixedSize()
    }

    @ViewBuilder private var readout: some View {
        if panelShowsHint && !legendHasRoomForHint {
            // The legend is full: the hint takes the readout line's trailing edge, if the readout leaves room.
            ViewThatFits(in: .horizontal) {
                readoutRow(withHint: true)
                readoutRow(withHint: false)
            }
        } else {
            readoutRow(withHint: false)
        }
    }

    private func readoutRow(withHint: Bool) -> some View {
        let t = page.markerTime
        let r = page.readout(at: t)
        let window = page.window(at: t)
        return HStack(spacing: IterSpace.sm) {
            Text(LightText.readout(hour: TimeText.time(t, in: page.timeZone), cloud: r.cloud, rain: r.rain,
                                         rainMm: r.rain == nil ? page.forecast?.hour(at: t)?.precipitationMm : nil))
                .font(IterFont.headline)
                .monospacedDigit()
            if let window {
                Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                Text(LightText.name(window.kind)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
            Spacer()
            if withHint { hintText }
            if page.scrub == nil, !isPanel {
                Text("Hover or drag to read any time", comment: "Hint on the timeline")
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
        }
        .frame(minHeight: IterSize.badgeHeight)
    }

    private func legend(_ data: TimelineData) -> some View {
        let swatches = Group {
            if data.hasLayers {
                swatch(IterColor.cloudHigh, LightText.cloudHighLegend)
                swatch(IterColor.cloudMid, LightText.cloudMidLegend)
                swatch(IterColor.cloudLow, LightText.cloudLowLegend)
            } else {
                swatch(IterColor.cloudMid, LightText.cloudTotalLegend)
            }
            swatch(IterColor.skyBlue, data.hours.contains { $0.precipitationChance != nil } ? LightText.rainLegend : LightText.rainAmountLegend)
        }
        // One line where it fits; otherwise two rows, so a narrow column (the iPad's) is never pushed wider than itself.
        let items = ViewThatFits(in: .horizontal) {
            HStack(spacing: isPanel ? IterSpace.sm : IterSpace.lg) { swatches }.fixedSize()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: IterSpace.sm, alignment: .leading)],
                      alignment: .leading, spacing: IterSpace.xs) { swatches }
        }
        .lineLimit(1)
        return Group {
            if isPanel {
                // The hint sits at the trailing end when the legend leaves room for it; otherwise on the readout line.
                // The hint is an overlay, so it never widens the row (the row's width decides whether it fits).
                HStack { items.onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { legendItemsWidth = $0 }); Spacer(minLength: 0) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        if panelShowsHint && legendHasRoomForHint { hintText }
                    }
                    .background(alignment: .leading) {
                        hintText.hidden().onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { hintWidth = $0 })
                            .accessibilityHidden(true)
                    }
            } else {
                HStack { items; Spacer() }
            }
        }
        .font(IterFont.secondary)
        .foregroundStyle(IterColor.textSecondary)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: IterSpace.xs) {
            RoundedRectangle(cornerRadius: IterStroke.thin).fill(color).frame(width: IterSpace.sm, height: IterSpace.sm)
                .overlay(RoundedRectangle(cornerRadius: IterStroke.thin).strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            Text(title)
        }
    }

    /// Without hourly weather the timeline has nothing to chart; the screen's banner says why.
    @ViewBuilder private var noWeather: some View {
        if page.isLoadingForecast {
            Label { Text(LightText.checkingForecast) } icon: { ProgressView().controlSize(.small) }
                .font(IterFont.secondary)
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
        TimelineRenderer.date(atX: x, width: width, data: data)
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

    static func data(_ page: SpotModel, panel: Bool = false) -> TimelineData {
        let domain = page.domain
        let sun = page.paths.sun
        let sky = sun.filter { $0.date >= domain.lowerBound.addingTimeInterval(-3600) && $0.date <= domain.upperBound.addingTimeInterval(3600) }
            .map { (date: $0.date, altitude: $0.position.altitude) }
        let hasWeather = page.forecast != nil && !page.hours.isEmpty
        return TimelineData(zone: page.timeZone, day: page.day, domain: domain, windows: page.dayLight.windows,
                            selected: page.selectedWindow, sky: sky, hours: page.hours, hasLayers: page.hasCloudLayers,
                            marker: page.markerTime, scrubbing: page.hasChosenTime,
                            tiers: page.focus == .fullDay ? 3 : 2,
                            tickEveryHours: page.focus == .fullDay ? 3 : 1, hasWeather: hasWeather, panel: panel)
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

    /// The plot's left and right x: the page leaves a gutter for the y-axis labels and a right inset; the panel runs the
    /// whole width (its percent labels sit inside the plot).
    static func plotEdges(width: CGFloat, panel: Bool) -> (left: CGFloat, right: CGFloat) {
        panel ? (0, width) : (SpotLayout.gutter, width - SpotLayout.rightInset)
    }

    /// The x of a date on the plot, for a canvas `width`. The inverse of `date(atX:width:data:)` inside the plot.
    static func x(for date: Date, width: CGFloat, data: TimelineData) -> CGFloat {
        let (left, right) = plotEdges(width: width, panel: data.panel)
        return left + CGFloat(date.timeIntervalSince(data.domain.lowerBound) / data.span) * (right - left)
    }

    /// The date under an x on the plot, clamped to the domain.
    static func date(atX x: CGFloat, width: CGFloat, data: TimelineData) -> Date {
        let (left, right) = plotEdges(width: width, panel: data.panel)
        let fraction = min(1, max(0, (x - left) / max(1, right - left)))
        return data.domain.lowerBound.addingTimeInterval(data.span * Double(fraction))
    }

    static func layout(_ d: TimelineData, width: CGFloat) -> Layout {
        let tiersHeight = CGFloat(d.tiers) * SpotLayout.labelTier
        let bracketY = tiersHeight + IterSpace.xs
        let skyTop = bracketY + SpotLayout.bracketDrop + IterSpace.xs
        let skyBottom = skyTop + (d.panel ? SpotLayout.panelSkyHeight : IterSize.timelineHeight)
        let axisBottom = skyBottom + IterSize.timelineAxisHeight
        let plotTop = axisBottom + IterSpace.sm
        let plotBottom = plotTop + (d.hasWeather ? (d.panel ? SpotLayout.panelPlotHeight : SpotLayout.plotHeight) : 0)
        return Layout(tiersHeight: tiersHeight, bracketY: bracketY, skyTop: skyTop, skyBottom: skyBottom, axisBottom: axisBottom,
                      plotTop: plotTop, plotBottom: plotBottom, totalHeight: d.hasWeather ? plotBottom + IterSpace.xs : axisBottom)
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
        let (left, right) = plotEdges(width: size.width, panel: d.panel)
        let plotW = right - left
        guard plotW > 0 else { return }
        func x(_ date: Date) -> CGFloat { Self.x(for: date, width: size.width, data: d) }

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
        // The panel's time pill over the marker line.
        drawPill(&ctx, d, lay, x: x, left: left, right: right)
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
        // The panel's marker time is a pill on the axis (drawn over the marker line afterwards); labels it would touch are skipped.
        let pill = pillGeometry(&ctx, d, lay, x: x, left: left, right: right)
        // The page draws no pill; a label the marker line would run through is skipped the same way.
        let markerX: CGFloat? = (!d.panel && d.domain.contains(d.marker)) ? x(d.marker) : nil
        for hour in stride(from: 0, through: 24, by: d.tickEveryHours) {
            let date = d.day.at(hour: hour, in: d.zone)
            guard d.domain.contains(date) else { continue }
            let tx = x(date)
            var tick = Path()
            tick.move(to: CGPoint(x: tx, y: lay.skyBottom))
            tick.addLine(to: CGPoint(x: tx, y: lay.skyBottom + SpotLayout.tickLength))
            ctx.stroke(tick, with: .color(IterColor.textSecondary.color), lineWidth: IterStroke.thin)
            let text = Text(verbatim: LightText.hourLabel(date, in: d.zone)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
            if d.panel {
                // The plot runs to the canvas edge: keep the end labels inside it.
                let resolved = ctx.resolve(text)
                let width = resolved.measure(in: CGSize(width: 100, height: IterSize.timelineAxisHeight)).width
                if let pill, abs(tx - pill.x) < (pill.width + width) / 2 + IterSpace.xs { continue }
                let anchor: UnitPoint = tx - width / 2 < left ? .topLeading : tx + width / 2 > right ? .topTrailing : .top
                ctx.draw(resolved, at: CGPoint(x: tx, y: lay.skyBottom + SpotLayout.tickLength), anchor: anchor)
            } else {
                if let markerX {
                    let width = ctx.resolve(text).measure(in: CGSize(width: 100, height: IterSize.timelineAxisHeight)).width
                    if abs(tx - markerX) < width / 2 + IterSpace.xs { continue }
                }
                ctx.draw(text, at: CGPoint(x: tx, y: lay.skyBottom + SpotLayout.tickLength), anchor: .top)
            }
        }
    }

    /// The panel's time pill: where it sits on the axis and how to draw it.
    private static func pillGeometry(_ ctx: inout GraphicsContext, _ d: TimelineData, _ lay: Layout, x: (Date) -> CGFloat,
                                     left: CGFloat, right: CGFloat) -> (x: CGFloat, width: CGFloat, rect: CGRect, text: GraphicsContext.ResolvedText)? {
        guard d.panel, d.domain.contains(d.marker) else { return nil }
        let text = Text(verbatim: TimeText.time(d.marker, in: d.zone)).font(IterFont.timeSmall).foregroundStyle(IterColor.backgroundWindow)
        let resolved = ctx.resolve(text)
        let size = resolved.measure(in: CGSize(width: 200, height: IterSize.timelineAxisHeight))
        let width = size.width + IterSpace.sm * 2
        let height = IterSize.timelineAxisHeight - IterStroke.thin
        let mx = min(max(x(d.marker), left + width / 2), right - width / 2)
        let rect = CGRect(x: mx - width / 2, y: lay.skyBottom + IterStroke.thin, width: width, height: height)
        return (mx, width, rect, resolved)
    }

    private static func drawPill(_ ctx: inout GraphicsContext, _ d: TimelineData, _ lay: Layout, x: (Date) -> CGFloat, left: CGFloat, right: CGFloat) {
        guard let pill = pillGeometry(&ctx, d, lay, x: x, left: left, right: right) else { return }
        ctx.fill(Path(roundedRect: pill.rect, cornerRadius: IterRadius.badge), with: .color(IterColor.textPrimary.color))
        ctx.draw(pill.text, at: CGPoint(x: pill.rect.midX, y: pill.rect.midY), anchor: .center)
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
            if !d.panel {
                let label = Text(verbatim: LightText.percent(fraction)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
                ctx.draw(label, at: CGPoint(x: left - IterSpace.xs, y: y(fraction)), anchor: .trailing)
            }
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
        if d.panel {
            // Percent labels inside the plot at its leading edge, over the data: under the top line, above the others.
            for fraction in [0.0, 0.5, 1.0] {
                let top = fraction == 1
                let label = Text(verbatim: LightText.percent(fraction)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
                ctx.draw(label, at: CGPoint(x: left + IterSpace.xs, y: y(fraction) + (top ? IterStroke.thin : -IterStroke.thin)),
                         anchor: top ? .topLeading : .bottomLeading)
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
                .font(selected ? IterFont.moduleTitle : IterFont.secondary)
                .foregroundStyle(w.score == nil ? IterColor.textSecondary : IterColor.textPrimary)
            let resolved = ctx.resolve(text)
            let measured = resolved.measure(in: CGSize(width: 400, height: SpotLayout.labelTier))
            var lx = x0
            if lx + measured.width > right { lx = right - measured.width }
            lx = max(d.panel ? left : left - IterSpace.sm, lx)
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
