import SwiftUI
import IterFeatures
import IterModel
import IterStore
import IterUI

/// All Trips (or one trip folder): the hero for the next trip, Pinned, each folder, then the rest as cards; an empty state with
/// templates. The shell owns the toolbar; the actions (New Trip, New Folder) are also here as buttons.
struct AllTripsContent: View {
    let library: LibraryModel
    let folderID: UUID?
    @Environment(AppNavigator.self) private var navigator
    @State private var renaming: UUID?
    @State private var folderName = ""
    @FocusState private var nameFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: IterSize.listMin, maximum: IterSize.listIdeal), spacing: IterSpace.lg, alignment: .top)]

    var body: some View {
        let shown = library.trips.filter { folderID == nil || $0.folderID == folderID }
        Group {
            if library.trips.isEmpty && folderID == nil {
                AllTripsEmptyState()
            } else if shown.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Trips in This Folder", comment: "Empty folder title"), systemImage: "folder")
                } description: {
                    Text("Drag trips here to file them.", comment: "Empty folder explanation")
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IterColor.backgroundWindow)
    }

    private var list: some View {
        let hero = folderID == nil ? library.nextTrip : nil
        let rest = library.trips.filter { $0.id != hero?.id && (folderID == nil || $0.folderID == folderID) }
        let pinned = folderID == nil ? rest.filter(\.isPinned) : []
        let unpinned = rest.filter { !$0.isPinned }
        let loose = unpinned.filter { folderID != nil || $0.folderID == nil }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: IterSpace.xl) {
                if let hero { TripHero(row: hero, library: library) }
                if !pinned.isEmpty {
                    section(title: String(localized: "Pinned", comment: "Section title"), symbol: "pin", trips: pinned, folder: nil)
                }
                if folderID == nil {
                    ForEach(library.tripFolders) { folder in
                        folderSection(folder, trips: unpinned.filter { $0.folderID == folder.id })
                    }
                }
                if !loose.isEmpty || folderID == nil {
                    section(title: folderID == nil ? String(localized: "Trips", comment: "Section title") : nil, symbol: nil, trips: loose,
                            folder: nil, showsNewFolder: folderID == nil)
                }
            }
            .padding(IterSpace.xl)
        }
    }

    // MARK: Sections

    @ViewBuilder private func section(title: String?, symbol: String?, trips: [TripRow], folder: FolderRow?,
                                      showsNewFolder: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            if title != nil || showsNewFolder {
                HStack {
                    if let title {
                        Label { Text(title).font(IterFont.headline) } icon: { if let symbol { Image(systemName: symbol) } }
                            .foregroundStyle(IterColor.textPrimary)
                    }
                    Spacer()
                    if showsNewFolder {
                        Button { newFolder() } label: { Label(String(localized: "New Folder", comment: "Button"), systemImage: "folder.badge.plus") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(IterColor.accentText)
                    }
                }
                // Dropping a card on "Trips" takes it out of its folder.
                .dropDestination(for: TripDragItem.self) { items, _ in
                    library.moveTrips(items.map(\.tripID), to: nil)
                    return !items.isEmpty
                }
            }
            if !trips.isEmpty { grid(trips) }
        }
    }

    private func folderSection(_ folder: FolderRow, trips: [TripRow]) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            HStack(spacing: IterSpace.sm) {
                Image(systemName: "folder").foregroundStyle(IterColor.accentText)
                if renaming == folder.id {
                    TextField(text: $folderName, prompt: Text("Folder name", comment: "Placeholder")) { Text("Folder name", comment: "Label") }
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .focused($nameFocused)
                        .onSubmit { commitRename(folder) }
                        .onChange(of: nameFocused) { if !nameFocused { commitRename(folder) } }
                } else {
                    Button { navigator.open(.tripFolder(folder.id)) } label: {
                        Text(folder.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                Text("^[\(folder.count) trip](inflect: true)", comment: "Folder row: how many trips").font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                Spacer()
                folderMenu(folder)
            }
            .contentShape(Rectangle())
            .contextMenu { folderMenuItems(folder) }
            .dropDestination(for: TripDragItem.self) { items, _ in
                library.moveTrips(items.map(\.tripID), to: folder.id)
                return !items.isEmpty
            }
            if trips.isEmpty {
                Text("Drag trips here to file them.", comment: "Empty folder hint").font(IterFont.secondary).foregroundStyle(IterColor.textTertiary)
            } else {
                grid(trips)
            }
        }
    }

    private func grid(_ trips: [TripRow]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: IterSpace.lg) {
            ForEach(trips) { row in TripCard(row: row, library: library) }
        }
    }

    // MARK: Folder actions

    private func folderMenu(_ folder: FolderRow) -> some View {
        Menu { folderMenuItems(folder) } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Folder Actions", comment: "Accessibility label"))
    }

    @ViewBuilder private func folderMenuItems(_ folder: FolderRow) -> some View {
        Button { navigator.open(.tripFolder(folder.id)) } label: { Text("Open", comment: "Menu item") }
        Button { startRename(folder) } label: { Text("Rename", comment: "Menu item") }
        Button { library.setFolderPinned(folder.id, !folder.isPinned) } label: {
            Text(folder.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar", comment: "Menu item")
        }
        Divider()
        Button(role: .destructive) { library.deleteFolder(folder.id) } label: { Text("Delete Folder", comment: "Menu item") }
    }

    private func newFolder() {
        let id = library.createFolder(name: String(localized: "New Folder", comment: "Default folder name"), kind: .trips)
        if let folder = library.tripFolders.first(where: { $0.id == id }) { startRename(folder) }
    }

    private func startRename(_ folder: FolderRow) {
        folderName = folder.name
        renaming = folder.id
        nameFocused = true
    }

    private func commitRename(_ folder: FolderRow) {
        guard renaming == folder.id else { return }
        renaming = nil
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != folder.name { library.renameFolder(folder.id, to: trimmed) }
    }
}

