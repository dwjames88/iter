import SwiftUI
import IterCore
import IterDesign

extension EnvironmentValues {
    /// Debug ▸ Show Layout Grid. Set once at the window root (`IterApp`), so snapshot tests can set it too.
    @Entry var showsLayoutGrid: Bool = false
}

/// One column guide: `width` points wide, starting `x` points from the leading or the trailing edge of the view.
struct LayoutLane: Hashable, Sendable {
    enum Edge: Hashable, Sendable { case leading, trailing }
    var edge: Edge
    var x: CGFloat
    var width: CGFloat

    init(edge: Edge = .leading, x: CGFloat, width: CGFloat) {
        self.edge = edge
        self.x = x
        self.width = width
    }

    /// The lane's horizontal extent in a view of `totalWidth`.
    func range(in totalWidth: CGFloat) -> ClosedRange<CGFloat> {
        switch edge {
        case .leading: x...(x + width)
        case .trailing: (totalWidth - x - width)...(totalWidth - x)
        }
    }
}

extension LayoutLane {
    /// The trailing lanes of a standard list row, from the measured widths (the order, left to right, is
    /// disclosure, label (flexible), event unit with its time inside, band and confidence). The last lane ends `IterGrid.inset`
    /// from the trailing edge, and lanes are `IterGrid.laneGap` apart. `disclosure` adds the leading chevron lane
    /// after the inset.
    @MainActor
    static func standardRowLanes(disclosure: Bool, event: EventScore.Variant, band: Bool, time: TimeStyle) -> [LayoutLane] {
        var lanes: [LayoutLane] = []
        if disclosure {
            lanes.append(LayoutLane(edge: .leading, x: IterGrid.inset, width: IterGrid.disclosureLane))
        }
        var x = IterGrid.inset
        func add(_ width: CGFloat) {
            guard width > 0 else { return }
            lanes.append(LayoutLane(edge: .trailing, x: x, width: width))
            x += width + IterGrid.laneGap
        }
        if band { add(BandConfidence.laneWidth) }
        add(EventScore.unitWidth(event, timeStyle: time))
        return lanes
    }
}

extension View {
    /// When Debug ▸ Show Layout Grid is on, draws the 8 pt grid, the inset edges and the given lane bands over this
    /// view. It never takes clicks. Off, it adds nothing.
    func layoutGrid(lanes: [LayoutLane] = [], inset: CGFloat = IterGrid.inset) -> some View {
        modifier(LayoutGridModifier(lanes: lanes, inset: inset))
    }
}

private struct LayoutGridModifier: ViewModifier {
    let lanes: [LayoutLane]
    let inset: CGFloat
    @Environment(\.showsLayoutGrid) private var shows

    func body(content: Content) -> some View {
        content.overlay {
            if shows { LayoutGridCanvas(lanes: lanes, inset: inset).allowsHitTesting(false) }
        }
    }
}

private struct LayoutGridCanvas: View {
    let lanes: [LayoutLane]
    let inset: CGFloat

    var body: some View {
        Canvas { context, size in
            let grid = IterColor.debugGrid
            let lane = IterColor.debugLane
            let hairline = IterStroke.hairline
            let unit = IterGrid.unit

            // Lane bands first, so lines sit on top.
            for l in lanes {
                let r = l.range(in: size.width)
                context.fill(Path(CGRect(x: r.lowerBound, y: 0, width: r.upperBound - r.lowerBound, height: size.height)),
                             with: .color(lane.opacity(IterDebug.laneOpacity)))
                for edge in [r.lowerBound, r.upperBound] {
                    var p = Path()
                    p.move(to: CGPoint(x: edge, y: 0))
                    p.addLine(to: CGPoint(x: edge, y: size.height))
                    context.stroke(p, with: .color(lane), lineWidth: hairline)
                }
            }

            // The 8 pt grid.
            var lines = Path()
            var x: CGFloat = 0
            while x <= size.width {
                lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height)); x += unit
            }
            var y: CGFloat = 0
            while y <= size.height {
                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y)); y += unit
            }
            context.stroke(lines, with: .color(grid.opacity(IterDebug.gridOpacity)), lineWidth: hairline)

            // The inset edges, stronger.
            var edges = Path()
            for ex in [inset, size.width - inset] {
                edges.move(to: CGPoint(x: ex, y: 0)); edges.addLine(to: CGPoint(x: ex, y: size.height))
            }
            context.stroke(edges, with: .color(grid.opacity(IterDebug.gridOpacity * 4)), lineWidth: IterStroke.thin)
        }
    }
}
