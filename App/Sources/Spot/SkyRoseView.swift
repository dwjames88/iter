import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The sky instrument, embedded in the Light through the day module under the timeline: where the sun and moon are
/// for the selected day on a top-down compass rose (the observer at the centre, the horizon on the rim, overhead at
/// the centre), with the classic view as a wedge, the strong fact about sunrise or sunset, the Sun and Moon readout
/// and a time scrubber. It shares the timeline's time through `SpotModel`, so the time itself is read once, above.
struct SkyRoseContent: View {
    let page: SpotModel
    /// Tests inject the orientation; the app reads the stored choice.
    var viewUpOverride: Bool?

    @AppStorage("iter.skyRose.viewUp") private var storedViewUp = false
    @Environment(\.spotDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    init(page: SpotModel, viewUp: Bool? = nil) {
        self.page = page
        self.viewUpOverride = viewUp
    }

    private var viewUp: Bool { (viewUpOverride ?? storedViewUp) && page.spot.facing != nil }
    private var hasFacing: Bool { page.spot.facing != nil }
    private var isPanel: Bool { density == .panel }

    /// The azimuth drawn at the top, as the shortest turn from north.
    private var rotation: Double {
        guard viewUp, let facing = page.spot.facing else { return 0 }
        var r = facing.truncatingRemainder(dividingBy: 360)
        if r > 180 { r -= 360 }
        return r
    }

    private var wide: Bool { !isPanel && width >= SpotLayout.roseMaxDiameter + IterSpace.lg + SpotLayout.roseReadoutMinWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            if hasFacing { orientationPicker }
            Text(LightText.roseFact(page.rose.fact(at: page.markerTime), in: page.timeZone))
                .font(IterFont.headline)
                .foregroundStyle(IterColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if wide {
                HStack(alignment: .top, spacing: IterSpace.lg) {
                    roseView.frame(width: SpotLayout.roseMaxDiameter, height: SpotLayout.roseMaxDiameter)
                    VStack(alignment: .leading, spacing: IterSpace.md) {
                        readout
                        key
                        TimeScrubber(page: page)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                roseView
                    .frame(maxWidth: SpotLayout.roseMaxDiameter)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                key
                readout
                TimeScrubber(page: page)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
    }

    // MARK: Pieces

    private var orientationPicker: some View {
        FullWidthSegmentedPicker(label: LightText.orientationLabel,
                                 options: [(false, LightText.northUp), (true, LightText.viewUp)],
                                 selection: Binding(get: { viewUp }, set: { storedViewUp = $0 }),
                                 help: LightText.orientationHelp)
    }

    private var key: some View {
        Text(LightText.roseKey)
            .font(IterFont.secondary)
            .foregroundStyle(IterColor.textSecondary)
    }

    private var roseView: some View {
        SkyRoseCanvas(data: Self.drawData(page, background: isPanel ? IterColor.backgroundWindow : IterColor.backgroundModule),
                      rotation: rotation, onPick: { page.setTime($0) })
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: rotation)
            .accessibilityElement()
            .accessibilityLabel(accessibilitySummary)
    }

    private var readout: some View {
        let t = page.markerTime
        let r = page.readout(at: t)
        let phase = page.rose.phase(at: t)
        return VStack(alignment: .leading, spacing: IterSpace.xs) {
            bodyLine(color: IterColor.sun, word: LightText.sunWord, detail: LightText.skyDetail(r.sun))
            bodyLine(color: IterColor.blueHour, word: LightText.moonWord, detail: LightText.moonDetail(r.moon, phase: phase))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenValue(page))
    }

    private func bodyLine(color: Color, word: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            Circle().fill(color).frame(width: IterSpace.sm, height: IterSpace.sm)
            Text(word).foregroundStyle(IterColor.textPrimary)
            Text(detail).foregroundStyle(IterColor.textSecondary)
        }
        .font(IterFont.secondary)
    }

    // MARK: Data and words

    static func drawData(_ page: SpotModel, background: Color) -> RoseDrawData {
        let r = page.readout(at: page.markerTime)
        return RoseDrawData(rose: page.rose, zone: page.timeZone, facing: page.spot.facing,
                            markerSun: r.sun, markerMoon: r.moon, background: background)
    }

    /// "18:41, golden hour. Sun 263° W, 1° up. Moon 120° ESE, 35° up, waxing gibbous, 78% lit."
    static func spokenValue(_ page: SpotModel) -> String {
        let t = page.markerTime
        let r = page.readout(at: t)
        return LightText.scrubberValue(time: TimeText.time(t, in: page.timeZone), window: page.window(at: t)?.kind,
                                       sun: r.sun, moon: r.moon, phase: page.rose.phase(at: t))
    }

    private var accessibilitySummary: String {
        let zone = page.timeZone
        var parts = [LightText.roseSummary(day: TimeText.longDay(page.day))]
        parts.append(LightText.roseFact(page.rose.fact(at: page.markerTime), in: zone))
        for event in page.rose.events {
            let time = TimeText.time(event.date, in: zone)
            let place = event.kind == .solarNoon ? LightText.altitudeUp(event.position.altitude) : LightText.degrees(event.position.azimuth)
            parts.append("\(LightText.eventName(event.kind)) \(time), \(place)")
        }
        if let facing = page.spot.facing { parts.append(LightText.facingNote(facing)) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - The canvas

/// Plain values for the rose canvas (the closure never reads the model).
struct RoseDrawData {
    var rose: SkyRose
    var zone: TimeZone
    var facing: Double?
    var markerSun: SkyPosition
    var markerMoon: SkyPosition
    var background: Color
}

/// The rose, drawn square. Animatable over `rotation` so the turn between "North up" and "View up" eases.
struct SkyRoseCanvas: View, @preconcurrency Animatable {
    var data: RoseDrawData
    var rotation: Double
    var onPick: (Date) -> Void

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                RoseRenderer.draw(&ctx, size: size, data: data, rotation: rotation)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: IterSpace.xs).onChanged { drag in
                let projection = RoseRenderer.projection(size: geo.size, rotation: rotation)
                if let hit = data.rose.nearestTime(to: drag.location, projection: projection, maxDistance: SpotLayout.roseHitDistance) {
                    onPick(hit.date)
                }
            })
        }
    }
}

// MARK: - Renderer

enum RoseRenderer {
    /// The one projection used for drawing and for hit testing.
    static func projection(size: CGSize, rotation: Double) -> RoseProjection {
        let diameter = min(size.width, size.height)
        return RoseProjection(center: CGPoint(x: size.width / 2, y: size.height / 2),
                              radius: max(0, diameter / 2 - SpotLayout.roseLabelBand), rotation: rotation)
    }

    private static func bodyColor(_ body: SkyRose.Body) -> Color { body == .sun ? IterColor.sun : IterColor.blueHour }

    /// Offsets of the tight text halo: eight points on a circle of `IterStroke.regular` + a half point.
    private static let haloOffsets: [CGSize] = (0..<8).map { i in
        let a = Double(i) * .pi / 4
        let r = IterStroke.thick
        return CGSize(width: r * CGFloat(cos(a)), height: r * CGFloat(sin(a)))
    }

    /// A line of label text that can be drawn in its own ink or in the halo colour.
    struct Line {
        var ink: AnyShapeStyle
        var make: (AnyShapeStyle) -> Text
        init<S: ShapeStyle>(ink: S, make: @escaping (AnyShapeStyle) -> Text) {
            self.ink = AnyShapeStyle(ink)
            self.make = make
        }
    }

    private static func drawText(_ ctx: inout GraphicsContext, _ line: Line, at p: CGPoint,
                                 anchor: UnitPoint, halo: Color) {
        let back = ctx.resolve(line.make(AnyShapeStyle(halo)))
        for o in haloOffsets { ctx.draw(back, at: CGPoint(x: p.x + o.width, y: p.y + o.height), anchor: anchor) }
        ctx.draw(ctx.resolve(line.make(line.ink)), at: p, anchor: anchor)
    }

    private static func measure(_ ctx: GraphicsContext, _ line: Line) -> CGSize {
        ctx.resolve(line.make(line.ink)).measure(in: CGSize(width: 300, height: 60))
    }

    private static func drawIcon(_ ctx: inout GraphicsContext, _ image: GraphicsContext.ResolvedImage, in rect: CGRect, halo: Color) {
        var back = image
        back.shading = .color(halo)
        for o in haloOffsets { ctx.draw(back, in: rect.offsetBy(dx: o.width, dy: o.height)) }
        ctx.draw(image, in: rect)
    }

    private static func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    struct RingLabel { var az: Double; var line: Line; var rect: CGRect; var cardinal: Bool }

    /// The N/E/S/W, intercardinal and degree labels in the outer band, measured.
    static func ringLabelRects(_ ctx: GraphicsContext, proj: RoseProjection) -> [RingLabel] {
        let labelRadius = proj.radius + SpotLayout.roseLabelBand / 2
        var out: [RingLabel] = []
        func add(_ az: Double, _ name: String, primary: Bool, cardinal: Bool) {
            let line = Line(ink: primary ? IterColor.textPrimary : IterColor.textSecondary) { Text(verbatim: name)
                .font(primary ? IterFont.moduleTitle : IterFont.timeSmall).foregroundStyle($0) }
            let s = measure(ctx, line), p = proj.point(azimuth: az, radius: labelRadius)
            out.append(RingLabel(az: az, line: line, rect: CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height),
                                 cardinal: cardinal))
        }
        for (az, name) in [(0.0, "N"), (90, "E"), (180, "S"), (270, "W")] { add(az, name, primary: true, cardinal: true) }
        for (az, name) in [(45.0, "NE"), (135, "SE"), (225, "SW"), (315, "NW")] { add(az, name, primary: false, cardinal: false) }
        for az in [30.0, 60, 120, 150, 210, 240, 300, 330] { add(az, "\(Int(az))", primary: false, cardinal: false) }
        return out
    }

    /// The classic-view label outside the rim at the facing azimuth. Always returns a placement: every candidate (one or
    /// two lines, slid along the rim, pulled back inside the canvas) is scored by what it breaks, and the cheapest wins.
    static func wedgeLabel(_ ctx: GraphicsContext, proj: RoseProjection, size: CGSize, facing: Double,
                           ringTexts: [RingLabel]) -> (lines: [Line], rect: CGRect)? {
        let c = proj.center, R = proj.radius
        guard R > 0 else { return nil }
        let tip = proj.point(azimuth: facing, radius: R)
        let v = CGVector(dx: (tip.x - c.x) / R, dy: (tip.y - c.y) / R)
        let t = CGVector(dx: -v.dy, dy: v.dx)
        let canvas = CGRect(origin: .zero, size: size).insetBy(dx: IterStroke.thick, dy: IterStroke.thick)
        let forms: [[Line]] = [
            [Line(ink: IterColor.textSecondary) { Text(LightText.viewShort(facing)).font(IterFont.timeSmall).foregroundStyle($0) }],
            [Line(ink: IterColor.textSecondary) { Text(LightText.viewWord).font(IterFont.timeSmall).foregroundStyle($0) },
             Line(ink: IterColor.textSecondary) { Text(LightText.degrees(facing)).font(IterFont.timeSmall).foregroundStyle($0) }]]
        var best: (lines: [Line], rect: CGRect, cost: CGFloat)?
        for lines in forms {
            let sizes = lines.map { measure(ctx, $0) }
            let w = sizes.map(\.width).max() ?? 0, h = sizes.map(\.height).reduce(0, +)
            let extent = abs(v.dx) * w / 2 + abs(v.dy) * h / 2
            let dist = R + IterSpace.xxs + extent
            for shift in stride(from: CGFloat(0), through: SpotLayout.roseLabelBand * 2, by: IterStroke.regular) {
                for sign in [1.0, -1.0] as [CGFloat] {
                    var rect = CGRect(x: c.x + v.dx * dist + t.dx * shift * sign - w / 2,
                                      y: c.y + v.dy * dist + t.dy * shift * sign - h / 2, width: w, height: h)
                    // Pull back inside the canvas; the distance moved is a cost.
                    var pulled: CGFloat = 0
                    if rect.width <= canvas.width, rect.height <= canvas.height {
                        let x = min(max(rect.minX, canvas.minX), canvas.maxX - w)
                        let y = min(max(rect.minY, canvas.minY), canvas.maxY - h)
                        pulled = abs(x - rect.minX) + abs(y - rect.minY)
                        rect.origin = CGPoint(x: x, y: y)
                    }
                    let extraLines: CGFloat = CGFloat(lines.count - 1) * 2
                    var cost: CGFloat = shift + pulled * 4 + extraLines
                    if !canvas.contains(rect) { cost += 10_000 }
                    // Over the disc.
                    let pad = rect.insetBy(dx: -IterSpace.xxs, dy: -IterSpace.xxs)
                    let closest = CGPoint(x: min(max(c.x, rect.minX), rect.maxX), y: min(max(c.y, rect.minY), rect.maxY))
                    let inside = max(0, R - hypot(closest.x - c.x, closest.y - c.y))
                    cost += inside * 20
                    for ring in ringTexts where ring.rect.intersects(pad) { cost += ring.cardinal ? 1_000 : 0 }
                    if best == nil || cost < best!.cost { best = (lines, rect, cost) }
                }
            }
        }
        return best.map { ($0.lines, $0.rect) }
    }

    /// Points every few pt along the sun and moon arcs, in canvas space, that labels should keep clear of.
    static func pathPoints(_ rose: SkyRose, proj: RoseProjection) -> [CGPoint] {
        var out: [CGPoint] = []
        for arcs in [rose.sunArcs, rose.moonArcs] {
            for arc in arcs where arc.count > 1 {
                let pts = arc.map { proj.point(azimuth: $0.position.azimuth, altitude: $0.position.altitude) }
                for (a, b) in zip(pts, pts.dropFirst()) {
                    let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / IterStroke.regular))
                    for i in 0...steps {
                        let t = CGFloat(i) / CGFloat(steps)
                        out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    }
                }
            }
        }
        return out
    }

    /// How many path points fall under a rect (grown by a few pt: stroke width and halo).
    static func pathHits(_ rect: CGRect, in points: [CGPoint]) -> Int {
        let r = rect.insetBy(dx: -IterSpace.xxs, dy: -IterSpace.xxs)
        return points.reduce(0) { $0 + (r.contains($1) ? 1 : 0) }
    }

    /// The farthest a label's edge may sit from its dot's edge.
    static let eventLabelReach: CGFloat = 20
    /// Past `eventLabelReach` (with a leader line) only a path-free spot is taken.
    static let eventLabelFarReach: CGFloat = 36

    /// Where an event label goes, next to its mark. Candidates in order: the inward side (4 to 20 pt off, up to 36 if only that is path-free), the opposite
    /// side, each slid along the rim, then the turned directions. Overlapping an obstacle or leaving the disc is never
    /// allowed; a candidate under a sun or moon path loses to any clean one, and among the dirty ones fewest hits win.
    /// `cleanOnly` drops every candidate under a path; `farReach` caps the edge-to-dot distance. With `force`, a mark with
    /// no free spot still gets its first candidate.
    static func eventLabelRect(mark: CGPoint, size: CGSize, center c: CGPoint, radius R: CGFloat, dot: CGFloat,
                               obstacles: [CGRect], pathPoints: [CGPoint], cleanOnly: Bool = false, farReach: CGFloat = eventLabelFarReach,
                               force: Bool = false) -> (rect: CGRect, gap: CGFloat, clean: Bool)? {
        var inward = CGVector(dx: c.x - mark.x, dy: c.y - mark.y)
        let len = hypot(inward.dx, inward.dy)
        inward = len < 1 ? CGVector(dx: 0, dy: 1) : CGVector(dx: inward.dx / len, dy: inward.dy / len)
        func turned(_ a: Double) -> CGVector {
            CGVector(dx: inward.dx * CGFloat(cos(a)) - inward.dy * CGFloat(sin(a)), dy: inward.dx * CGFloat(sin(a)) + inward.dy * CGFloat(cos(a)))
        }
        func extent(_ v: CGVector) -> CGFloat { abs(v.dx) * size.width / 2 + abs(v.dy) * size.height / 2 }
        // (direction, slide along the tangent, tier): tiers 0/1 are the two sides, 2 slid along the rim, 3 turned.
        // The outward side (labels over the rim, in the label band) is kept inside the square canvas instead.
        var tries: [(dir: CGVector, slide: CGFloat, tier: Int, outer: Bool)] = [(inward, 0, 0, false), (turned(.pi), 0, 1, true)]
        let tangent = CGVector(dx: -inward.dy, dy: inward.dx)
        let reach = abs(tangent.dx) * size.width / 2 + abs(tangent.dy) * size.height / 2 + dot
        for outer in [false, true] {
            for slide in stride(from: CGFloat(6), through: reach, by: 6) {
                for sign in [1, -1] as [CGFloat] { tries.append((outer ? turned(.pi) : inward, slide * sign, 2, outer)) }
            }
        }
        for a in [0.5, -0.5, 1.0, -1.0, 1.57, -1.57, 2.1, -2.1, 2.6, -2.6] as [Double] { tries.append((turned(a), 0, 3, false)) }

        let reachOut = R + SpotLayout.roseLabelBand - IterStroke.thick
        let canvas = CGRect(x: c.x - reachOut, y: c.y - reachOut, width: reachOut * 2, height: reachOut * 2)
        func within(_ r: CGRect, _ limit: CGFloat) -> Bool {
            corners(r).allSatisfy { hypot($0.x - c.x, $0.y - c.y) <= limit }
        }
        var best: (rect: CGRect, score: Int, gap: CGFloat, clean: Bool)?
        var first: (rect: CGRect, gap: CGFloat)?
        for (order, t) in tries.enumerated() {
            for gap in [4, 8, 12, 20, 28, 36] as [CGFloat] {
                let dist = extent(t.dir) + dot / 2 + gap
                let center = CGPoint(x: mark.x + t.dir.dx * dist + tangent.dx * t.slide, y: mark.y + t.dir.dy * dist + tangent.dy * t.slide)
                let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
                if first == nil { first = (rect, gap) }
                guard t.outer ? canvas.contains(rect) : within(rect, R - IterSpace.xs) else { continue }
                if obstacles.contains(where: { $0.intersects(rect.insetBy(dx: -IterStroke.thick, dy: -IterStroke.thin)) }) { continue }
                let near = CGPoint(x: min(max(mark.x, rect.minX), rect.maxX), y: min(max(mark.y, rect.minY), rect.maxY))
                let edge = hypot(near.x - mark.x, near.y - mark.y) - dot / 2
                guard edge <= farReach + IterSpace.xxs else { continue }
                let hits = pathHits(rect, in: pathPoints)
                if cleanOnly, hits > 0 { continue }
                if edge > eventLabelReach + IterSpace.xxs, hits > 0 { continue }
                let score = (hits > 0 ? 100_000 + hits * 100 : 0) + t.tier * 1_000 + order * 10 + Int(edge)
                if best == nil || score < best!.score { best = (rect, score, edge, hits == 0) }
            }
        }
        if let best { return (best.rect, best.gap, best.clean) }
        return force ? first.map { ($0.rect, $0.gap, false) } : nil
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, data d: RoseDrawData, rotation: Double,
                     onEventLabel: ((SkyRose.Event, CGRect, _ short: Bool) -> Void)? = nil) {
        let proj = projection(size: size, rotation: rotation)
        let c = proj.center
        let R = proj.radius
        guard R > 0 else { return }
        let rose = d.rose
        let bg = d.background
        func rim(_ az: Double, _ r: CGFloat) -> CGPoint { proj.point(azimuth: az, radius: r) }
        func alt(_ az: Double, _ a: Double) -> CGPoint { proj.point(azimuth: az, altitude: a) }
        func disc(_ r: CGFloat, around p: CGPoint) -> CGRect { CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2) }

        let paths = pathPoints(rose, proj: proj)

        // a. Disc and rim.
        let rimPath = Path(ellipseIn: disc(R, around: c))
        ctx.fill(rimPath, with: .color(IterColor.skyDay.opacity(SpotLayout.windowTintOpacity)))
        ctx.stroke(rimPath, with: .color(IterColor.textSecondary.color), lineWidth: IterStroke.thin)

        // b. Altitude rings (labels are placed now and drawn last).
        var obstacles: [CGRect] = []
        let ringAngle = SpotLayout.roseRingLabelAngle * .pi / 180
        var ringLabels: [(Line, CGPoint)] = []
        for altitude in [30.0, 60.0] {
            let r = R * CGFloat((90 - altitude) / 90)
            ctx.stroke(Path(ellipseIn: disc(r, around: c)), with: .color(IterColor.separator),
                       style: StrokeStyle(lineWidth: IterStroke.hairline, dash: [IterStroke.dashLength, IterStroke.dashGap]))
            let text = Line(ink: IterColor.textSecondary) { Text(verbatim: "\(Int(altitude))°").font(IterFont.timeSmall).foregroundStyle($0) }
            let s = measure(ctx, text)
            let p = CGPoint(x: c.x + r * CGFloat(sin(ringAngle)), y: c.y - r * CGFloat(cos(ringAngle)))
            ringLabels.append((text, p))
            obstacles.append(CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height)
                .insetBy(dx: -IterSpace.xs, dy: -IterSpace.xxs))
        }

        // c. Degree ring ticks, pointing inward.
        for az in stride(from: 0.0, to: 360, by: 30) {
            let cardinal = az.truncatingRemainder(dividingBy: 90) == 0
            var tick = Path()
            tick.move(to: rim(az, R))
            tick.addLine(to: rim(az, R - (cardinal ? IterSpace.sm : IterSpace.xs)))
            ctx.stroke(tick, with: .color(cardinal ? IterColor.textSecondary.color : IterColor.separator), lineWidth: IterStroke.thin)
        }

        // d. Labels in the outer band, upright. The classic-view label sits just outside the rim at the facing azimuth;
        // ring labels it would touch are skipped, except the cardinals, which make it slide along the rim instead.
        let ringTexts = ringLabelRects(ctx, proj: proj)
        var wedgeText: (lines: [Line], rect: CGRect)?
        if let facing = d.facing { wedgeText = wedgeLabel(ctx, proj: proj, size: size, facing: facing, ringTexts: ringTexts) }
        // Obstacles for labels: the observer, the markers and the event dots.
        let dot = SpotLayout.roseEventDot
        let marker = IterSize.arcMarker
        func markPoint(_ e: SkyRose.Event) -> CGPoint {
            e.kind == .solarNoon ? alt(e.position.azimuth, e.position.altitude) : alt(e.position.azimuth, 0)
        }
        obstacles.append(disc(SpotLayout.roseObserverDot, around: c))
        // Only the cardinals are fixed; an event label next to a degree or intercardinal label takes its place.
        for label in ringTexts where label.cardinal { obstacles.append(label.rect.insetBy(dx: -IterSpace.xxs, dy: -IterSpace.xxs)) }
        if let wedgeText { obstacles.append(wedgeText.rect.insetBy(dx: -IterSpace.xxs, dy: -IterSpace.xxs)) }
        for e in rose.events { obstacles.append(disc(dot / 2 + IterStroke.thin, around: markPoint(e))) }
        for p in [d.markerSun, d.markerMoon] where p.altitude >= 0 {
            obstacles.append(disc(marker / 2 + IterStroke.regular, around: alt(p.azimuth, p.altitude)))
        }

        // Event labels: sun first, then moon; each sits beside its dot, clear of the paths where it can.
        let iconSide = IterSpace.md
        struct EventLabel {
            var event: SkyRose.Event
            var icon: GraphicsContext.ResolvedImage
            var time: Line
            var detail: Line
            var line1Width: CGFloat
            var line1Height: CGFloat
            var rect: CGRect
            var mark: CGPoint
            var leader: Bool
        }
        var placedLabels: [EventLabel] = []
        func placeEvents(_ events: [SkyRose.Event]) {
        for e in events {
            var icon = ctx.resolve(Image(systemName: LightText.roseSymbol(e.kind)))
            icon.shading = .color(bodyColor(e.body))
            let timeString = TimeText.time(e.date, in: d.zone)
            let time = Line(ink: IterColor.textPrimary) { Text(timeString).font(IterFont.timeSmall).foregroundStyle($0) }
            let detailText = e.kind == .solarNoon ? LightText.altitudeUp(e.position.altitude) : LightText.degrees(e.position.azimuth)
            let detailFull = Line(ink: IterColor.textSecondary) { Text(detailText).font(IterFont.timeSmall).foregroundStyle($0) }
            // The short form drops the compass word ("241°"); the Sun and Moon fact lines keep it.
            let shortText = LightText.degreesShort(e.position.azimuth)
            let detailShort = Line(ink: IterColor.textSecondary) { Text(shortText).font(IterFont.timeSmall).foregroundStyle($0) }
            let ts = measure(ctx, time)
            let line1 = iconSide + IterSpace.xxs + ts.width
            let h1 = max(ts.height, iconSide)
            func labelSize(_ detail: Line) -> CGSize {
                let ds = measure(ctx, detail)
                return CGSize(width: max(line1, ds.width), height: h1 + ds.height)
            }
            let mark = markPoint(e)
            func place(_ detail: Line, cleanOnly: Bool, farReach: CGFloat = eventLabelFarReach, force: Bool = false) -> (rect: CGRect, gap: CGFloat, clean: Bool)? {
                eventLabelRect(mark: mark, size: labelSize(detail), center: c, radius: R, dot: dot, obstacles: obstacles,
                               pathPoints: paths, cleanOnly: cleanOnly, farReach: farReach, force: force)
            }
            // A clean spot for the full label; else for the short one; else the short one with the fewest path hits within
            // the near reach. Sun labels always get a spot; a moon label with none is left out.
            let canShorten = e.kind != .solarNoon
            var detail = detailFull
            var short = false
            var found = place(detailFull, cleanOnly: true)
            if found == nil, canShorten, let p = place(detailShort, cleanOnly: true) { found = p; detail = detailShort; short = true }
            if found == nil {
                if canShorten { detail = detailShort; short = true }
                found = place(detail, cleanOnly: false, farReach: eventLabelReach, force: e.body == .sun)
            }
            guard let pick = found else { continue }
            obstacles.append(pick.rect.insetBy(dx: -IterSpace.xs, dy: -IterSpace.xxs))
            onEventLabel?(e, pick.rect, short)
            placedLabels.append(EventLabel(event: e, icon: icon, time: time, detail: detail, line1Width: line1, line1Height: h1,
                                           rect: pick.rect, mark: mark, leader: pick.gap > 10))
        }
        }

        // Sun labels first, then the moon's.
        placeEvents(rose.events.filter { $0.body == .sun })
        placeEvents(rose.events.filter { $0.body == .moon })

        for label in ringTexts {
            if !label.cardinal, placedLabels.contains(where: { $0.rect.intersects(label.rect.insetBy(dx: -IterSpace.xxs, dy: -IterSpace.xxs)) }) { continue }
            if let w = wedgeText, !label.cardinal, label.rect.intersects(w.rect.insetBy(dx: -IterSpace.xxs, dy: -IterSpace.xxs)) { continue }
            drawText(&ctx, label.line, at: CGPoint(x: label.rect.midX, y: label.rect.midY), anchor: .center, halo: bg)
        }

        // e. Classic view wedge.
        if let facing = d.facing {
            let half = SkyRose.viewHalfWidth
            var wedge = Path()
            wedge.move(to: c)
            for step in stride(from: -half, through: half, by: 1) { wedge.addLine(to: rim(facing + step, R)) }
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(IterColor.textPrimary.color.opacity(SpotLayout.roseWedgeOpacity)))
            var edges = Path()
            edges.move(to: rim(facing - half, R)); edges.addLine(to: c); edges.addLine(to: rim(facing + half, R))
            ctx.stroke(edges, with: .color(IterColor.textSecondary.color), lineWidth: IterStroke.hairline)
        }

        // f. Paths: the moon under the sun, continuous.
        func stroke(_ arcs: [[SkyRose.Sample]], color: Color) {
            for arc in arcs where arc.count > 1 {
                var path = Path()
                for (i, s) in arc.enumerated() {
                    let p = alt(s.position.azimuth, s.position.altitude)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: IterStroke.thick, lineCap: .round, lineJoin: .round))
            }
        }
        stroke(rose.moonArcs, color: IterColor.blueHour)
        stroke(rose.sunArcs, color: IterColor.sun)

        // Sight lines.
        let bodies: [(SkyPosition, Color)] = [(d.markerMoon, IterColor.blueHour), (d.markerSun, IterColor.sun)]
        for (p, color) in bodies where p.altitude >= 0 {
            var line = Path()
            line.move(to: c); line.addLine(to: alt(p.azimuth, p.altitude))
            ctx.stroke(line, with: .color(color.opacity(SpotLayout.roseSightOpacity)), lineWidth: IterStroke.hairline)
        }

        // Text over the paths, with a tight halo.
        for (text, p) in ringLabels { drawText(&ctx, text, at: p, anchor: .center, halo: bg) }
        if let wedgeText {
            var y = wedgeText.rect.minY
            for line in wedgeText.lines {
                let h = measure(ctx, line).height
                drawText(&ctx, line, at: CGPoint(x: wedgeText.rect.midX, y: y + h / 2), anchor: .center, halo: bg)
                y += h
            }
        }

        // g. Event marks and labels.
        for e in rose.events {
            ctx.fill(Path(ellipseIn: disc(dot / 2, around: markPoint(e))), with: .color(bodyColor(e.body)))
        }
        for label in placedLabels {
            let r = label.rect
            if label.leader {
                let edge = CGPoint(x: min(max(label.mark.x, r.minX), r.maxX), y: min(max(label.mark.y, r.minY), r.maxY))
                var line = Path()
                line.move(to: label.mark); line.addLine(to: edge)
                ctx.stroke(line, with: .color(bodyColor(label.event.body).opacity(0.6)), lineWidth: IterStroke.hairline)
            }
            let x0 = r.midX - label.line1Width / 2
            let iconRect = CGRect(x: x0, y: r.minY + (label.line1Height - iconSide) / 2, width: iconSide, height: iconSide).fittingSymbol(label.icon.size)
            drawIcon(&ctx, label.icon, in: iconRect, halo: bg)
            drawText(&ctx, label.time, at: CGPoint(x: x0 + iconSide + IterSpace.xxs, y: r.minY + label.line1Height / 2), anchor: .leading, halo: bg)
            drawText(&ctx, label.detail, at: CGPoint(x: r.midX, y: r.minY + label.line1Height), anchor: .top, halo: bg)
        }

        // h. Observer.
        ctx.fill(Path(ellipseIn: disc(SpotLayout.roseObserverDot / 2, around: c)), with: .color(IterColor.textPrimary.color))

        // i. Markers at the shared time. A body below the horizon is a hollow ring just inside the rim.
        for (p, color) in bodies {
            if p.altitude >= 0 {
                let rect = disc(marker / 2, around: alt(p.azimuth, p.altitude))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -IterStroke.regular / 2, dy: -IterStroke.regular / 2)),
                           with: .color(bg), lineWidth: IterStroke.regular)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                let rect = disc(marker / 2, around: rim(p.azimuth, R - marker / 2 - IterStroke.thin))
                ctx.fill(Path(ellipseIn: rect), with: .color(bg.opacity(0.8)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.5)), lineWidth: IterStroke.regular)
            }
        }
    }
}

private extension CGRect {
    /// The largest rectangle with a symbol's aspect ratio inside this one, centred.
    func fittingSymbol(_ size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(width / size.width, height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: midX - w / 2, y: midY - h / 2, width: w, height: h)
    }
}
