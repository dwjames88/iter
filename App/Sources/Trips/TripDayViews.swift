import SwiftUI
import IterCore
import IterDesign
import IterFeatures

// MARK: - Day container

/// Where a row sits inside its day's container.
enum ContainerPosition {
    case first, middle, last, only

    var roundsTop: Bool { self == .first || self == .only }
    var roundsBottom: Bool { self == .last || self == .only }
}

/// The outline of a day container as seen by one row: the side edges, plus the top edge and corners on the first row
/// and the bottom edge and corners on the last. Rows stack with no gap, so the edges join into one rounded outline.
private struct ContainerOutline: Shape {
    let position: ContainerPosition
    let radius: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let minX = rect.minX + inset, maxX = rect.maxX - inset
        let minY = rect.minY + (position.roundsTop ? inset : 0)
        let maxY = rect.maxY - (position.roundsBottom ? inset : 0)
        let r = radius
        var path = Path()
        // Left edge, bottom to top, then across the top.
        path.move(to: CGPoint(x: minX, y: position.roundsBottom ? maxY - r : maxY))
        path.addLine(to: CGPoint(x: minX, y: position.roundsTop ? minY + r : minY))
        if position.roundsTop {
            path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
            path.addLine(to: CGPoint(x: maxX - r, y: minY))
            path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
        } else {
            path.move(to: CGPoint(x: maxX, y: minY))
        }
        // Right edge, top to bottom, then across the bottom.
        path.addLine(to: CGPoint(x: maxX, y: position.roundsBottom ? maxY - r : maxY))
        if position.roundsBottom {
            path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - r, y: maxY), radius: r)
            path.addLine(to: CGPoint(x: minX + r, y: maxY))
            path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - r), radius: r)
        }
        return path
    }
}

/// One row's slice of a day's container: a content-coloured fill with rounded top corners on the first row and rounded
/// bottom corners on the last, and a hairline outline (accent when the day is selected). Used as `listRowBackground`.
struct DayContainerBackground: View {
    let position: ContainerPosition
    var selected = false
    /// The header row sits on a slightly stronger ground than the timeline under it.
    var isHeader = false

    private var radius: CGFloat { IterRadius.card }
    private var lineWidth: CGFloat { selected ? IterStroke.regular : IterStroke.hairline }

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: position.roundsTop ? radius : 0,
                                   bottomLeadingRadius: position.roundsBottom ? radius : 0,
                                   bottomTrailingRadius: position.roundsBottom ? radius : 0,
                                   topTrailingRadius: position.roundsTop ? radius : 0,
                                   style: .continuous)
                .fill(isHeader ? AnyShapeStyle(ControlFill()) : AnyShapeStyle(ContentFill()))
            ContainerOutline(position: position, radius: radius, lineWidth: lineWidth)
                .stroke(selected ? IterColor.accent : IterColor.separator, lineWidth: lineWidth)
            if isHeader {
                // The header is set apart from the timeline by a hairline along its bottom edge.
                VStack { Spacer(minLength: 0); Rectangle().fill(IterColor.separator).frame(height: IterStroke.hairline) }
            }
        }
        .padding(.horizontal, IterSpace.md)
    }
}

// MARK: - Day header

/// The first row of a day's container: which day, the light bookends, and the day's load.
struct DayHeaderRow: View {
    let group: TripDayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                Text(TimeText.dayName(index: group.index))
                    .font(IterFont.titleSection)
                    .foregroundStyle(IterColor.textPrimary)
                Text(TimeText.longDay(group.date))
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .fixedSize(horizontal: false, vertical: true)
            bookends
            Text(LightText.dayTotals(stops: group.stopCount, drivingSeconds: group.drivingSeconds))
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IterSpace.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Sunrise and sunset with their symbols, in the zone of the day's first stop.
    @ViewBuilder private var bookends: some View {
        if group.sunrise != nil || group.sunset != nil {
            HStack(spacing: IterSpace.md) {
                if let sunrise = group.sunrise { bookend(symbol: "sunrise.fill", label: String(localized: "Sunrise", comment: "Day header: sunrise"), time: sunrise) }
                if let sunset = group.sunset { bookend(symbol: "sunset.fill", label: String(localized: "Sunset", comment: "Day header: sunset"), time: sunset) }
            }
            .font(IterFont.caption)
            .foregroundStyle(IterColor.textSecondary)
            .lineLimit(1)
        }
    }

    private func bookend(symbol: String, label: String, time: Date) -> some View {
        HStack(spacing: IterSpace.xs) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(TimeText.time(time, in: group.timeZone)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) \(TimeText.time(time, in: group.timeZone))", comment: "VoiceOver: a day's sunrise or sunset and its time"))
    }
}

/// A day's conflicts in one line, under the header. Each conflict is spelled out on its own stop or drive.
struct DayConflictRow: View {
    let count: Int

