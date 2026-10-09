import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The body of All Trips on the Mac and iPad/iPhone: a centred column with the hero, then groups of trip cards. Scrolling
/// belongs to the host.
struct TripsPageContent: View {
    let overview: TripsOverview
    let today: LocalDay
    @Binding var prompt: TripNamePrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxl) {
            if let hero = overview.hero {
                TripHeroView(entry: hero, today: today, prompt: $prompt)
            }
            ForEach(overview.sections) { section in
                TripsSectionView(section: section, prompt: $prompt)
            }
        }
        .frame(maxWidth: TripsMetrics.columnMax)
        .padding(.horizontal, TripsMetrics.margin)
        .padding(.vertical, IterSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

/// One group: header (with the folder menu), then the grid. A folder, or Other Trips, takes trips dropped on it.
struct TripsSectionView: View {
    @Environment(AppModel.self) private var model
    let section: TripsSection
    @Binding var prompt: TripNamePrompt?
    @State private var isTargeted = false

    private var acceptsDrops: Bool { section.kind != .pinned }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            if let title = section.title { header(title) }
            if section.entries.isEmpty {
                emptyFolder
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: TripsMetrics.gridMinimum), spacing: IterSpace.lg, alignment: .top)],
                          alignment: .leading, spacing: IterSpace.lg) {
                    ForEach(section.entries) { entry in
                        TripCardView(entry: entry, prompt: $prompt)
                    }
                }
            }
        }
        .padding(IterSpace.sm)
        .padding(-IterSpace.sm)
        .background {
            if isTargeted {
                RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous)
                    .fill(IterColor.selection)
                    .padding(-IterSpace.md)
            }
        }
        .animation(.smooth(duration: 0.15), value: isTargeted)
        .dropDestination(for: LibraryDragItem.self) { items, _ in
            guard acceptsDrops else { return false }
            let trips = items.compactMap(\.tripID).compactMap { model.store.trip(id: $0) }
            guard !trips.isEmpty else { return false }
            let folder = section.folderID.flatMap { model.store.folder(id: $0) }
            model.store.moveTrips(trips, to: folder, index: nil)
            return true
        } isTargeted: { isTargeted = acceptsDrops && $0 }
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: IterSpace.sm) {
            Label {
                Text(title).font(IterFont.titleSection)
            } icon: {
                Image(systemName: symbol).font(IterFont.headline)
            }
            .foregroundStyle(IterColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: IterSpace.sm)
            if let folderID = section.folderID {
                Menu {
                    TripFolderMenu(folderID: folderID, prompt: $prompt)
                } label: {
                    Label(String(localized: "Folder Options", comment: "Folder header menu"), systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                #if os(macOS)
                .menuStyle(.button)
                .buttonStyle(.borderless)
                #endif
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .contextMenu {
            if let folderID = section.folderID { TripFolderMenu(folderID: folderID, prompt: $prompt) }
        }
    }

    private var symbol: String {
        switch section.kind {
        case .pinned: "pin.fill"
        case .folder: "folder.fill"
        case .other: "tray.full.fill"
        }
    }

    private var emptyFolder: some View {
        Text("Drag trips here to file them in this folder.", comment: "Empty trip folder on the All Trips page")
            .font(IterFont.callout)
            .foregroundStyle(IterColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget + IterSpace.xl)
            .background(ContentFill(), in: RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous))
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
    @State private var isHovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TripsMetrics.corner, style: .continuous) }

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: 0) {
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
                .padding(IterSpace.lg + IterSpace.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                TripCover(spot: template.stops.first.flatMap { CuratedSpots.spot(id: $0.spotID) })
                    .frame(height: 96)
                    .clipShape(ConcentricRectangle())
                    .padding(TripsMetrics.inset)
            }
            .frame(height: 252)
            .containerShape(shape)
            .background(ModuleFill(), in: shape)
            .contentShape(shape)
            .scaleEffect(isHovering ? 1.012 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.14 : 0.05), radius: isHovering ? 16 : 6, y: isHovering ? 8 : 2)
            .animation(.smooth(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
