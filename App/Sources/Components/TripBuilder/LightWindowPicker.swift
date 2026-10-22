import SwiftUI
import IterCore
import IterDesign

/// A stop's light window as a system pop-up: the closed control names the window ("Sunset"); the open menu lists every
/// window the sun makes that day with its symbol, time and score, which is what you compare to choose.
struct LightWindowPicker: View {
    struct Option: Identifiable, Equatable {
        var kind: LightWindowKind
        /// The menu item, e.g. "Sunset · 6:12–6:48 PM · 64".
        var title: String
        var symbol: String
        var id: LightWindowKind { kind }
    }

    let options: [Option]
    let selection: LightWindowKind
    /// The closed control's text: the window's name.
    let closedLabel: String
    let onSelect: (LightWindowKind) -> Void

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { selection }, set: onSelect)) {
                ForEach(options) { option in
                    Label(option.title, systemImage: option.symbol).tag(option.kind)
                }
            } label: {
                Text("Session", comment: "Accessibility label of the session menu")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(closedLabel).font(BuilderType.body)
        }
        .menuStyle(.button)
        .fixedSize()
        .accessibilityLabel(Text("Session", comment: "Accessibility label of the session menu"))
        .accessibilityValue(Text(closedLabel))
        .help(Text("Which light to shoot here: each window with its time and score for this day", comment: "Tooltip"))
    }
}

#Preview("Window picker, light") { WindowPickerPreview().preferredColorScheme(.light) }
#Preview("Window picker, dark") { WindowPickerPreview().preferredColorScheme(.dark) }

private struct WindowPickerPreview: View {
    var body: some View {
        LightWindowPicker(options: [
            .init(kind: .goldenMorning, title: "Sunrise · 6:25–6:55 AM · 71", symbol: "sunrise.fill"),
            .init(kind: .goldenEvening, title: "Sunset · 6:01–6:31 PM · 100", symbol: "sunset.fill"),
        ], selection: .goldenEvening, closedLabel: "Sunset") { _ in }
            .padding(IterSpace.xl)
            .background(IterColor.backgroundModule)
    }
}
