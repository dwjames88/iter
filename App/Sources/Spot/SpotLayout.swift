import SwiftUI
import IterDesign

/// Shared measures for the spot page, all derived from tokens. The timeline, the hourly strip and the arc use the
/// same left gutter and right inset, so their x-axes line up (critique C21).
enum SpotLayout {
    /// Comfortable reading width for the single column.
    static let contentMaxWidth: CGFloat = IterSize.listMax + IterSize.inspectorMax
    /// Left gutter: y-axis labels on the timeline, row labels on the hourly strip.
    static let gutter: CGFloat = IterGrid.unit * 5
    static let rightInset: CGFloat = IterGrid.inset
    /// One tier of bracket labels above the sky strip.
    static let labelTier: CGFloat = IterSpace.lg
    static let bracketDrop: CGFloat = IterSpace.xs
    static let tickLength: CGFloat = IterSpace.xs
    /// Height of the cloud and rain plot.
    static let plotHeight: CGFloat = IterSize.hourlyTintHeight * 2
    /// Panel density (the Explore column's place panel): the sky band and the cloud and rain plot are taller, since the
    /// timeline is the panel's centrepiece and has no label gutter. 88 and 112.
    static let panelSkyHeight: CGFloat = IterGrid.unit * 11
    static let panelPlotHeight: CGFloat = IterGrid.unit * 14
    /// Below this column width (the list column's minimum, 340, plus a little) the timeline's "Drag to read any time" hint is dropped.
    static let panelHintMinWidth: CGFloat = 350
    /// Rows of the hourly strip.
    static let hourlyRow: CGFloat = IterGrid.unit * 3

    static let windowTintOpacity = 0.2
    static let selectedFillOpacity = 0.16
    static let cloudFillOpacity = 0.5
    static let belowHorizonOpacity = 0.35

    // MARK: Compass rose
    /// Widest the rose is drawn (45 grid units). Narrower columns draw it at their width.
    static let roseMaxDiameter: CGFloat = IterGrid.unit * 45
    /// Outer band that holds the compass labels (5 grid units: room for the classic-view label outside the rim).
    static let roseLabelBand: CGFloat = IterGrid.unit * 5
    /// How near a drag must be to a path to pick a time on it.
    static let roseHitDistance: CGFloat = IterGrid.unit * 3
    /// Event marks on the rim and the observer dot at the centre.
    static let roseEventDot: CGFloat = IterSpace.xs + IterSpace.xxs
    static let roseObserverDot: CGFloat = IterSpace.xs
    /// Fixed screen angle (clockwise from straight up) where the altitude rings carry their labels.
    static let roseRingLabelAngle: Double = 22.5
    static let roseWedgeOpacity = 0.07
    static let roseSightOpacity = 0.4
    /// Page density: the readout column beside the rose needs at least this much width.
    static let roseReadoutMinWidth: CGFloat = IterGrid.unit * 25

    // MARK: Time scrubber
    static let scrubberTrack: CGFloat = IterGrid.unit
    #if os(iOS)
    static let scrubberThumb: CGFloat = IterSize.hitTarget
    static let scrubberHit: CGFloat = IterGrid.unit * 5.5
    #else
    static let scrubberThumb: CGFloat = IterGrid.unit * 2
    static let scrubberHit: CGFloat = IterSize.hitTarget
    #endif
    static let scrubberKeyStep = 15
    static let scrubberKeyStepLarge = 60
}

/// Where the spot page's sections are drawn. `.page` is the full spot page; `.panel` is the Explore column's place
/// panel (340 to 520 pt wide) where sections drop page-only chrome, fit the width they are given, and the light
/// timeline is drawn wide (no label gutter, a taller band and plot). Module titles sit on the panel's 16 pt inset
/// with no card fill; lists of windows keep a filled card.
enum SpotDensity: Sendable { case page, panel }

extension EnvironmentValues {
    @Entry var spotDensity: SpotDensity = .page
}

/// A module card (the Weather idiom): a quiet title with a leading symbol inside the card at its top-left, an optional
/// control at the title row's trailing edge, then the content 8 below. Fill `background/module`, no border.
/// `flush` lets a list inside run edge to edge of the card (its rows carry their own 16 pt inset), so the lanes
/// measured from the card edge match the layout grid overlay.
struct ModuleCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    var flush = false
    @Environment(\.spotDensity) private var density
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, symbol: String, flush: Bool = false,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.flush = flush
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        if density == .panel { panelBody } else { cardBody }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            titleRow
                .padding(.horizontal, flush ? IterGrid.inset : 0)
            content
        }
        .padding(.horizontal, flush ? 0 : IterGrid.inset)
        .padding(.top, IterGrid.inset)
        .padding(.bottom, flush ? IterSpace.sm : IterGrid.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// In the panel the title sits on the column's 16 pt inset and the content runs the column's full inset width (so
    /// the timeline gets all the room). A flush list (window rows) keeps its filled card, 16 in from the column edge.
    private var panelBody: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            titleRow
                .padding(.horizontal, IterGrid.inset)
            if flush {
                content
                    .padding(.vertical, IterSpace.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
                    .padding(.horizontal, IterGrid.inset)
            } else {
                content
                    .padding(.horizontal, IterGrid.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// The title and its control share a row; where they do not fit side by side the control drops below.
    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                titleLabel
                Spacer(minLength: IterSpace.sm)
                accessory
            }
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                titleLabel
                accessory
            }
        }
    }

    private var titleLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title)
        }
        .font(IterFont.moduleTitle)
        .foregroundStyle(IterColor.textSecondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ModuleCard where Accessory == EmptyView {
    init(title: String, symbol: String, flush: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, flush: flush, accessory: { EmptyView() }, content: content)
    }
}
