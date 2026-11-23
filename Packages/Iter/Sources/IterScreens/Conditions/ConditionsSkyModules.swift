import SwiftUI
import IterAstro
import IterFeatures
import IterModel
import IterSky
import IterUI

// Module 4: light through the day. The timeline (sun altitude, window spans, cloud layers) and the sun and moon compass,
// drawn in the content layer with Canvas and Path, tokens only.

struct SkyModule: View {
    let model: ConditionsModel

    var body: some View {
        ModuleCard(title: "Light Through the Day", symbol: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                TimelineBlock(model: model)
                Divider()
                CompassBlock(model: model)
                ScrubControls(model: model)
            }
        }
    }
}

// MARK: Timeline

enum TimelineLayout {
    static let gutter: CGFloat = 36
    static let rightInset: CGFloat = 12
    static let plotHeight: CGFloat = IterSize.timelineHeight
    static let band: CGFloat = 8
    static let bandGap: CGFloat = 2
    static let gap: CGFloat = 8
    static let axis: CGFloat = 14
    static var totalHeight: CGFloat { plotHeight + gap + 3 * band + 2 * bandGap + gap + axis }

    /// x for a time within the day.
    static func x(_ t: Date, start: Date, end: Date, width: CGFloat) -> CGFloat {
        let span = max(1, end.timeIntervalSince(start))
        let f = min(1, max(0, t.timeIntervalSince(start) / span))
        return gutter + CGFloat(f) * (width - gutter - rightInset)
    }
}

struct TimelineBlock: View {
    let model: ConditionsModel

    var body: some View {
        let zone = model.place.timeZone
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(verbatim: readout(zone: zone)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
            LightTimelineCanvas(timeline: model.timeline, scrub: model.scrubTime, zone: zone)
                .frame(height: TimelineLayout.totalHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Light timeline for the day. " + readout(zone: zone)))
            Text(verbatim: legend).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
        }
    }

    private func readout(zone: TimeZone) -> String {
        let t = model.timeline
        var parts: [String] = []
        if let r = t.sunrise { parts.append("Sunrise \(TimeText.time(r, in: zone))") }
        if let s = t.sunset { parts.append("Sunset \(TimeText.time(s, in: zone))") }
        return parts.isEmpty ? "The sun does not rise or set on this day" : parts.joined(separator: " \u{00B7} ")
    }

    private var legend: String {
        model.timeline.clouds.isEmpty
            ? "Sun height and light windows. Cloud layers appear with the forecast."
            : "Sun height and light windows, then high, mid and low cloud by hour."
    }
}

struct LightTimelineCanvas: View {
    let timeline: LightTimeline
    let scrub: Date
    let zone: TimeZone

    var body: some View {
        Canvas { ctx, size in
            draw(&ctx, size: size)
        }
    }

    private func skyColor(altitude a: Double) -> Color {
        let night = IterColor.skyNight, blue = IterColor.skyBlue, golden = IterColor.skyGolden, day = IterColor.skyDay
        switch a {
        case ..<(-18): return night
        case -18..<(-6): return night.mix(with: blue, by: (a + 18) / 12)
        case -6..<0: return blue.mix(with: golden, by: (a + 6) / 6 * 0.5)
        case 0..<6: return blue.mix(with: golden, by: 0.5 + a / 6 * 0.5)
        case 6..<14: return golden.mix(with: day, by: (a - 6) / 8)
        default: return day
        }
    }

    private func windowColor(_ kind: LightWindowKind) -> Color {
        switch kind {
        case .goldenMorning, .goldenEvening: IterColor.sun
        case .blueMorning, .blueEvening: IterColor.blueHour
        case .night: IterColor.moon
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let L = TimelineLayout.self
        let w = size.width
        let plot = CGRect(x: L.gutter, y: 0, width: w - L.gutter - L.rightInset, height: L.plotHeight)
        let start = timeline.dayStart, end = timeline.dayEnd
        func x(_ t: Date) -> CGFloat { L.x(t, start: start, end: end, width: w) }

        // Sky band: a gradient by the sun's altitude, left to right.
        let samples = timeline.sun
        if samples.count > 1 {
            let stops = samples.map { s in
                Gradient.Stop(color: skyColor(altitude: s.altitude), location: min(1, max(0, (x(s.time) - plot.minX) / plot.width)))
            }
            ctx.fill(Path(roundedRect: plot, cornerRadius: IterRadius.badge),
                     with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: plot.minX, y: 0), endPoint: CGPoint(x: plot.maxX, y: 0)))
        }

