import SwiftUI

/// "Add Stop" at the foot of a day: the system bordered capsule button, small, with a plus. The caller attaches the
/// popover that picks the stop. Figma part: add stop button.
public struct AddStopButton: View {
    public let action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Label(String(localized: "Add Stop", bundle: .module, comment: "Button at the end of a day"), systemImage: "plus")
                .font(BuilderType.control)
                #if os(iOS)
                // iOS: the capsule grows toward the 44 pt touch target (GLASS-RULES).
                .frame(minHeight: 32)
                #endif
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        #if os(macOS)
        .controlSize(.small)
        #else
        .controlSize(.regular)
        #endif
        .help(Text("Add a stop to this day, nearest spots first", bundle: .module, comment: "Tooltip"))
    }
}
