import SwiftUI
import IterModel
import IterGoActivity
import IterUI

/// The run is over: what happened at each stop. One Done button returns to the start view.
public struct GoFinishedView: View {
    let snapshot: GoSnapshot
    let done: () -> Void
    @Environment(\.goFlatButtons) private var flat

    public init(snapshot: GoSnapshot, done: @escaping () -> Void) {
        self.snapshot = snapshot
        self.done = done
    }

    public var body: some View {
        let stops = snapshot.summary?.stops ?? []
        ScrollView {
            VStack(spacing: IterSpace.md) {
                header(stops: stops)
                if !stops.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            if index > 0 { Divider().padding(.leading, IterSpace.xl + IterSpace.md) }
                            GoFinishedRow(stop: stop, fallback: snapshot.generatedAt)
                        }
                    }
                    .goScreenCard()
                }
            }
            .padding(.horizontal, IterSpace.lg)
            .padding(.bottom, IterSpace.lg)
        }
    }

    private func header(stops: [GoTripSummary.Stop]) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(snapshot.tripName.isEmpty ? "Trip finished" : snapshot.tripName)
                    .font(IterFont.titleSection)
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(stops: stops))
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { done() } label: {
                Text("Done").font(IterFont.headline).frame(maxWidth: .infinity, minHeight: IterSize.hitTarget)
            }
            .goProminentButton(flat: flat)
        }
        .goScreenCard()
    }

    private func subtitle(stops: [GoTripSummary.Stop]) -> String {
        let photoStops = stops.filter { $0.windowKind != nil }
        let shot = photoStops.filter { $0.outcome == .shot }.count
        var parts: [String] = []
        if let span = dateSpan(stops) { parts.append(span) }
        if !photoStops.isEmpty { parts.append("\(shot) of \(photoStops.count) shot") }
        if let meters = snapshot.summary?.drivenMeters { parts.append("\(TimeText.distance(meters: meters)) driven") }
        return parts.joined(separator: " · ")
    }

    private func dateSpan(_ stops: [GoTripSummary.Stop]) -> String? {
        guard let summary = snapshot.summary, let start = summary.startedAt else { return nil }
        let zone = stops.first.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
        let first = LocalDay(start, in: zone)
        let last = LocalDay(summary.endedAt ?? start, in: zone)
        return first == last ? TimeText.day(first) : "\(TimeText.day(first)) – \(TimeText.day(last))"
    }
}

struct GoFinishedRow: View {
    let stop: GoTripSummary.Stop
    let fallback: Date

    var body: some View {
        let zone = TimeZone(identifier: stop.timeZoneIdentifier) ?? .current
        HStack(alignment: .center, spacing: IterSpace.md) {
            NumberBadge(number: stop.number, size: IterSize.iconLarge + IterSpace.xs)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(stop.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                outcomeLabel
                if let line = timesLine(zone: zone) {
                    Text(line).font(IterFont.subheadline).monospacedDigit().foregroundStyle(IterColor.textSecondary)
                }
            }
            Spacer(minLength: IterSpace.sm)
            if let kind = stop.windowKind, let score = stop.score {
                ScoreChip(kind: kind, start: stop.arrivedAt ?? fallback, score: score, zone: zone, size: .small, timeStyle: .none)
            }
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: IterSize.hitTarget)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var outcomeLabel: some View {
        switch stop.outcome {
        case .shot where stop.windowKind == nil:
            // A lodging or waypoint stop is visited, not shot.
            Label("Visited", systemImage: "checkmark").font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
        case .shot:
            Label("Shot", systemImage: "camera.fill").font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
        case .skipped:
            Label("Skipped", systemImage: "forward.fill").font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
        case .missed:
            Label("Missed", systemImage: "clock.badge.xmark").font(IterFont.subheadline).foregroundStyle(IterColor.warning)
        }
    }

    private func timesLine(zone: TimeZone) -> String? {
        switch (stop.arrivedAt, stop.leftAt) {
        case let (a?, l?): "\(TimeText.time(a, in: zone)) – \(TimeText.time(l, in: zone))"
        case let (a?, nil): "Arrived \(TimeText.time(a, in: zone))"
        default: nil
        }
    }
}