        // Sun altitude curve over the band, and the horizon.
        let maxAlt = max(30, (samples.map(\.altitude).max() ?? 30) + 6)
        let minAlt = -20.0
        func y(_ alt: Double) -> CGFloat { plot.maxY - CGFloat((alt - minAlt) / (maxAlt - minAlt)) * plot.height }
        var horizon = Path()
        horizon.move(to: CGPoint(x: plot.minX, y: y(0)))
        horizon.addLine(to: CGPoint(x: plot.maxX, y: y(0)))
        ctx.stroke(horizon, with: .color(IterColor.onAccent.opacity(0.55)), style: StrokeStyle(lineWidth: IterStroke.hairline, dash: [IterStroke.dashLength, IterStroke.dashGap]))
        if samples.count > 1 {
            var curve = Path()
            for (i, s) in samples.enumerated() {
                let p = CGPoint(x: x(s.time), y: y(s.altitude))
                if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            ctx.stroke(curve, with: .color(IterColor.sun), style: StrokeStyle(lineWidth: IterStroke.regular, lineCap: .round, lineJoin: .round))
        }

        // Window spans, tinted by window; the span after the skyline when terrain changes it.
        for spanInfo in timeline.windows {
            let s = spanInfo.effectiveSpan ?? spanInfo.span
            let x0 = x(max(s.start, start)), x1 = max(x(min(s.end, end)), x0 + IterSize.windowMinWidth / 2)
            let r = CGRect(x: x0, y: plot.minY, width: x1 - x0, height: plot.height)
            let color = windowColor(spanInfo.kind)
            ctx.fill(Path(roundedRect: r, cornerRadius: IterRadius.badge), with: .color(color.opacity(0.28)))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: IterRadius.badge), with: .color(color.opacity(0.9)), lineWidth: IterStroke.hairline)
            if let score = spanInfo.score, r.width >= 22 {
                ctx.draw(Text(verbatim: "\(score)").font(IterFont.timeSmall).foregroundStyle(IterColor.onAccent),
                         at: CGPoint(x: r.midX, y: r.minY + 9), anchor: .center)
            }
        }

        // Cloud layers by hour: high, mid, low, each an opacity band.
        let bandTop = plot.maxY + L.gap
        let layers: [(String, KeyPath<CloudHour, Double?>, Color)] = [
            ("High", \.high, IterColor.cloudHigh), ("Mid", \.mid, IterColor.cloudMid), ("Low", \.low, IterColor.cloudLow),
        ]
        for (i, layer) in layers.enumerated() {
            let top = bandTop + CGFloat(i) * (L.band + L.bandGap)
            ctx.draw(Text(verbatim: layer.0).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary),
                     at: CGPoint(x: L.gutter - 6, y: top + L.band / 2), anchor: .trailing)
            let track = CGRect(x: plot.minX, y: top, width: plot.width, height: L.band)
            ctx.fill(Path(roundedRect: track, cornerRadius: 2), with: .color(IterColor.skyNight.opacity(0.85)))
            for hour in timeline.clouds {
                guard let v = hour[keyPath: layer.1] else { continue }
                let x0 = x(hour.time), x1 = x(hour.time.addingTimeInterval(3600))
                guard x1 > plot.minX, x0 < plot.maxX else { continue }
                let r = CGRect(x: max(x0, plot.minX), y: top, width: min(x1, plot.maxX) - max(x0, plot.minX), height: L.band)
                ctx.fill(Path(r), with: .color(layer.2.opacity(0.15 + 0.85 * min(1, max(0, v)))))
            }
        }

        // Axis: every three hours.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let axisY = bandTop + 3 * L.band + 2 * L.bandGap + L.gap
        var t = start
        while t <= end {
            let h = cal.component(.hour, from: t)
            if h % 3 == 0 {
                ctx.draw(Text(verbatim: String(format: "%02d", h)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary),
                         at: CGPoint(x: x(t), y: axisY + L.axis / 2), anchor: .center)
            }
            t = t.addingTimeInterval(3600)
        }

        // The scrub marker.
        let mx = x(scrub)
        var marker = Path()
        marker.move(to: CGPoint(x: mx, y: plot.minY))
        marker.addLine(to: CGPoint(x: mx, y: bandTop + 3 * L.band + 2 * L.bandGap))
        ctx.stroke(marker, with: .color(IterColor.accent), lineWidth: IterStroke.regular)
        ctx.fill(Path(ellipseIn: CGRect(x: mx - 4, y: plot.minY - 1, width: 8, height: 8)), with: .color(IterColor.accent))
    }
}

