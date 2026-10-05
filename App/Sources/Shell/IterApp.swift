import SwiftUI
import SwiftData
import IterCore
import IterData
import IterFeatures

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
        let model = AppModel.live(store: store, scout: AppLaunch.makeScout())
        _model = State(initialValue: model)
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
                .modelContainer(model.store.container)
                .task { await model.loadAttribution() }
        }
        .defaultSize(width: 1280, height: 820)
        // Under the test runner the host app opens no window, so tests never take over the screen.
        .defaultLaunchBehavior(AppLaunch.isRunningTests ? .suppressed : .automatic)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppLaunch.isRunningTests { NSApp.setActivationPolicy(.prohibited) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
