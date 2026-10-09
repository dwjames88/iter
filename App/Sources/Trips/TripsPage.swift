import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Which slice of the trips the page shows.
enum TripsPageMode: Equatable {
    case all
    case pinned
    case folder(UUID)
}

/// The body of All Trips on the Mac and iPad/iPhone: a centred column with the hero, then Pinned trips, folder tiles and
/// the other trips as full-width grids. Scrolling belongs to the host.
struct TripsPageContent: View {
    let overview: TripsOverview
    let today: LocalDay
    var mode: TripsPageMode = .all
    @Binding var prompt: TripNamePrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxl) {
            switch mode {
            case .all:
                if let hero = overview.hero { TripHeroView(entry: hero, today: today, prompt: $prompt) }
                if !overview.pinned.isEmpty {
                    group(String(localized: "Pinned", comment: "Trips group")) { tripCards(overview.pinned) }
                }
                if !overview.folders.isEmpty {
                    group(String(localized: "Folders", comment: "Trips group")) {
                        ForEach(overview.folders) { TripFolderTileView(tile: $0, prompt: $prompt) }
                    }
                }
                if !overview.others.isEmpty {
                    let hasOthers = overview.hero != nil || !overview.pinned.isEmpty || !overview.folders.isEmpty
                    UnfileDropGroup {
                        group(hasOthers ? String(localized: "Trips", comment: "Trips group") : nil) { tripCards(overview.others) }
                    }
                }
            case .pinned:
                group(nil) { tripCards(overview.pinned) }
            case .folder(let id):
                let entries = overview.folders.first { $0.id == id }?.entries ?? []
                if entries.isEmpty {
                    Text("Drag trips here, or use a trip's Move to Folder menu.", comment: "Empty trip folder")
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget + IterSpace.xxl)
                        .background(ContentFill(), in: RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous))
                } else {
                    group(nil) { tripCards(entries) }
                }
            }
        }
        .frame(maxWidth: TripsMetrics.columnMax)
        .padding(.horizontal, TripsMetrics.margin)
        .padding(.vertical, IterSpace.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func tripCards(_ entries: [TripEntry]) -> some View {
        ForEach(entries) { TripCardView(entry: $0, prompt: $prompt) }
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            if let title {
                Text(title)
                    .font(IterFont.titleSection)
                    .foregroundStyle(IterColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: TripsMetrics.gridMinimum), spacing: IterSpace.lg, alignment: .top)],
                      alignment: .leading, spacing: IterSpace.lg) {
                content()
            }
        }
    }
}

/// A trip dropped anywhere on the unfiled group leaves its folder.
private struct UnfileDropGroup<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        content.dropDestination(for: LibraryDragItem.self) { items, _ in
            let trips = items.compactMap(\.tripID).compactMap { model.store.trip(id: $0) }.filter { $0.folder != nil }
            guard !trips.isEmpty else { return false }
            model.store.moveTrips(trips, to: nil, index: nil)
            return true
        }
    }
}

// MARK: - Empty state

/// No trips yet: a small illustration, one sentence, the one primary action, and the templates as picture cards.
struct TripsEmptyState: View {
    let plan: (_ templateID: String?) -> Void

    var body: some View {
        VStack(spacing: IterSpace.xxl) {
            VStack(spacing: IterSpace.lg) {
                Image(systemName: "sun.horizon.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 52))
                    .frame(width: 112, height: 112)
                    .background(ModuleFill(), in: RoundedRectangle(cornerRadius: TripsMetrics.corner * 1.2, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: IterSpace.sm) {
                    Text("Plan Trips Around the Light", comment: "Empty trips screen headline")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("Pick your spots and days. Iter works out when to leave so you are set up before the light arrives.",
                         comment: "Empty trips screen explanation")
                        .font(IterFont.body)
                        .foregroundStyle(IterColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480)
                }
                Button { plan(nil) } label: {
                    Text("Plan a Trip", comment: "Primary button on the empty trips screen")
                        .frame(minWidth: IterSize.lightRingLarge * 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(IterColor.accent)
                .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: IterSpace.md) {
                Text("Or Start from a Template", comment: "Heading above the trip templates")
                    .font(IterFont.titleSection)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: IterSpace.lg, alignment: .top)],
                          alignment: .leading, spacing: IterSpace.lg) {
                    ForEach(TripTemplates.all) { template in
                        TemplateCard(template: template) { plan(template.id) }
                    }
                }
            }
        }
        .frame(maxWidth: TripsMetrics.columnMax)
        .padding(.horizontal, TripsMetrics.margin)
        .padding(.vertical, IterSpace.xxl)
        .frame(maxWidth: .infinity)
    }
}

private struct TemplateCard: View {
    let template: TripTemplate
    let start: () -> Void

    var body: some View {
        TripTile(action: start) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(template.defaultName)
                    .font(IterFont.titleSpot)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                Text(TimeText.dayAndStops(days: template.dayCount, stops: template.stops.count))
                    .font(IterFont.callout)
                    .foregroundStyle(IterColor.textSecondary)
                Text(spotNames)
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(2)
            }
        } bottom: {
            TripCover(spot: template.stops.first.flatMap { CuratedSpots.spot(id: $0.spotID) })
        }
        .accessibilityElement(children: .combine)
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
