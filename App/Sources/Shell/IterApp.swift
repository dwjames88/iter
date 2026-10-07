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

    init() {
        let container: ModelContainer
        do {
            container = try IterSchema.makeContainer(inMemory: AppLaunch.inMemoryStore)
        } catch {
            // A store that cannot open must not take the app down; run in memory and say so in the log.
            AppLaunch.log.error("Store failed to open, using memory: \(String(describing: error), privacy: .public)")
            container = try! IterSchema.makeContainer(inMemory: true)
        }
        let store = IterStore(container: container)
        store.actionName = StoreActionText.name
        // An in-memory or test run keeps its offline packs in a throwaway folder so it never cleans up the real ones.
        let throwaway = AppLaunch.inMemoryStore || AppLaunch.isRunningTests
        let packs = throwaway ? FileManager.default.temporaryDirectory.appending(path: "IterOfflinePacks-\(UUID().uuidString)", directoryHint: .isDirectory)
                              : OfflinePackStore.defaultRoot()
        let model = AppModel.live(store: store, scout: AppLaunch.makeScout(), offlinePacks: packs)
        _model = State(initialValue: model)
        if AppLaunch.seedLibrary { LibrarySeed.run(model) }
        model.offline.attach(imagery: .shared, pointSize: CGSize(width: IterSize.placeCardWidth, height: IterSize.placeCardImageHeight), scale: 2)
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
                .tint(IterColor.accent)
                .environment(model)
                .modelContainer(model.store.container)
                .task { await model.loadAttribution() }
        }
        .defaultSize(width: 1280, height: 820)
        // Under the test runner the host app opens no window, so tests never take over the screen.
        .defaultLaunchBehavior(AppLaunch.isRunningTests ? .suppressed : .automatic)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .tint(IterColor.accent)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