// MARK: - Hero

/// The next trip, large: its name in the serif, dates and size, the next light with its one score chip, Open as the accent action.
struct TripHero: View {
    let row: TripRow
    let library: LibraryModel
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.libraryClock) private var clock
    @Environment(\.libraryLightScore) private var scoreFor
    @State private var next: NextLight?
    @State private var searched = false

    var body: some View {
        HStack(alignment: .bottom, spacing: IterSpace.xl) {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                Text("Next Trip", comment: "Hero caption").font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                Text(row.name).font(IterFont.titleSpot).foregroundStyle(IterColor.textPrimary).lineLimit(2)
                Text(LibraryText.tripSubtitle(row)).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
                nextLight
            }
            Spacer(minLength: IterSpace.lg)
            Button { navigator.open(.trip(row.id)) } label: { Text("Open", comment: "Button: open the trip").frame(minWidth: 72) }
                .buttonStyle(.borderedProminent)
                .tint(IterColor.accent)
                .controlSize(.large)
        }
        .padding(IterSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { navigator.open(.trip(row.id)) }
        .task(id: row) {
            next = library.trip(id: row.id).flatMap { NextLight.find(in: $0, now: clock()) }
            searched = true
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var nextLight: some View {
        if let next {
            HStack(spacing: IterSpace.sm) {
                Text("Next: \(next.stopName)", comment: "Hero: the next stop with light")
                    .font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                ScoreChip(kind: next.kind, start: next.start, end: next.end, score: scoreFor?(next.place, next.day, next.kind),
                          zone: next.zone, size: .small, timeStyle: .start)
                Text(TimeText.relativeDay(next.day, today: LocalDay(clock(), in: next.zone)))
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
        } else if searched {
            Text(row.stopCount == 0 ? "No stops yet. Open the trip to add the first." : "All sessions have passed",
                 comment: "Hero: nothing coming up").font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
        }
    }
}

// MARK: - Card

/// One trip as a card: name, dates, size and the first places. Double-click or the Open item opens it.
struct TripCard: View, Equatable {
    let row: TripRow
    let library: LibraryModel
    @Environment(AppNavigator.self) private var navigator

    nonisolated static func == (lhs: TripCard, rhs: TripCard) -> Bool { lhs.row == rhs.row }

    var body: some View {
        Button { navigator.open(.trip(row.id)) } label: {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    Spacer(minLength: IterSpace.xs)
                    if row.isPinned { Image(systemName: "pin.fill").font(IterFont.caption).foregroundStyle(IterColor.textSecondary).accessibilityLabel(Text("Pinned", comment: "Accessibility label")) }
                }
                Text(LibraryText.tripSubtitle(row)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                if row.placeNames.isEmpty {
                    Label {
                        Text("No stops yet. Open the trip to add the first.", comment: "Trip card with no stops")
                    } icon: { Image(systemName: "plus.circle").foregroundStyle(IterColor.accent) }
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                } else {
                    Text(row.placeNames.joined(separator: ", ")).font(IterFont.secondary).foregroundStyle(IterColor.textTertiary).lineLimit(2)
                }
            }
            .padding(IterSpace.lg)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .draggable(TripDragItem(tripID: row.id))
        .contextMenu { TripMenuItems(row: row, library: library) }
        .accessibilityElement(children: .combine)
    }
}

/// The trip context menu: Open, Duplicate, Share…, Pin/Unpin, Move to Folder ▸, Delete Trip.
struct TripMenuItems: View {
    let row: TripRow
    let library: LibraryModel
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        Button { navigator.open(.trip(row.id)) } label: { Text("Open", comment: "Menu item") }
        Button { if let copy = library.duplicateTrip(row.id) { navigator.open(.trip(copy)) } } label: { Text("Duplicate", comment: "Menu item") }
        ShareLink(item: LibraryTripExport(fileName: ITERFileNaming.name(row.name)) { [library, id = row.id] in
            (try? library.exportTrip(id))??.data
        }, preview: SharePreview(row.name)) { Text("Share…", comment: "Menu item") }
        Button { library.setTripPinned(row.id, !row.isPinned) } label: { Text(row.isPinned ? "Unpin" : "Pin", comment: "Menu item") }
        Menu {
            Button { library.moveTrips([row.id], to: nil) } label: {
                Toggle(isOn: .constant(row.folderID == nil)) { Text("No Folder", comment: "Menu item") }
            }
            ForEach(library.tripFolders) { folder in
                Button { library.moveTrips([row.id], to: folder.id) } label: {
                    Toggle(isOn: .constant(row.folderID == folder.id)) { Text(folder.name) }
                }
            }
        } label: { Text("Move to Folder", comment: "Menu item") }
        Divider()
        Button(role: .destructive) { library.deleteTrip(row.id) } label: { Text("Delete Trip", comment: "Menu item") }
    }
}

enum ITERFileNaming {
    static func name(_ tripName: String) -> String { ITERFileInfo.suggestedFileName(forTripNamed: tripName) }
}

// MARK: - Empty state

/// "Plan trips around the light": New Trip and three templates.
struct AllTripsEmptyState: View {
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(spacing: IterSpace.xl) {
                Text("Plan trips around the light", comment: "Empty All Trips headline")
                    .font(IterFont.titleSpot).foregroundStyle(IterColor.textPrimary).multilineTextAlignment(.center)
                Text("Pick your spots and days. Iter works out when to leave so you are set up before the light arrives.",
                     comment: "Empty All Trips explanation")
                    .font(IterFont.callout).foregroundStyle(IterColor.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Button { navigator.present(.newTrip(templateID: nil, firstPlace: nil)) } label: {
                    Text("New Trip", comment: "Button").frame(minWidth: 128)
                }
                .buttonStyle(.borderedProminent)
                .tint(IterColor.accent)
                .controlSize(.large)
                Text("Or start from a template", comment: "Caption above the template rows")
                    .font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                VStack(spacing: IterSpace.sm) {
                    ForEach(TripTemplates.all) { template in TemplateRow(template: template) }
                }
                .frame(maxWidth: 520)
            }
            .padding(IterSpace.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct TemplateRow: View {
    let template: TripTemplate
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        Button { navigator.present(.newTrip(templateID: template.id, firstPlace: nil)) } label: {
            HStack(spacing: IterSpace.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.defaultName).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    Text("\(InflectedCount.days(template.dayCount)), \(InflectedCount.stops(template.stops.count))", comment: "Template size")
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                    Text(spotNames).font(IterFont.secondary).foregroundStyle(IterColor.textTertiary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
            }
            .padding(IterSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var spotNames: String {
        var seen = Set<String>()
        let names = template.stops.compactMap { stop -> String? in
            guard seen.insert(stop.spotID).inserted else { return nil }
            return CuratedSpots.spot(id: stop.spotID)?.name
        }
        return names.prefix(3).joined(separator: ", ")
    }
}
