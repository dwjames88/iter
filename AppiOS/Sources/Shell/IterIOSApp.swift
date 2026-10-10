import SwiftUI
import SwiftData
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The iPhone and iPad app. Same store, schema, migration, services and view models as the Mac app (`IterApp`);
/// only the shell differs: a tab bar on iPhone (and in compact width on iPad), a split view with the sidebar on iPad.
@main
struct IterIOSApp: App {
    @State private var model: AppModel
    @AppStorage("IterShowLayoutGrid") private var showLayoutGrid = false

    init() {
        IterPerf.mark("app.init")
        // WeatherKit needs a paid team with the capability on the App ID, which this build does not have, so on iOS the
        // first-run forecast source is OpenWeather (a key from Settings, the Keychain or `-ITER_OPENWEATHER_KEY`). A source
        // chosen in Settings is stored in the app domain and always wins over this registered default.
        UserDefaults.standard.register(defaults: ["iter.weather.primary": "openWeather"])
        // A fresh iOS container has no Application Support folder; SwiftData's default store lives there and logs a
        // recovery error on first launch unless the folder exists.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        let container: ModelContainer
        do {
            container = try IterSchema.makeContainer(inMemory: AppLaunch.inMemoryStore)
        } catch {
            AppLaunch.log.error("Store failed to open, using memory: \(String(describing: error), privacy: .public)")
            container = try! IterSchema.makeContainer(inMemory: true)
        }
        let store = IterStore(container: container)
        store.actionName = StoreActionText.name
        let throwaway = AppLaunch.inMemoryStore || AppLaunch.isRunningTests
        let packs = throwaway ? FileManager.default.temporaryDirectory.appending(path: "IterOfflinePacks-\(UUID().uuidString)", directoryHint: .isDirectory)
                              : OfflinePackStore.defaultRoot()
        let model = AppModel.live(store: store, scout: AppLaunch.makeScout(), discovery: AppLaunch.makeDiscovery(), offlinePacks: packs)
        _model = State(initialValue: model)
        if AppLaunch.inMemoryStore, let seed = AppLaunch.seedTrip {
            let trip = store.seedSampleTrip(startDay: model.today(in: .current).adding(days: 1))
            if seed == .conflict {
                store.reorder(day: 1, in: trip, to: trip.orderedStops(onDay: 1).reversed().map(\.id))
            }
        }
        if AppLaunch.seedLibrary { LibrarySeed.run(model) }
        model.offline.attach(imagery: .shared, pointSize: CGSize(width: IterSize.imageRequestWidth, height: IterSize.imageStripHeight), scale: 3)
        if !AppLaunch.isRunningTests { model.offline.start() }
        if AppLaunch.smokeTest {
            Task { @MainActor in
                await model.loadAttribution()
                await SmokeHook.run(model)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(model)
                .environment(\.showsLayoutGrid, showLayoutGrid)
                .modelContainer(model.store.container)
                .preferredColorScheme(AppLaunch.forcedColorScheme)
                .task { await model.loadAttribution() }
        }
    }
}

extension AppLaunch {
    /// `-IterAppearance light|dark` forces the colour scheme (screenshots); absent, the system setting applies.
    static var forcedColorScheme: ColorScheme? {
        switch appearanceName {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
