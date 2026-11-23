import SwiftUI
import IterFeatures
import IterModel
import IterStore
import IterUI

/// All Trips (or one trip folder) for the iPhone sheet: a system `List` with the next trip as the hero row, Pinned, the folders as
/// rows that push, then the trips. Swipe right to pin, swipe left to delete (with an Undo toast), touch and hold for the menu.
///
/// `open` shows an app route (the app maps it onto the tab's navigation stack); `share` builds the Share item for a trip (the
/// app's own `ShareTripButton`). Reads `AppNavigator` from the environment for sheets.
public struct PhoneTripsList<Share: View>: View {
    let library: LibraryModel
    let folderID: UUID?
    let toast: PhoneUndoToast
    let open: (AppRoute) -> Void
    let share: (UUID) -> Share
    @Environment(AppNavigator.self) private var navigator
    @State private var renameTarget: RenameTarget?
    @State private var newName = ""

    public init(library: LibraryModel, folderID: UUID? = nil, toast: PhoneUndoToast, open: @escaping (AppRoute) -> Void,
                @ViewBuilder share: @escaping (UUID) -> Share) {
        self.library = library
        self.folderID = folderID
        self.toast = toast
        self.open = open
        self.share = share
    }

    private struct RenameTarget: Identifiable, Equatable {
        enum Kind { case trip, folder }
        let id: UUID
        let kind: Kind
        let current: String
    }

