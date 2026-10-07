import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Plain values for the arc canvas.
struct ArcData {
    var sun: [(azimuth: Double, altitude: Double)]
    var moon: [(azimuth: Double, altitude: Double)]
    var yMax: Double
    var facing: Double?
    var sunrise: (azimuth: Double, label: String)?
    var sunset: (azimuth: Double, label: String)?
    var markerSun: SkyPosition
    var markerMoon: SkyPosition
}

/// The sky instrument (patterns #17, #23): where the sun and moon are, by compass direction and height, for the
/// selected day, with markers at the same time the timeline shows.
struct SkyArcSection: View {
    let page: SpotModel

    var body: some View {
        let data = Self.data(page)
        let t = page.markerTime
        ModuleCard(title: LightText.skyTitle, symbol: "moon.stars") {
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    Canvas { ctx, size in ArcRenderer.draw(&ctx, size: size, data: data) }
                        .frame(height: ArcRenderer.height)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilitySummary(data, time: t))
                    legend
                    Text(LightText.sunAt(time: TimeText.time(t, in: page.timeZone), sun: data.markerSun))
                        .font(IterFont.headline)
                    if let note = LightText.frameNote(sun: data.markerSun, facing: data.facing) {
                        Text(note).font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                    }
                    moonRow
                }
        }
    }

    private var legend: some View {
        HStack(spacing: IterSpace.lg) {
            HStack(spacing: IterSpace.xs) {
                Circle().fill(IterColor.sun).frame(width: IterSpace.sm, height: IterSpace.sm)
                Text(LightText.sunLegend)
            }
            HStack(spacing: IterSpace.xs) {
                Circle().fill(IterColor.moon).frame(width: IterSpace.sm, height: IterSpace.sm)
                Text(LightText.moonLegend)
            }
            if page.spot.facing != nil {
                HStack(spacing: IterSpace.xs) {
                    Rectangle().fill(IterColor.accent).frame(width: IterStroke.thick, height: IterSpace.lg)
                    Text("Classic view", comment: "Sky arc legend for the facing direction")
                }
            }
            Spacer()
        }
        .font(IterFont.secondary)
        .foregroundStyle(IterColor.textSecondary)
    }

    private var moonRow: some View {
        let phase = page.dayLight.moonPhase
        return HStack(spacing: IterSpace.sm) {
            Image(systemName: LightText.moonSymbol(phase.name))
                .font(.system(size: IterSize.iconLarge))
                .foregroundStyle(IterColor.textPrimary)
                .accessibilityHidden(true)
            Text(LightText.moonLine(phase: phase, events: page.dayLight.moon, in: page.timeZone))
                .font(IterFont.body)
                .foregroundStyle(IterColor.textSecondary)
        }
    }

    static func data(_ page: SpotModel) -> ArcData {
        let paths = page.paths
        let sun = paths.sun.map { (azimuth: $0.position.azimuth, altitude: $0.position.altitude) }
        let moon = paths.moon.map { (azimuth: $0.position.azimuth, altitude: $0.position.altitude) }
        let highest = max(sun.map(\.altitude).max() ?? 0, moon.map(\.altitude).max() ?? 0)
        let yMax = min(90, max(60, (highest / 10).rounded(.up) * 10 + 10))
        let zone = page.timeZone
        func event(_ date: Date?, _ phrase: (String) -> String) -> (azimuth: Double, label: String)? {
            guard let date else { return nil }
            return (page.app.ephemeris.sunPosition(at: date, coordinate: page.spot.coordinate).azimuth, phrase(TimeText.time(date, in: zone)))
        }
        let r = page.readout(at: page.markerTime)
        return ArcData(sun: sun, moon: moon, yMax: yMax, facing: page.spot.facing,
                       sunrise: event(page.dayLight.sun.sunrise, LightText.sunriseOnArc),
                       sunset: event(page.dayLight.sun.sunset, LightText.sunsetOnArc),
                       markerSun: r.sun, markerMoon: r.moon)
    }

    private func accessibilitySummary(_ data: ArcData, time: Date) -> String {
        var parts = [String(localized: "Sun and moon for \(TimeText.longDay(page.day))", comment: "VoiceOver: sky arc label")]
        if let rise = data.sunrise { parts.append("\(rise.label), \(LightText.degrees(rise.azimuth))") }
        if let set = data.sunset { parts.append("\(set.label), \(LightText.degrees(set.azimuth))") }
        if let facing = page.spot.facing { parts.append(LightText.facingNote(facing)) }
        parts.append(LightText.sunAt(time: TimeText.time(time, in: page.timeZone), sun: data.markerSun))
        return parts.joined(separator: ". ")
    }
}

