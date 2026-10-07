import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The day as a slider under the rose: a track tinted by the light windows, a thumb at the shared marker time, hour
/// labels and the current time. It spans the whole day whatever the timeline's zoom. Drag, tap or use the arrow keys.
struct TimeScrubber: View {
    let page: SpotModel

    private var symbolRow: CGFloat { IterSpace.lg }
    private var thumb: CGFloat { SpotLayout.scrubberThumb }
    private var contentHeight: CGFloat { symbolRow + thumb + IterSpace.xs + IterSpace.lg }
    private var inset: CGFloat { thumb / 2 }

    var body: some View {
        let (start, end) = page.dayInterval
        let span = max(1, end.timeIntervalSince(start))
        let marker = page.markerTime
        let windows = page.dayLight.windows
        let now = page.app.now()
        let zone = page.timeZone
        let day = page.day
        let night = Self.nightSpans(page.rose.sun, start: start, end: end)
        return GeometryReader { geo in
            let width = geo.size.width
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, start: start, span: span, marker: marker, windows: windows, night: night, now: now, zone: zone, day: day,
                          symbolRow: symbolRow, thumb: thumb)
            }
            .frame(height: contentHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                page.setTime(Self.date(atX: drag.location.x, width: width, inset: inset, start: start, span: span))
            })
        }
        .frame(height: max(SpotLayout.scrubberHit, contentHeight))
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let large = press.modifiers.contains(.shift) || press.modifiers.contains(.option)
            let minutes = large ? SpotLayout.scrubberKeyStepLarge : SpotLayout.scrubberKeyStep
            page.stepTime(minutes: press.key == .leftArrow ? -minutes : minutes)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(LightText.timeOfDay)
        .accessibilityValue(SkyRoseContent.spokenValue(page))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page.stepTime(minutes: SpotLayout.scrubberKeyStep)
            case .decrement: page.stepTime(minutes: -SpotLayout.scrubberKeyStep)
            @unknown default: break
            }
        }
    }

    /// The night before dawn and after dusk (sun below -18°, the timeline's night colour), as the sun samples give it.
    static func nightSpans(_ sun: [SkyRose.Sample], start: Date, end: Date) -> [ClosedRange<Date>] {
        let limit = -18.0
        var out: [ClosedRange<Date>] = []
        if let first = sun.firstIndex(where: { $0.position.altitude > limit }), first > 0 {
            out.append(start...sun[first].date)
        }
        if let last = sun.lastIndex(where: { $0.position.altitude > limit }), last < sun.count - 1 {
            out.append(sun[last].date...end)
        }
        return out
    }

    static func date(atX x: CGFloat, width: CGFloat, inset: CGFloat, start: Date, span: TimeInterval) -> Date {
        let fraction = min(1, max(0, (x - inset) / max(1, width - inset * 2)))
        return start.addingTimeInterval(span * Double(fraction))
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, start: Date, span: TimeInterval, marker: Date,
                             windows: [LightWindow], night: [ClosedRange<Date>], now: Date, zone: TimeZone, day: LocalDay, symbolRow: CGFloat, thumb: CGFloat) {
        let inset = thumb / 2
        let left = inset, right = size.width - inset
        guard right > left else { return }
        func x(_ date: Date) -> CGFloat { left + CGFloat(date.timeIntervalSince(start) / span) * (right - left) }
        let trackH = SpotLayout.scrubberTrack
        let cy = symbolRow + thumb / 2
        let track = CGRect(x: left, y: cy - trackH / 2, width: right - left, height: trackH)
        let capsule = Path(roundedRect: track, cornerRadius: trackH / 2)

        ctx.fill(capsule, with: .color(IterColor.separator))
        ctx.drawLayer { layer in
            layer.clip(to: capsule)
            for n in night {
                let x0 = max(left, x(n.lowerBound)), x1 = min(right, x(n.upperBound))
                guard x1 > x0 else { continue }
                layer.fill(Path(CGRect(x: x0, y: track.minY, width: x1 - x0, height: trackH)), with: .color(IterColor.skyNight))
            }
            for w in windows {
                let x0 = max(left, x(w.span.start)), x1 = min(right, x(w.span.end))
                guard x1 > x0 else { continue }
                layer.fill(Path(CGRect(x: x0, y: track.minY, width: x1 - x0, height: trackH)), with: .color(TimelineRenderer.tint(w.kind)))
            }
        }

        // The current time: a label over a short tick.
        var nowRect: CGRect?
        if now >= start, now <= start.addingTimeInterval(span) {
            let nx = x(now)
            var tick = Path()
            tick.move(to: CGPoint(x: nx, y: symbolRow)); tick.addLine(to: CGPoint(x: nx, y: track.minY))
            ctx.stroke(tick, with: .color(IterColor.textPrimary.color), lineWidth: IterStroke.regular)
            let label = ctx.resolve(Text(LightText.nowMark).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary))
            let s = label.measure(in: CGSize(width: 100, height: 30))
            let lx = min(max(nx, left + s.width / 2), right - s.width / 2)
            ctx.draw(label, at: CGPoint(x: lx, y: symbolRow - IterStroke.thin), anchor: .bottom)
            nowRect = CGRect(x: lx - s.width / 2 - IterSpace.xs, y: 0, width: s.width + IterSpace.xs * 2, height: symbolRow)
        }

        // The window symbols in one row above the track, each over its window; where windows are close the symbols
        // are spread apart around their windows' middle, and any that would touch the "Now" mark are skipped.
        let side = IterSpace.md
        let gap = IterSpace.xxs
        let centres: [(window: LightWindow, x: CGFloat)] = windows.filter { $0.kind != .night }.compactMap { w in
            let x0 = max(left, x(w.span.start)), x1 = min(right, x(w.span.end))
            return x1 > x0 ? (w, (x0 + x1) / 2) : nil
        }.sorted { $0.x < $1.x }
        var placed = centres.map(\.x)
        for _ in 0..<centres.count {
            var i = 0
            var moved = false
            while i < placed.count {
                var j = i
                while j + 1 < placed.count, placed[j + 1] - placed[j] < side + gap { j += 1 }
                if j > i {
                    // One cluster: lay it out evenly around the mean of its windows' middles.
                    let mean = centres[i...j].map(\.x).reduce(0, +) / CGFloat(j - i + 1)
                    let step = side + gap
                    for k in i...j {
                        let target = mean + (CGFloat(k - i) - CGFloat(j - i) / 2) * step
                        if abs(placed[k] - target) > 0.01 { moved = true }
                        placed[k] = target
                    }
                }
                i = j + 1
            }
            if !moved { break }
        }
        for (k, entry) in centres.enumerated() {
            let cx = min(max(placed[k], side / 2), size.width - side / 2)
            let rect = CGRect(x: cx - side / 2, y: (symbolRow - side) / 2, width: side, height: side)
            if let nowRect, nowRect.intersects(rect) { continue }
            var icon = ctx.resolve(Image(systemName: LightText.symbol(entry.window.kind)))
            icon.shading = .color(IterColor.textSecondary.color)
            let scale = min(side / max(1, icon.size.width), side / max(1, icon.size.height))
            let fitted = CGSize(width: icon.size.width * scale, height: icon.size.height * scale)
            ctx.draw(icon, in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
        }

        // Hour labels, the end ones kept inside the edges.
        let labelY = cy + thumb / 2 + IterSpace.xs
        for hour in [0, 6, 12, 18, 24] {
            let date = day.at(hour: hour, in: zone)
            let label = ctx.resolve(Text(verbatim: LightText.hourLabel(date, in: zone)).font(IterFont.timeSmall).foregroundStyle(IterColor.textSecondary))
            let s = label.measure(in: CGSize(width: 100, height: 30))
            let tx = x(date)
            let anchor: UnitPoint = tx - s.width / 2 < 0 ? .topLeading : tx + s.width / 2 > size.width ? .topTrailing : .top
            let px = anchor == .topLeading ? 0 : anchor == .topTrailing ? size.width : tx
            ctx.draw(label, at: CGPoint(x: px, y: labelY), anchor: anchor)
        }

        // The thumb.
        let tx = x(marker)
        let thumbRect = CGRect(x: tx - thumb / 2, y: cy - thumb / 2, width: thumb, height: thumb)
        ctx.fill(Path(ellipseIn: thumbRect), with: .color(IterColor.backgroundWindow))
        ctx.stroke(Path(ellipseIn: thumbRect.insetBy(dx: IterStroke.regular / 2, dy: IterStroke.regular / 2)),
                   with: .color(IterColor.textPrimary.color), lineWidth: IterStroke.regular)
    }
}
