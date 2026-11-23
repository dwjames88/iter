import SwiftUI
import IterModel
import IterGoActivity
import IterUI

/// What is left of the trip: today's stops, then each later day under its heading. Times are in each stop's own zone.
struct GoScheduleSection: View {
    let snapshot: GoSnapshot
    let now: Date

    var body: some View {
        let days = GoFlow.groupByDay(GoFlow.scheduleItems(snapshot))
        if let first = days.first {
            VStack(alignment: .leading, spacing: IterSpace.md) {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: IterSpace.sm) {
                        Text(GoFlow.dayHeading(group: day, first: first, now: now))
                            .font(IterFont.headline)
                            .foregroundStyle(IterColor.textPrimary)
                            .padding(.horizontal, IterSpace.xs)
                        VStack(spacing: 0) {
                            ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, IterSpace.xl + IterSpace.md) }
                                GoScheduleRow(item: item, now: now)
                            }
                        }
                        .goScreenCard()
                    }
                }
            }
        }
    }
}

/// One stop: number, name, its light window and start, and on the right when to leave (or arrive), or that it is late.
struct GoScheduleRow: View {
    let item: GoScheduleItem
    let now: Date

    var body: some View {
        let zone = GoFlow.zone(item.stop)
        HStack(alignment: .center, spacing: IterSpace.md) {
            NumberBadge(number: item.stop.number, size: IterSize.iconLarge + IterSpace.xs)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(item.stop.name)
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let kind = item.stop.windowKind {
                    HStack(spacing: IterSpace.xs) {
                        Image(systemName: LightText.symbol(kind)).accessibilityHidden(true)
                        Text(windowLine(kind: kind, zone: zone))
                    }
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                }
            }
            Spacer(minLength: IterSpace.sm)
            trailing(zone: zone)
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: IterSize.hitTarget)
        .accessibilityElement(children: .combine)
    }

    private func windowLine(kind: LightWindowKind, zone: TimeZone) -> String {
        guard let start = item.stop.windowStart else { return LightText.shortName(kind) }
        return "\(LightText.shortName(kind)) \(TimeText.time(start, in: zone))"
    }

    @ViewBuilder private func trailing(zone: TimeZone) -> some View {
        VStack(alignment: .trailing, spacing: IterSpace.xxs) {
            switch item.status {
            case .late:
                Label("Late", systemImage: "exclamationmark.triangle.fill")
                    .font(IterFont.headline).foregroundStyle(IterColor.warning)
                timeWord(zone: zone)
            case .missed:
                Label("Missed", systemImage: "clock.badge.xmark")
                    .font(IterFont.headline).foregroundStyle(IterColor.warning)
            case .leaveNow:
                Text("Leave now").font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
            default:
                timeWord(zone: zone)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }

    @ViewBuilder private func timeWord(zone: TimeZone) -> some View {
        if let leaveBy = item.leaveBy {
            Text("Leave \(TimeText.time(leaveBy, in: zone))")
                .font(item.status == .late ? IterFont.subheadline : IterFont.headline)
                .foregroundStyle(item.status == .late ? IterColor.textSecondary : IterColor.textPrimary)
        } else if let arrival = item.arrival {
            Text("Arrive \(TimeText.time(arrival, in: zone))")
                .font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
        }
    }
}
