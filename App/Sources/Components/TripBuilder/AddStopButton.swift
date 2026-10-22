import SwiftUI
import IterDesign

/// "Add Stop" at the foot of a day: the system bordered capsule button, small, with a plus. The caller attaches the
/// popover that picks the stop.
struct AddStopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "Add Stop", comment: "Button at the end of a day"), systemImage: "plus")
                .font(BuilderType.control)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .help(Text("Add a stop to this day, nearest spots first", comment: "Tooltip"))
    }
}

#Preview("Add stop, light") { AddStopButton {}.padding(IterSpace.xl).background(IterColor.backgroundContent).preferredColorScheme(.light) }
#Preview("Add stop, dark") { AddStopButton {}.padding(IterSpace.xl).background(IterColor.backgroundContent).preferredColorScheme(.dark) }
