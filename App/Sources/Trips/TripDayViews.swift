import SwiftUI
import IterCore
import IterDesign
import IterFeatures

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
// TODO(w6): iOS only (AppiOS/Sources/Trips/TripDayList.swift); the Mac uses `OvernightNote` and the transfer card.
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
// TODO(w6): iOS only (AppiOS/Sources/Trips/TripBuilderScreen.swift); the Mac uses `DaySelector`.
struct TripOverviewStrip: View {
    let cells: [TripOverviewCell]
    let selectedDay: Int?
    /// Adds an All Days cell first (the Mac card, where the map has no switcher of its own).
    var selectAll: (() -> Void)?
    let select: (Int) -> Void

    private static let minCellWidth: CGFloat = 104

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: IterSpace.xs) { cellViews(flexible: true) }
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IterSpace.xs) { cellViews(flexible: false) }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.vertical, IterSpace.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Trip days", comment: "Accessibility label of the trip overview strip"))
    }

    @ViewBuilder private func cellViews(flexible: Bool) -> some View {
        if let selectAll {
            Button(action: selectAll) {
                AllDaysCellView(cells: cells, isSelected: selectedDay == nil, minWidth: Self.minCellWidth, flexible: flexible)
            }
            .buttonStyle(.plain)
            .help(Text("Show every day on the map", comment: "Tooltip"))
            .accessibilityAddTraits(selectedDay == nil ? .isSelected : [])
        }
        ForEach(cells) { cell in
            Button { select(cell.index) } label: {
                OverviewCellView(cell: cell, isSelected: cell.index == selectedDay, minWidth: Self.minCellWidth, flexible: flexible)
            }
            .buttonStyle(.plain)
            .help(Text("Show this day", comment: "Tooltip"))
            .accessibilityLabel(OverviewCellView.accessibilityText(cell))
            .accessibilityAddTraits(cell.index == selectedDay ? .isSelected : [])
        }
    }
}

/// The strip's first cell: every day at once, which is what the map shows when no day is chosen.
private struct AllDaysCellView: View {
    let cells: [TripOverviewCell]
    let isSelected: Bool
    let minWidth: CGFloat
    let flexible: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            HStack(spacing: IterSpace.xs) {
                Image(systemName: "map").font(IterFont.captionStrong)
                Text("All Days", comment: "Overview strip: every day").font(IterFont.captionStrong)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(IterColor.accentText) : AnyShapeStyle(IterColor.textPrimary))
            Text(InflectedCount.string("day", count: cells.count) { AttributedString(localized: "^[\(cells.count) day](inflect: true)") })
                .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            Text(InflectedCount.string("stop", count: stops) { AttributedString(localized: "^[\(stops) stop](inflect: true)") })
                .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
        }
        .lineLimit(1)
        .padding(IterSpace.sm)
        // The size is the cell's own, inside its background, so every cell is as wide and as tall as its neighbours.
        .frame(minWidth: minWidth, maxWidth: flexible ? .infinity : minWidth, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? AnyShapeStyle(IterColor.accent.opacity(0.14)) : AnyShapeStyle(ContentFill()), in: shape)
        .overlay(shape.strokeBorder(isSelected ? IterColor.accent : IterColor.separator,
                                    lineWidth: isSelected ? IterStroke.thick : IterStroke.hairline))
        .contentShape(shape)
    }

    private var stops: Int { cells.reduce(0) { $0 + $1.stopCount } }
}

private struct OverviewCellView: View {
    let cell: TripOverviewCell
    let isSelected: Bool
    let minWidth: CGFloat
    let flexible: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            HStack(spacing: IterSpace.xs) {
                Text(TimeText.dayName(index: cell.index)).font(IterFont.captionStrong)
                    .foregroundStyle(isSelected ? AnyShapeStyle(IterColor.accentText) : AnyShapeStyle(IterColor.textPrimary))
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
        .frame(minWidth: minWidth, maxWidth: flexible ? .infinity : minWidth, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? AnyShapeStyle(IterColor.accent.opacity(0.14)) : AnyShapeStyle(ContentFill()), in: shape)
        .overlay(shape.strokeBorder(isSelected ? IterColor.accent : IterColor.separator,
                                    lineWidth: isSelected ? IterStroke.thick : IterStroke.hairline))
        .contentShape(shape)
    }

    private var stopsText: String {
        InflectedCount.string("stop", count: cell.stopCount) { AttributedString(localized: "^[\(cell.stopCount) stop](inflect: true)") }
    }

    /// The day's best window as the event unit (symbol, score and start time in one capsule).
    @ViewBuilder private var bestWindow: some View {
        if let best = cell.bestWindow {
            ScoreChip(window: best.window, zone: best.zone, timeStyle: .start, size: .compact)
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
