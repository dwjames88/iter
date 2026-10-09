import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// All Trips: the home of the app. A centred column on paper: the featured trip as a hero, then soft cards grouped as
/// Pinned, one section per folder and the rest. With no trips, a way to start one. Folders are made, renamed, deleted and
/// filled here (menu, context menu, or dragging a card onto a folder).
struct TripsHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.presentNewTrip) private var presentNewTrip
    @State private var prompt: TripNamePrompt?

    var body: some View {
        let today = model.today(in: .current)
        let overview = home.overview(today: today, featuring: openFolderID == nil)
        let openFolder = openFolderID.flatMap { model.store.folder(id: $0) }
        Group {
            if overview.isEmpty {
                ScrollView { TripsEmptyState { presentNewTrip(template: $0) } }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if let openFolder { folderHeader(openFolder) }
                        TripsPageContent(overview: overview, today: today, mode: openFolderID.map { .folder($0) } ?? .all, prompt: $prompt)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IterColor.backgroundWindow, ignoresSafeAreaEdges: [])
        .unifiedToolbarBackground()
        .navigationTitle(openFolder.map { Text($0.name) } ?? Text("All Trips", comment: "Screen title"))
        .toolbar {
            if !overview.isEmpty {
                ToolbarItem {
                    Button { presentNewTrip() } label: {
                        Label(String(localized: "New Trip", comment: "Toolbar button"), systemImage: "plus")
                    }
                    .help(Text("New Trip (⌘N)", comment: "Tooltip"))
                }
                ToolbarItem {
                    Menu {
                        Button { prompt = .newFolder(trip: nil) } label: {
                            Label(String(localized: "New Folder…", comment: "Toolbar menu"), systemImage: "folder.badge.plus")
                        }
                        Button { navigation.importRequest += 1 } label: {
                            Label(String(localized: "Import Trip…", comment: "Toolbar menu"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label(String(localized: "More", comment: "Toolbar menu"), systemImage: "ellipsis")
                    }
                    .help(Text("Folders and Import", comment: "Tooltip"))
                }
            }
        }
        .environment(\.openTripFolder) { navigation.selection = .tripFolder($0) }
        .tripNamePrompt($prompt)
        .tripFlows()
        .onAppear {
            if AppLaunch.newFolderPrompt { prompt = .newFolder(trip: nil) }
            consumeRequests()
        }
        .onChange(of: navigation.newFolderRequest) { consumeRequests() }
        .onChange(of: navigation.renamingID) { consumeRequests() }
    }

    /// The trip folder this page shows (chosen in the sidebar), nil = every trip.
    private var openFolderID: UUID? {
        if case .tripFolder(let id) = navigation.selection { id } else { nil }
    }

    /// File ▸ New Folder and the sidebar's Rename arrive through the navigation state; this page answers them.
    private func consumeRequests() {
        if navigation.newFolderRequest == .trips {
            navigation.newFolderRequest = nil
            prompt = .newFolder(trip: nil)
        }
        if let id = navigation.renamingID {
            if model.store.trip(id: id) != nil {
                navigation.renamingID = nil
                prompt = .renameTrip(id)
            } else if model.store.folder(id: id)?.kind == .trips {
                navigation.renamingID = nil
                prompt = .renameFolder(id)
            }
        }
    }

    /// Back to All Trips, the folder's name, and its menu.
    private func folderHeader(_ folder: FolderRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.md) {
            Button { navigation.selection = .trips } label: {
                Label(String(localized: "All Trips", comment: "Back button on a trip folder's page"), systemImage: "chevron.backward")
            }
            .buttonStyle(.borderless)
            Spacer(minLength: IterSpace.md)
        }
        .overlay {
            HStack(spacing: IterSpace.sm) {
                Image(systemName: "folder.fill").font(IterFont.headline)
                Text(folder.name).font(.system(.largeTitle, design: .serif, weight: .semibold))
                Menu {
                    TripFolderMenu(folderID: folder.id, prompt: $prompt)
                } label: {
                    Label(String(localized: "Folder Options", comment: "Folder header menu"), systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: TripsMetrics.columnMax)
        .padding(.horizontal, TripsMetrics.margin)
        .padding(.top, IterSpace.xl)
        .frame(maxWidth: .infinity)
    }

    private var home: TripsHomeModel {
        TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
    }
}