enum ArcRenderer {
    /// Lowest altitude drawn: far enough below the horizon to show twilight.
    static let yMin = -20.0
    /// Space above the plot for the facing label and the y-axis title.
    static let topBand: CGFloat = SpotLayout.labelTier + IterSpace.xs
    /// Space below the plot for compass labels and the x-axis title.
    static let bottomBand: CGFloat = IterSize.timelineAxisHeight + SpotLayout.labelTier
    static var height: CGFloat { topBand + IterSize.arcHeight + bottomBand }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, data d: ArcData) {
        let left = SpotLayout.gutter
        let right = size.width - SpotLayout.rightInset
        let top = topBand
        let bottom = top + IterSize.arcHeight
        let plot = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard plot.width > 0 else { return }
        let yMin = Self.yMin
        func x(_ azimuth: Double) -> CGFloat { left + CGFloat(azimuth / 360) * plot.width }
        func y(_ altitude: Double) -> CGFloat { bottom - CGFloat((altitude - yMin) / (d.yMax - yMin)) * plot.height }

        // Sky above the horizon, ground below.
        let horizon = y(0)
        ctx.fill(Path(CGRect(x: left, y: top, width: plot.width, height: horizon - top)), with: .color(IterColor.skyDay.opacity(SpotLayout.windowTintOpacity)))
        ctx.fill(Path(CGRect(x: left, y: horizon, width: plot.width, height: bottom - horizon)), with: .color(IterColor.skyNight.opacity(SpotLayout.windowTintOpacity / 2)))
        ctx.stroke(Path(plot), with: .color(IterColor.separator), lineWidth: IterStroke.hairline)

        // Height gridlines every 30 degrees, labelled.
        for altitude in stride(from: 30.0, through: d.yMax, by: 30.0) {
            var grid = Path()
            grid.move(to: CGPoint(x: left, y: y(altitude)))
            grid.addLine(to: CGPoint(x: right, y: y(altitude)))
            ctx.stroke(grid, with: .color(IterColor.separator), lineWidth: IterStroke.hairline)
            ctx.draw(Text(verbatim: "\(Int(altitude))°").font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary),
                     at: CGPoint(x: left - IterSpace.xs, y: y(altitude)), anchor: .trailing)
        }
        ctx.draw(Text(verbatim: "0°").font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary),
                 at: CGPoint(x: left - IterSpace.xs, y: horizon), anchor: .trailing)
        var horizonLine = Path()
        horizonLine.move(to: CGPoint(x: left, y: horizon))
        horizonLine.addLine(to: CGPoint(x: right, y: horizon))
        ctx.stroke(horizonLine, with: .color(IterColor.textSecondary.color), lineWidth: IterStroke.thin)
        ctx.draw(Text(LightText.horizon).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary),
                 at: CGPoint(x: left + IterSpace.xs, y: horizon - IterSpace.xs), anchor: .bottomLeading)

        // Compass along the bottom: north at both ends because the sky is a circle.
        for (azimuth, name) in [(0.0, "N"), (90.0, "E"), (180.0, "S"), (270.0, "W"), (360.0, "N")] {
            var tick = Path()
            tick.move(to: CGPoint(x: x(azimuth), y: bottom))
            tick.addLine(to: CGPoint(x: x(azimuth), y: bottom + IterSpace.xs))
            ctx.stroke(tick, with: .color(IterColor.textSecondary.color), lineWidth: IterStroke.thin)
            ctx.draw(Text(verbatim: name).font(IterFont.moduleTitle).foregroundStyle(IterColor.textPrimary),
                     at: CGPoint(x: x(azimuth), y: bottom + IterSpace.xs), anchor: .top)
        }
        for azimuth in [45.0, 135.0, 225.0, 315.0] {
            var tick = Path()
            tick.move(to: CGPoint(x: x(azimuth), y: bottom))
            tick.addLine(to: CGPoint(x: x(azimuth), y: bottom + IterSpace.xs))
            ctx.stroke(tick, with: .color(IterColor.separator), lineWidth: IterStroke.thin)
        }
        ctx.draw(Text(LightText.arcAxisX).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary),
                 at: CGPoint(x: plot.midX, y: size.height), anchor: .bottom)
        ctx.draw(Text(LightText.arcAxisY).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary),
                 at: CGPoint(x: left + IterSpace.xs, y: top + IterSpace.xs), anchor: .topLeading)

        // The direction the classic composition faces.
        if let facing = d.facing {
            var line = Path()
            line.move(to: CGPoint(x: x(facing), y: top))
            line.addLine(to: CGPoint(x: x(facing), y: bottom))
            ctx.stroke(line, with: .color(IterColor.accent), style: StrokeStyle(lineWidth: IterStroke.regular, dash: [IterStroke.dashLength, IterStroke.dashGap]))
            let label = ctx.resolve(Text(LightText.facingNote(facing)).font(IterFont.moduleTitle).foregroundStyle(IterColor.accentText))
            let w = label.measure(in: CGSize(width: 600, height: 40)).width
            let lx = min(max(left, x(facing) - w / 2), right - w)
            ctx.draw(label, at: CGPoint(x: lx + w / 2, y: top - IterSpace.xs), anchor: .bottom)
        }

        // Sunrise and sunset directions, labelled on the horizon.
        for event in [d.sunrise, d.sunset].compactMap({ $0 }) {
            let ex = x(event.azimuth)
            var mark = Path()
            mark.move(to: CGPoint(x: ex, y: horizon - IterSpace.xs))
            mark.addLine(to: CGPoint(x: ex, y: horizon + IterSpace.xs))
            ctx.stroke(mark, with: .color(IterColor.textPrimary.color), lineWidth: IterStroke.thick)
            let line1 = ctx.resolve(Text(event.label).font(IterFont.secondary).foregroundStyle(IterColor.textPrimary))
            let line2 = ctx.resolve(Text(LightText.degrees(event.azimuth)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary))
            let w = max(line1.measure(in: CGSize(width: 400, height: 40)).width, line2.measure(in: CGSize(width: 400, height: 40)).width)
            let lx = min(max(left, ex - w / 2), right - w)
            ctx.draw(line1, at: CGPoint(x: lx + w / 2, y: horizon + IterSpace.xs + IterSpace.xs), anchor: .top)
            ctx.draw(line2, at: CGPoint(x: lx + w / 2, y: horizon + IterSpace.xs + IterSpace.xs + SpotLayout.labelTier - IterSpace.xs), anchor: .top)
        }

        // Paths. Segments that wrap through north or sink below the plot are not joined.
        ctx.drawLayer { layer in
            layer.clip(to: Path(plot))
            func stroke(_ points: [(azimuth: Double, altitude: Double)], minAltitude: Double, color: Color, width: CGFloat, dimBelowHorizon: Bool) {
                for (a, b) in zip(points, points.dropFirst()) {
                    guard a.altitude >= minAltitude, b.altitude >= minAltitude, abs(a.azimuth - b.azimuth) < 180 else { continue }
                    var segment = Path()
                    segment.move(to: CGPoint(x: x(a.azimuth), y: y(a.altitude)))
                    segment.addLine(to: CGPoint(x: x(b.azimuth), y: y(b.altitude)))
                    let below = dimBelowHorizon && (a.altitude + b.altitude) / 2 < 0
                    layer.stroke(segment, with: .color(color.opacity(below ? SpotLayout.belowHorizonOpacity : 1)),
                                 style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            stroke(d.moon, minAltitude: 0, color: IterColor.moon, width: IterStroke.thick, dimBelowHorizon: false)
            stroke(d.sun, minAltitude: 0, color: IterColor.textPrimary.color, width: IterStroke.thick, dimBelowHorizon: false)
        }

        // Markers at the shared time.
        let diameter = IterSize.arcMarker
        if d.markerMoon.altitude >= 0 {
            let c = CGPoint(x: x(d.markerMoon.azimuth), y: y(d.markerMoon.altitude))
            let rect = CGRect(x: c.x - diameter / 2, y: c.y - diameter / 2, width: diameter, height: diameter)
            ctx.fill(Path(ellipseIn: rect), with: .color(IterColor.moon))
            ctx.stroke(Path(ellipseIn: rect), with: .color(IterColor.backgroundWindow), lineWidth: IterStroke.regular)
        }
        if d.markerSun.altitude >= yMin {
            let c = CGPoint(x: x(d.markerSun.azimuth), y: y(d.markerSun.altitude))
            let rect = CGRect(x: c.x - diameter / 2, y: c.y - diameter / 2, width: diameter, height: diameter)
            if d.markerSun.altitude >= 0 {
                ctx.fill(Path(ellipseIn: rect), with: .color(IterColor.sun))
                ctx.stroke(Path(ellipseIn: rect), with: .color(IterColor.backgroundWindow), lineWidth: IterStroke.regular)
            } else {
                ctx.fill(Path(ellipseIn: rect), with: .color(IterColor.backgroundWindow))
                ctx.stroke(Path(ellipseIn: rect), with: .color(IterColor.sun), lineWidth: IterStroke.thick)
            }
        }
    }
}
