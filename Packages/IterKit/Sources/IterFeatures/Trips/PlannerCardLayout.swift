import CoreGraphics

/// Where the Mac trip planner card sits and how wide it is, decided from the window's width. Pure, so the thresholds,
/// the 40 % rule and the hysteresis are unit-tested; the view only measures and applies it.
///
/// Widths are of the WINDOW's content (sidebar included when it is showing), because the detail area alone moves with
/// the sidebar. The view reports the detail width too, since the card's own size is a share of that area.
///
/// - `wide` (window of 1440 pt or more): the centred card, 62 % of the detail area between 560 and 800 pt.
/// - `capped` (1100 up to 1440): still centred, but narrowed so the visible map (the detail area less the card) is at
///   least 40 % of the window.
/// - `side` (under 1100): Apple Maps' inspector card docked to the leading edge, as the Explore list card, with the map
///   to its trailing side.
public struct PlannerCardLayout: Equatable, Sendable {
    public enum Mode: Int, Equatable, Sendable, Comparable {
        case side, capped, wide
        public static func < (a: Mode, b: Mode) -> Bool { a.rawValue < b.rawValue }
    }

    public var mode: Mode
    /// The card's width in points.
    public var cardWidth: CGFloat

    /// Window width from which the wide card is used.
    public static let wideThreshold: CGFloat = 1440
    /// Window width from which the card is centred rather than docked.
    public static let sideThreshold: CGFloat = 1100
    /// A mode is kept this far (points) below the threshold that entered it, so a live resize at a threshold does not flap.
    public static let hysteresis: CGFloat = 8
    /// The share of the window the visible map keeps in `capped` mode.
    public static let minMapShare: CGFloat = 0.4
    /// The wide card: a share of the detail area, kept between these.
    public static let wideMin: CGFloat = 560
    public static let wideMax: CGFloat = 800
    public static let wideFraction: CGFloat = 0.62
    /// The card's margin to the window, as `FloatingPanelLayout.margin`.
    public static let margin: CGFloat = 8

    /// - Parameters:
    ///   - windowWidth: the window's content width.
    ///   - detailWidth: the width of the area the card floats in (the window less the sidebar when it shows).
    ///   - previous: the mode in use now, for the hysteresis; nil decides from the thresholds alone.
    ///   - sideWidth: the docked card's ideal width (the list column's).
    ///   - floorWidth: the narrowest the card may be.
    ///   - detailMin: the narrowest the map beside a docked card may be.
    public static func resolve(windowWidth: CGFloat, detailWidth: CGFloat, previous: Mode? = nil,
                               sideWidth: CGFloat = 360, floorWidth: CGFloat = 340, detailMin: CGFloat = 420) -> PlannerCardLayout {
        let mode = mode(windowWidth: windowWidth, previous: previous)
        switch mode {
        case .side:
            return PlannerCardLayout(mode: .side, cardWidth: max(floorWidth, min(sideWidth, detailWidth - 2 * margin - detailMin)))
        case .wide:
            return PlannerCardLayout(mode: .wide, cardWidth: wideWidth(detailWidth: detailWidth, floorWidth: floorWidth))
        case .capped:
            let mapCap = detailWidth - minMapShare * windowWidth
            let width = min(wideWidth(detailWidth: detailWidth, floorWidth: floorWidth), mapCap)
            return PlannerCardLayout(mode: .capped, cardWidth: max(floorWidth, width))
        }
    }

    /// The mode for a window width, with `previous` held until the width is `hysteresis` below the threshold that entered it.
    public static func mode(windowWidth: CGFloat, previous: Mode? = nil) -> Mode {
        let held = (previous ?? .side)
        func reaches(_ threshold: CGFloat, _ mode: Mode) -> Bool {
            windowWidth >= (held >= mode ? threshold - hysteresis : threshold)
        }
        if reaches(wideThreshold, .wide) { return .wide }
        if reaches(sideThreshold, .capped) { return .capped }
        return .side
    }

    private static func wideWidth(detailWidth: CGFloat, floorWidth: CGFloat) -> CGFloat {
        max(floorWidth, min(max(wideMin, min(wideMax, detailWidth * wideFraction)), detailWidth - 2 * margin))
    }
}
