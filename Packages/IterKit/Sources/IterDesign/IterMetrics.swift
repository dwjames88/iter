import SwiftUI

private func d(_ name: String) -> CGFloat { CGFloat(TokenValues.dimension(name)) }

/// 8-pt spacing scale. `xs` (4) is only for hairline-tight pairs; `md` (12) and `xxs` (2) stay for old code and are not used in new layout.
public enum IterSpace {
    public static let xxs = d("space/xxs")
    public static let xs = d("space/xs")
    public static let sm = d("space/sm")
    public static let md = d("space/md")
    public static let lg = d("space/lg")
    /// The standard macOS sheet margin (20).
    public static let sheet = d("space/sheet")
    public static let xl = d("space/xl")
    public static let xxl = d("space/xxl")
}

/// The invisible layout grid: lanes, insets and row heights (see Design/HIERARCHY.md).
public enum IterGrid {
    public static let unit = d("grid/unit")
    public static let inset = d("grid/inset")
    public static let laneGap = d("grid/lane/gap")
    public static let disclosureLane = d("grid/lane/disclosure")
    public static let rowSingle = d("grid/row/single")
    public static let rowDouble = d("grid/row/double")
}

/// The event unit (window symbol + score + time) and the map pin label that wraps it.
public enum IterEvent {
    public static let heightCompact = d("event/height/compact")
    public static let heightRegular = d("event/height/regular")
    public static let heightLarge = d("event/height/large")
    public static let symbolCompact = d("event/symbol/compact")
    public static let symbolRegular = d("event/symbol/regular")
    public static let symbolLarge = d("event/symbol/large")
    public static let gap = d("event/gap")
    public static let padding = d("event/padding")
    public static let paddingCompact = d("event/paddingCompact")
    public static let pinShadowRadius = d("event/pinShadowRadius")
    public static let pinShadowRadiusSelected = d("event/pinShadowRadiusSelected")
    /// A scale factor, stored as a dimension token.
    public static let pinScaleSelected = d("event/pinScaleSelected")
    /// An opacity, stored as a dimension token.
    public static let lowConfidenceOpacity = Double(TokenValues.dimension("event/lowConfidenceOpacity"))
}

/// Debug layout-grid overlay opacities (ratios stored as dimension tokens).
public enum IterDebug {
    public static let gridOpacity = Double(TokenValues.dimension("debug/gridOpacity"))
    public static let laneOpacity = Double(TokenValues.dimension("debug/laneOpacity"))
}

public enum IterRadius {
    public static let badge = d("radius/badge")
    public static let control = d("radius/control")
    public static let card = d("radius/card")
    public static let panel = d("radius/panel")
}

public enum IterSize {
    public static let badgeHeightCompact = d("size/badge/heightCompact")
    public static let badgeHeight = d("size/badge/height")
    public static let badgeHeightLarge = d("size/badge/heightLarge")
    public static let badgeMinWidth = d("size/badge/minWidth")
    public static let mapPin = d("size/mapPin")
    public static let mapPinSelected = d("size/mapPinSelected")
    public static let controlHeight = d("size/control/height")
    public static let controlHeightLarge = d("size/control/heightLarge")
    public static let hitTarget = d("size/hitTarget")
    public static let iconSmall = d("size/icon/small")
    public static let iconMedium = d("size/icon/medium")
    public static let iconLarge = d("size/icon/large")
    public static let confidenceMark = d("size/confidenceMark")
    public static let imageStripHeight = d("size/imageStripHeight")
    public static let lightRingSmall = d("size/lightRing/small")
    public static let lightRingMedium = d("size/lightRing/medium")
    public static let lightRingLarge = d("size/lightRing/large")

    public static let timelineHeight = d("chart/timelineHeight")
    public static let timelineAxisHeight = d("chart/timelineAxisHeight")
    public static let arcHeight = d("chart/arcHeight")
    public static let arcMarker = d("chart/arcMarker")
    public static let hourlyTintHeight = d("chart/hourlyTintHeight")
    public static let windowMinWidth = d("chart/windowMinWidth")

    public static let sidebarMin = d("layout/sidebarMin")
    public static let sidebarIdeal = d("layout/sidebarIdeal")
    public static let sidebarMax = d("layout/sidebarMax")
    public static let listMin = d("layout/listMin")
    public static let listIdeal = d("layout/listIdeal")
    public static let listMax = d("layout/listMax")
    public static let listColumnMin = d("layout/listColumnMin")
    public static let detailMin = d("layout/detailMin")
    public static let inspectorMin = d("layout/inspectorMin")
    public static let inspectorIdeal = d("layout/inspectorIdeal")
    public static let inspectorMax = d("layout/inspectorMax")
    public static let imageRequestWidth = d("layout/imageRequestWidth")
    public static let mainWindowMinWidth = d("layout/windowMinWidth")
    public static let windowMinHeight = d("layout/windowMinHeight")
}

public enum IterStroke {
    public static let hairline = d("stroke/hairline")
    public static let thin = d("stroke/thin")
    public static let regular = d("stroke/regular")
    public static let thick = d("stroke/thick")
    public static let route = d("stroke/route")
    public static let routeInactive = d("stroke/routeInactive")
    public static let routeCasing = d("stroke/routeCasing")
    public static let dashLength = d("stroke/dashLength")
    public static let dashGap = d("stroke/dashGap")
    public static let focusRingWidth = d("stroke/focusRingWidth")
    public static let focusRingOffset = d("stroke/focusRingOffset")
}
