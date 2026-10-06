import SwiftUI

private func d(_ name: String) -> CGFloat { CGFloat(TokenValues.dimension(name)) }

/// 4-pt base spacing (with one half step).
public enum IterSpace {
    public static let xxs = d("space/xxs")
    public static let xs = d("space/xs")
    public static let sm = d("space/sm")
    public static let md = d("space/md")
    public static let lg = d("space/lg")
    public static let xl = d("space/xl")
    public static let xxl = d("space/xxl")
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
    public static let placeCardImageHeight = d("size/placeCardImageHeight")
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
    public static let placeCardWidth = d("layout/placeCardWidth")
    public static let placeCardMaxHeight = d("layout/placeCardMaxHeight")
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