    public var body: some View {
        let sections = PhoneTripSections.make(trips: library.trips, next: library.nextTrip, folders: library.tripFolders, folderID: folderID)
        Group {
            if library.trips.isEmpty && folderID == nil {
                AllTripsEmptyState()
            } else if sections.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Trips in This Folder", comment: "Empty folder title"), systemImage: "folder")
                } description: {
                    Text("Touch and hold a trip, then choose Move to Folder.", comment: "Empty folder explanation on iPhone")
                }
            } else {
                list(sections)
            }
        }
        .alert(renameTarget?.kind == .folder ? "Rename Folder" : "Rename Trip", isPresented: renameBinding, presenting: renameTarget) { target in
            TextField(text: $newName) { Text("Name", comment: "Rename field label") }
            Button("Cancel", role: .cancel) {}
            Button("Rename") { commitRename(target) }
        }
    }

    private func list(_ s: PhoneTripSections) -> some View {
        List {
            if let hero = s.hero {
                Section {
                    PhoneTripHeroRow(row: hero, library: library) { open(.trip(hero.id)) }
                        .modifier(TripActions(row: hero, library: library, toast: toast, open: open, share: share, rename: startRename))
                }
            }
            if !s.pinned.isEmpty {
                Section { rows(s.pinned) } header: { Text("Pinned", comment: "Section title") }
            }
            if !s.folders.isEmpty {
                Section {
                    ForEach(s.folders) { folder in folderRow(folder) }
                } header: { Text("Folders", comment: "Section title") }
            }
            if !s.trips.isEmpty {
                Section {
                    rows(s.trips)
                } header: { Text(folderID == nil ? "Trips" : "In This Folder", comment: "Section title") }
            }
        }
        .phoneGroupedList()
    }

    private func rows(_ trips: [TripRow]) -> some View {
        ForEach(trips) { row in
            PhoneTripRow(row: row) { open(.trip(row.id)) }
                .modifier(TripActions(row: row, library: library, toast: toast, open: open, share: share, rename: startRename))
        }
    }

    private func folderRow(_ folder: FolderRow) -> some View {
        Button { open(.tripFolder(folder.id)) } label: {
            HStack(spacing: IterSpace.md) {
                Image(systemName: "folder").foregroundStyle(IterColor.accentText).frame(width: 24).accessibilityHidden(true)
                Text(folder.name).font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                Spacer(minLength: IterSpace.sm)
                Text(folder.count, format: .number).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).monospacedDigit()
                Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Rectangle().fill(ContentFill()))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                toast.perform(String(localized: "Folder Deleted", comment: "Undo toast")) { library.deleteFolder(folder.id) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { open(.tripFolder(folder.id)) } label: { Label("Open", systemImage: "folder") }
            Button { startRename(.init(id: folder.id, kind: .folder, current: folder.name)) } label: { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) {
                toast.perform(String(localized: "Folder Deleted", comment: "Undo toast")) { library.deleteFolder(folder.id) }
            } label: { Label("Delete Folder", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Rename

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func startRename(_ target: RenameTarget) {
        newName = target.current
        renameTarget = target
    }

    private func commitRename(_ target: RenameTarget) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != target.current else { return }
        switch target.kind {
        case .trip: library.renameTrip(target.id, to: trimmed)
        case .folder: library.renameFolder(target.id, to: trimmed)
        }
    }

    // MARK: Swipe actions and menu

    /// Leading swipe Pin or Unpin, trailing swipe Delete, and the touch-and-hold menu.
    private struct TripActions: ViewModifier {
        let row: TripRow
        let library: LibraryModel
        let toast: PhoneUndoToast
        let open: (AppRoute) -> Void
        let share: (UUID) -> Share
        let rename: (RenameTarget) -> Void

        func body(content: Content) -> some View {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { library.setTripPinned(row.id, !row.isPinned) } label: {
                        Label(row.isPinned ? "Unpin" : "Pin", systemImage: row.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(IterColor.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { delete() } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu { menu }
        }

        private func delete() {
            toast.perform(String(localized: "Trip Deleted", comment: "Undo toast")) { library.deleteTrip(row.id) }
        }

        @ViewBuilder private var menu: some View {
            Button { open(.trip(row.id)) } label: { Label("Open", systemImage: "arrow.up.right") }
            Button { rename(.init(id: row.id, kind: .trip, current: row.name)) } label: { Label("Rename", systemImage: "pencil") }
            Button { if let copy = library.duplicateTrip(row.id) { open(.trip(copy)) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { library.setTripPinned(row.id, !row.isPinned) } label: {
                Label(row.isPinned ? "Unpin" : "Pin", systemImage: row.isPinned ? "pin.slash" : "pin")
            }
            Menu {
                Button { library.moveTrips([row.id], to: nil) } label: {
                    Toggle(isOn: .constant(row.folderID == nil)) { Text("No Folder", comment: "Menu item") }
                }
                ForEach(library.tripFolders) { folder in
                    Button { library.moveTrips([row.id], to: folder.id) } label: {
                        Toggle(isOn: .constant(row.folderID == folder.id)) { Text(folder.name) }
                    }
                }
            } label: { Label("Move to Folder", systemImage: "folder") }
            share(row.id)
            Divider()
            Button(role: .destructive) { delete() } label: { Label("Delete Trip", systemImage: "trash") }
        }
    }
}

// MARK: - Rows

/// One trip: name, dates and size, the first places, a pin glyph when pinned, and the push chevron.
struct PhoneTripRow: View {
    let row: TripRow
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: IterSpace.sm) {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(row.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    Text(LibraryText.tripSubtitle(row)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                    if row.placeNames.isEmpty {
                        Text("No stops yet", comment: "Trip row with no stops").font(IterFont.secondary).foregroundStyle(IterColor.textTertiary)
                    } else {
                        Text(row.placeNames.joined(separator: ", ")).font(IterFont.secondary).foregroundStyle(IterColor.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: IterSpace.xs)
                if row.isPinned {
                    Image(systemName: "pin.fill").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                        .accessibilityLabel(Text("Pinned", comment: "Accessibility label"))
                }
                Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Rectangle().fill(ContentFill()))
        .accessibilityElement(children: .combine)
    }
}

/// The next trip, large: its name, dates and size, the next light with its one score chip.
struct PhoneTripHeroRow: View {
    let row: TripRow
    let library: LibraryModel
    let open: () -> Void
    @Environment(\.libraryClock) private var clock
    @Environment(\.libraryLightScore) private var scoreFor
    @State private var next: NextLight?
    @State private var searched = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                Text("Next Trip", comment: "Hero caption").font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(IterFont.titleSpot).foregroundStyle(IterColor.textPrimary).lineLimit(2)
                    Spacer(minLength: IterSpace.xs)
                    Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary).accessibilityHidden(true)
                }
                Text(LibraryText.tripSubtitle(row)).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
                nextLight
            }
            .padding(.vertical, IterSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Rectangle().fill(ContentFill()))
        .task(id: row) {
            next = library.trip(id: row.id).flatMap { NextLight.find(in: $0, now: clock()) }
            searched = true
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var nextLight: some View {
        if let next {
            HStack(spacing: IterSpace.sm) {
                Text("Next: \(next.stopName)", comment: "Hero: the next stop with light")
                    .font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                ScoreChip(kind: next.kind, start: next.start, end: next.end, score: scoreFor?(next.place, next.day, next.kind),
                          zone: next.zone, size: .small, timeStyle: .start)
                Text(TimeText.relativeDay(next.day, today: LocalDay(clock(), in: next.zone)))
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).lineLimit(1)
            }
        } else if searched {
            Text(row.stopCount == 0 ? "No stops yet. Open the trip to add the first." : "All sessions have passed",
                 comment: "Hero: nothing coming up").font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
        }
    }
}
