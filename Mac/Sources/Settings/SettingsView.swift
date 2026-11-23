import SwiftUI
import IterFeatures

/// The Settings scene: five panes, each a grouped form of system controls.
struct SettingsView: View {
    let shell: AppShell

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsPane(model: shell.settings) }
            Tab("Search", systemImage: "magnifyingglass") { SearchSettingsPane(model: shell.settings) }
            Tab("Sources & Credits", systemImage: "books.vertical") { SourcesSettingsPane(model: shell.settings) }
            Tab("Keys", systemImage: "key") { KeysSettingsPane(model: shell.settings) }
            Tab("Updates", systemImage: "arrow.down.circle") { UpdatesSettingsPane(controller: shell.updates) }
        }
        .frame(width: 600, height: 560)
        .scenePadding()
    }
}

/// Settings ▸ General.
struct GeneralSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Map Style", selection: $model.mapStyle) {
                    ForEach(SettingsModel.mapStyles, id: \.id) { Text($0.title).tag($0.id) }
                }
                Toggle("Show Daylight", isOn: $model.showDaylight)
            } header: {
                Text("Map")
            } footer: {
                Text("Daylight shades the night side of the globe when the map is zoomed out.")
            }
        }
        .formStyle(.grouped)
    }
}
