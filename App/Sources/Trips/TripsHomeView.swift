import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// All Trips: the home of the app. Trips first (plan 6.1-A); with none, a single clear way to start one.
struct TripsHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.presentNewTrip) private var presentNewTrip

    var body: some View {
        let summaries = home.summaries()
        Group {
            if summaries.isEmpty {
                EmptyTripsView()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: IterSize.listMin, maximum: IterSize.listIdeal), spacing: IterSpace.lg, alignment: .top)],
                              alignment: .leading, spacing: IterSpace.lg) {
                        ForEach(summaries) { summary in
                            TripCard(summary: summary)
                        }
                    }
                    .padding(IterSpace.xl)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IterColor.backgroundWindow)
        .navigationTitle(Text("All Trips", comment: "Screen title"))
        .toolbar {
            if !summaries.isEmpty {
                ToolbarItem {
                    Button { presentNewTrip() } label: {
                        Label(String(localized: "New Trip", comment: "Toolbar button"), systemImage: "plus")
                    }
                    .help(Text("New Trip (⌘N)", comment: "Tooltip"))
                }
            }
        }
        .tripFlows()
    }

    private var home: TripsHomeModel {
        TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
    }
}

// MARK: - Empty state

/// No trips: sell the app in a sentence, one primary action, and the three templates right under it (C57, C58).
private struct EmptyTripsView: View {
    @Environment(\.presentNewTrip) private var presentNewTrip

    var body: some View {
        ScrollView {
            VStack(spacing: IterSpace.xl) {
                VStack(spacing: IterSpace.sm) {
                    Text("Plan trips around the light", comment: "Empty trips screen headline")
                        .font(IterFont.titleSpot)
                        .multilineTextAlignment(.center)
                    Text("Pick your spots and days. Iter works out when to leave so you are set up before the light arrives.",
                         comment: "Empty trips screen explanation")
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { presentNewTrip() } label: {
                    Text("New Trip", comment: "Primary button on the empty trips screen")
                        .frame(minWidth: IterSize.lightRingLarge * 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    Text("Or start from a template", comment: "Heading above the trip templates")
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                    ForEach(TripTemplates.all) { template in
                        TemplateRow(template: template)
                    }
                }
                .frame(maxWidth: IterSize.listMax)
            }
            .padding(IterSpace.xxl)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TemplateRow: View {
    @Environment(\.presentNewTrip) private var presentNewTrip
    let template: TripTemplate

    var body: some View {
        Button { presentNewTrip(template: template.id) } label: {
            HStack(spacing: IterSpace.md) {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(template.defaultName).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    Text(TimeText.dayAndStops(days: template.dayCount, stops: template.stops.count))
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                    Text(spotNames)
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: IterSpace.sm)
                Image(systemName: "chevron.right")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(IterSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous)
                .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(template.defaultName), \(TimeText.dayAndStops(days: template.dayCount, stops: template.stops.count))", comment: "VoiceOver: template"))
        .accessibilityHint(Text("Starts a new trip from this template", comment: "VoiceOver hint"))
    }

    /// The first few distinct places, so the template reads as a route.
    private var spotNames: String {
        var seen = Set<String>()
        let names = template.stops.compactMap { CuratedSpots.spot(id: $0.spotID)?.name }.filter { seen.insert($0).inserted }
        let shown = names.prefix(3).formatted(.list(type: .and, width: .narrow))
        return names.count > 3 ? shown + "…" : shown
    }
}

// MARK: - Trip card

private struct TripCard: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppModel.self) private var model
    let summary: TripSummary

    var body: some View {
        Button { navigation.show(.trip(summary.id)) } label: {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                Text(summary.name)
                    .font(IterFont.titleSpot)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(TimeText.dateRange(from: summary.startDay, to: summary.endDay))
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textPrimary)
                    Text(TimeText.dayAndStops(days: summary.dayCount, stops: summary.stopCount))
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                }
                Divider()
                footer
            }
            .padding(IterSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous)
                .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let record = model.store.trip(id: summary.id) { TripContextMenu(trip: record) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the trip", comment: "VoiceOver hint"))
    }

    @ViewBuilder private var footer: some View {
        if let next = summary.next {
            Label {
                Text(LightText.nextSession(next))
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
            } icon: {
                Image(systemName: LightText.symbol(next.kind)).foregroundStyle(IterColor.textSecondary)
            }
        } else if summary.stopCount == 0 {
            // A deliberate empty card, not a missing image (C59).
            Label {
                Text("No stops yet. Open the trip to add the first.", comment: "Trip card with no stops")
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(IterColor.accent)
            }
        } else {
            Label {
                Text("All sessions have passed", comment: "Trip card when every session is in the past")
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(IterColor.textSecondary)
            }
        }
    }
}
