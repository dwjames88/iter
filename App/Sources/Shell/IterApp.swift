import SwiftUI
import SwiftData
import IterCore
import IterData
import IterFeatures
import IterDesign

@main
struct IterApp: App {
    @State private var model: AppModel
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    /// Debug ▸ Show Layout Grid. A launch argument `-IterShowLayoutGrid YES` sets it too (the argument domain wins).
    @AppStorage("IterShowLayoutGrid") private var showLayoutGrid = false

    init() {
        IterPerf.mark("app.init")
        TripPerfProbe.start()
        let container: ModelContainer
        do {
            container = try StoreBootstrap.makeContainer(inMemory: AppLaunch.inMemoryStore)
        } catch {
            // A store that cannot open must not take the app down; run in memory and say so in the log.
            AppLaunch.log.error("Store failed to open, using memory: \(String(describing: error), privacy: .public)")
            container = try! IterSchema.makeContainer(inMemory: true)
        }
        let store = IterStore(container: container)
        store.actionName = StoreActionText.name
        // An in-memory or test run keeps its offline packs in a throwaway folder so it never cleans up the real ones.
        let throwaway = AppLaunch.inMemoryStore || AppLaunch.isRunningTests
        let packs = throwaway ? RenderCopy.scratchDirectory("OfflinePacks-\(UUID().uuidString)")
                              : OfflinePackStore.defaultRoot()
        let model = AppModel.live(store: store, scout: AppLaunch.makeScout(), discovery: AppLaunch.makeDiscovery(), offlinePacks: packs,
                                  isolated: AppLaunch.isRenderCopy)
        _model = State(initialValue: model)
        // `-IterSeedTrip YES` (with `-IterInMemoryStore YES` only): the Canyon Country sample trip, starting tomorrow,
        // so `-IterSection trip` opens a 4-day trip for screenshots and measurements without touching real data.
        // `-IterSeedTrip conflict` also reverses day 2, so a sunrise stop follows a sunset stop (a conflict and a suggestion).
        if AppLaunch.inMemoryStore, let seed = AppLaunch.seedTrip {
            let trip = store.seedSampleTrip(startDay: model.today(in: .current).adding(days: 1))
            if seed == .conflict {
                store.reorder(day: 1, in: trip, to: trip.orderedStops(onDay: 1).reversed().map(\.id))
            }
        }
        if AppLaunch.seedLibrary { LibrarySeed.run(model) }
        model.offline.attach(imagery: .shared, pointSize: CGSize(width: IterSize.imageRequestWidth, height: IterSize.imageStripHeight), scale: 2)
        if !AppLaunch.isRunningTests { model.offline.start() }
        // The smoke hook starts here, not in a view task, so it also runs when the app is launched hidden.
        if AppLaunch.smokeTest {
            Task { @MainActor in
                await model.loadAttribution()
                await SmokeHook.run(model)
            }
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .environment(\.showsLayoutGrid, showLayoutGrid)
                .modelContainer(model.store.container)
                .task { await model.loadAttribution() }
        }
        .defaultSize(width: 1280, height: 820)
        // Under the test runner the host app opens no window, so tests never take over the screen.
        .defaultLaunchBehavior(AppLaunch.isRunningTests ? .suppressed : .automatic)
        .commands {
            AppCommands(model: model)
            UpdateCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppLaunch.isRunningTests { NSApp.setActivationPolicy(.prohibited) }
        switch AppLaunch.appearanceName {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The daily update check and the clean-up of old downloads; does nothing under tests, in-memory or smoke runs.
        UpdateController.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