// MARK: Compass

struct CompassBlock: View {
    let model: ConditionsModel

    var body: some View {
        let zone = model.place.timeZone
        let readout = model.compass
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: IterSpace.lg) {
                compass
                lines(readout: readout, zone: zone)
            }
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                compass
                lines(readout: readout, zone: zone)
            }
        }
    }

    private var compass: some View {
        SkyCompass(readout: model.compass, day: model.compassDay, horizon: model.horizon.profile, facing: model.place.facing, zone: model.place.timeZone)
            .frame(width: SkyCompass.side, height: SkyCompass.side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Sun and moon compass. " + ConditionsFormat.sunLine(model.compass) + ". " + ConditionsFormat.moonLine(model.compass, day: model.compassDay)))
    }

    private func lines(readout: CompassReadout, zone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Text(verbatim: TimeText.time(readout.time, in: zone)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
            key(IterColor.sun, ConditionsFormat.sunLine(readout))
            key(IterColor.moon, ConditionsFormat.moonLine(readout, day: model.compassDay))
            if let mw = ConditionsFormat.milkyWayLine(readout, day: model.compassDay, zone: zone) { key(IterColor.skyBlue, mw) }
            if let rs = ConditionsFormat.riseSetLine(model.compassDay, facing: model.place.facing, zone: zone, scrub: readout.time) {
                Text(verbatim: rs).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: ConditionsFormat.facingLine(model.place.facing)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: text).font(IterFont.body).foregroundStyle(IterColor.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A sky chart: the rim is the horizon, the centre is straight up, north at the top. Sun, moon and the Milky Way core sit at
/// their azimuth and altitude; rise and set marks sit on the rim; the terrain skyline is the filled ring inside the rim.
struct SkyCompass: View {
    static let side: CGFloat = 268
    static let radius: CGFloat = 86

    let readout: CompassReadout
    let day: CompassDay
    let horizon: HorizonProfile?
    let facing: Double?
    let zone: TimeZone

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size: size) }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = Self.radius
        let rim = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
        ctx.fill(rim, with: .color(IterColor.backgroundContent))

        // The view the place faces: a soft wedge.
        if let facing {
            var wedge = Path()
            wedge.move(to: c)
            wedge.addArc(center: c, radius: R, startAngle: .degrees(facing - 90 - 20), endAngle: .degrees(facing - 90 + 20), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(IterColor.accent.opacity(0.16)))
            var line = Path()
            line.move(to: c)
            line.addLine(to: ConditionsFormat.rimPoint(azimuth: facing, radius: R, center: c))
            ctx.stroke(line, with: .color(IterColor.accent.opacity(0.7)), style: StrokeStyle(lineWidth: IterStroke.hairline, dash: [IterStroke.dashLength, IterStroke.dashGap]))
        }

        // Altitude rings at 30 and 60 degrees; spokes every 90.
        for alt in [30.0, 60.0] {
            let r = R * CGFloat((90 - alt) / 90)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(IterColor.separator), lineWidth: IterStroke.hairline)
        }
        for az in stride(from: 0.0, to: 360, by: 90) {
            var spoke = Path()
            spoke.move(to: c)
            spoke.addLine(to: ConditionsFormat.rimPoint(azimuth: az, radius: R, center: c))
            ctx.stroke(spoke, with: .color(IterColor.separator), lineWidth: IterStroke.hairline)
        }

        // The terrain skyline, as the ring between the skyline and the rim.
        if let horizon, !horizon.elevationsDegrees.isEmpty {
            var ring = rim
            var sky = Path()
            let n = horizon.elevationsDegrees.count
            for i in 0..<n {
                let az = Double(i) * horizon.azimuthStepDegrees
                let p = ConditionsFormat.skyPoint(azimuth: az, altitude: max(0, horizon.elevationsDegrees[i]), radius: R, center: c)
                if i == 0 { sky.move(to: p) } else { sky.addLine(to: p) }
            }
            sky.closeSubpath()
            ring.addPath(sky)
            ctx.fill(ring, with: .color(IterColor.textSecondary.color.opacity(0.35)), style: FillStyle(eoFill: true))
            ctx.stroke(sky, with: .color(IterColor.textSecondary.color.opacity(0.8)), lineWidth: IterStroke.hairline)
        }
        ctx.stroke(rim, with: .color(IterColor.textSecondary.color.opacity(0.6)), lineWidth: IterStroke.thin)

        // Cardinal letters just inside the rim.
        for (label, az) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
            ctx.draw(Text(verbatim: label).font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary),
                     at: ConditionsFormat.rimPoint(azimuth: az, radius: R - 11, center: c), anchor: .center)
        }

        // Rise and set marks on the rim; the sun's carry its time just outside.
        for (point, isSun) in [(day.sunrise, true), (day.sunset, true), (day.moonrise, false), (day.moonset, false)] {
            guard let point else { continue }
            let p = ConditionsFormat.rimPoint(azimuth: point.azimuth, radius: R, center: c)
            let color = isSun ? IterColor.sun : IterColor.moon
            let dot = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            if isSun { ctx.fill(Path(ellipseIn: dot), with: .color(color)) } else {
                ctx.fill(Path(ellipseIn: dot), with: .color(IterColor.backgroundContent))
                ctx.stroke(Path(ellipseIn: dot), with: .color(color), lineWidth: IterStroke.regular)
            }
            if isSun {
                ctx.draw(Text(verbatim: TimeText.time(point.time, in: zone)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary),
                         at: ConditionsFormat.rimPoint(azimuth: point.azimuth, radius: R + 18, center: c), anchor: .center)
            }
        }

        // The Milky Way core, then the moon, then the sun on top.
        let core = readout.milkyWayCore
        if core.altitude > 0 {
            let p = ConditionsFormat.skyPoint(azimuth: core.azimuth, altitude: core.altitude, radius: R, center: c)
            var diamond = Path()
            diamond.move(to: CGPoint(x: p.x, y: p.y - 6)); diamond.addLine(to: CGPoint(x: p.x + 6, y: p.y))
            diamond.addLine(to: CGPoint(x: p.x, y: p.y + 6)); diamond.addLine(to: CGPoint(x: p.x - 6, y: p.y)); diamond.closeSubpath()
            ctx.fill(diamond, with: .color(IterColor.skyBlue.opacity(readout.coreIsInDark ? 1 : 0.5)))
        }
        marker(&ctx, readout.moon, color: IterColor.moon, center: c, radius: 6)
        marker(&ctx, readout.sun, color: IterColor.sun, center: c, radius: 7)
    }

    /// A filled disc above the horizon; a hollow, faded ring just outside the rim below it.
    private func marker(_ ctx: inout GraphicsContext, _ pos: SkyPosition, color: Color, center c: CGPoint, radius: CGFloat) {
        let p = ConditionsFormat.skyPoint(azimuth: pos.azimuth, altitude: pos.altitude, radius: Self.radius, center: c)
        let r = CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius)
        if pos.altitude > 0 {
            ctx.fill(Path(ellipseIn: r), with: .color(color))
            ctx.stroke(Path(ellipseIn: r), with: .color(IterColor.backgroundContent), lineWidth: IterStroke.regular)
        } else {
            ctx.stroke(Path(ellipseIn: r), with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: IterStroke.regular, dash: [2, 2]))
        }
    }
}

// MARK: Scrubbing

struct ScrubControls: View {
    let model: ConditionsModel

    var body: some View {
        let zone = model.place.timeZone
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Slider(value: Binding(get: { model.scrubTime.timeIntervalSince1970 }, set: { model.scrubTime = Date(timeIntervalSince1970: $0) }),
                   in: model.timeline.dayStart.timeIntervalSince1970...max(model.timeline.dayEnd.timeIntervalSince1970, model.timeline.dayStart.timeIntervalSince1970 + 1)) {
                Text("Time of day")
            } minimumValueLabel: {
                Text(verbatim: "00").font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
            } maximumValueLabel: {
                Text(verbatim: "24").font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary)
            }
            .accessibilityValue(Text(verbatim: TimeText.time(model.scrubTime, in: zone)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IterSpace.sm) {
                    if model.selectedDayIsToday {
                        Button { model.scrubToNow() } label: { Label("Now", systemImage: "location.north.line") }
                    }
                    ForEach(model.timeline.windows.sorted { $0.span.start < $1.span.start }) { w in
                        Button { model.scrub(toWindow: w.kind) } label: {
                            Label { Text(verbatim: LightText.shortName(w.kind)) } icon: { WindowSymbol(kind: w.kind, font: .system(size: 12)) }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
