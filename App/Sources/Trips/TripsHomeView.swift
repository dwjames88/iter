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
        let overview = home.overview(today: today,
                                     pinnedTitle: String(localized: "Pinned", comment: "Trips section"),
                                     otherTitle: String(localized: "Other Trips", comment: "Trips section for trips in no folder"),
                                     subfolderTitle: { String(localized: "\($0) › \($1)", comment: "A subfolder's title under its folder") })
        Group {
            if overview.isEmpty {
                ScrollView { TripsEmptyState { presentNewTrip(template: $0) } }
            } else {
                ScrollView { TripsPageContent(overview: overview, today: today, prompt: $prompt) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IterColor.backgroundWindow, ignoresSafeAreaEdges: [])
        .unifiedToolbarBackground()
        .navigationTitle(Text("All Trips", comment: "Screen title"))
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
                        Button { prompt = .newFolder(parent: nil, trip: nil) } label: {
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
        .tripNamePrompt($prompt)
        .tripFlows()
        .onAppear {
            if AppLaunch.newFolderPrompt { prompt = .newFolder(parent: nil, trip: nil) }
        }
    }

    private var home: TripsHomeModel {
        TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
    }
}