    var body: some View {
        Label {
            Text("^[\(count) conflict](inflect: true) on this day", comment: "Day summary: how many schedule conflicts the day has")
                .font(IterFont.subheadline)
                .foregroundStyle(IterColor.textPrimary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IterSpace.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Overnight boundary

/// Between two day containers: where you sleep. Not selectable and not a drop target.
struct OvernightBoundaryRow: View {
    let boundary: OvernightBoundary

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            Rectangle().fill(IterColor.separator).frame(height: IterStroke.hairline)
            Label {
                Text(ConnectorText.overnight(near: boundary.place)).lineLimit(1)
            } icon: {
                Image(systemName: "moon.stars")
            }
            .font(IterFont.captionStrong)
            .foregroundStyle(IterColor.textSecondary)
            .fixedSize()
            Rectangle().fill(IterColor.separator).frame(height: IterStroke.hairline)
        }
        .padding(.vertical, IterSpace.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Overview strip

/// One cell per day, side by side: the day's name and date, its stops, its best window and a conflict mark.
/// Selecting a cell selects that day everywhere (list, map).
struct TripOverviewStrip: View {
    let cells: [TripOverviewCell]
    let selectedDay: Int?
    let select: (Int) -> Void

    private static let minCellWidth: CGFloat = 104

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: IterSpace.xs) { cellViews(flexible: true) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IterSpace.xs) { cellViews(flexible: false) }
            }
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.vertical, IterSpace.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Trip days", comment: "Accessibility label of the trip overview strip"))
    }

    private func cellViews(flexible: Bool) -> some View {
        ForEach(cells) { cell in
            Button { select(cell.index) } label: {
                OverviewCellView(cell: cell, isSelected: cell.index == selectedDay)
                    .frame(minWidth: Self.minCellWidth, maxWidth: flexible ? .infinity : Self.minCellWidth, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(Text("Show this day", comment: "Tooltip"))
            .accessibilityLabel(OverviewCellView.accessibilityText(cell))
            .accessibilityAddTraits(cell.index == selectedDay ? .isSelected : [])
        }
    }
}

private struct OverviewCellView: View {
    let cell: TripOverviewCell
    let isSelected: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            HStack(spacing: IterSpace.xs) {
                Text(TimeText.dayName(index: cell.index)).font(IterFont.captionStrong).foregroundStyle(IterColor.textPrimary)
                Spacer(minLength: 0)
                if cell.hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.warning)
                        .help(Text("This day has schedule conflicts", comment: "Tooltip"))
                }
            }
            Text(TimeText.shortDay(cell.date)).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            if cell.stopCount > 0 {
                Text(stopsText).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                bestWindow
            } else {
                Text("No stops", comment: "Overview cell of a day with no stops")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
            }
        }
        .lineLimit(1)
        .padding(IterSpace.sm)
        .background(isSelected ? AnyShapeStyle(IterColor.accent.opacity(0.14)) : AnyShapeStyle(ContentFill()), in: shape)
        .overlay(shape.strokeBorder(isSelected ? IterColor.accent : IterColor.separator,
                                    lineWidth: isSelected ? IterStroke.regular : IterStroke.hairline))
        .contentShape(shape)
    }

    private var stopsText: String {
        InflectedCount.string("stop", count: cell.stopCount) { AttributedString(localized: "^[\(cell.stopCount) stop](inflect: true)") }
    }

    /// The day's best window as the event unit (symbol, score and start time in one capsule).
    @ViewBuilder private var bestWindow: some View {
        if let best = cell.bestWindow {
            EventScore(window: best.window, zone: best.zone, timeStyle: .start, variant: .compact)
        }
    }

    /// The VoiceOver label, built once per cell value (a cell is rebuilt only when its day changes).
    private static var spoken: [Int: (cell: TripOverviewCell, locale: String, text: String)] = [:]

    static func accessibilityText(_ cell: TripOverviewCell) -> Text {
        let locale = Locale.current.identifier
        if let hit = spoken[cell.index], hit.cell == cell, hit.locale == locale { return Text(hit.text) }
        let text = spokenText(cell)
        spoken[cell.index] = (cell, locale, text)
        return Text(text)
    }

    private static func spokenText(_ cell: TripOverviewCell) -> String {
        var parts = [String(localized: "\(TimeText.dayName(index: cell.index)), \(TimeText.longDay(cell.date))", comment: "VoiceOver: an overview cell's day")]
        if cell.stopCount == 0 {
            parts.append(String(localized: "No stops", comment: "VoiceOver: a day with no stops"))
        } else {
            parts.append(InflectedCount.string("stop", count: cell.stopCount) { AttributedString(localized: "^[\(cell.stopCount) stop](inflect: true)") })
            if let best = cell.bestWindow {
                parts.append(String(localized: "Best light: \(LightText.accessibilityDescription(best.window)) at \(TimeText.time(best.window.span.start, in: best.zone))",
                                    comment: "VoiceOver: the day's best window and its start time"))
            }
        }
        if cell.hasConflict {
            parts.append(InflectedCount.string("conflict", count: cell.conflictCount) { AttributedString(localized: "^[\(cell.conflictCount) conflict](inflect: true)") })
        }
        return parts.joined(separator: ", ")
    }
}
