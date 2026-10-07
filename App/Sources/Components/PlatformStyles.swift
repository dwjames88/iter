import SwiftUI

// Styles that exist on macOS only, with the iOS equivalent, for views compiled into both apps.
extension View {
    /// A checkbox on the Mac; iOS has no checkbox style, so a toggle button there.
    @ViewBuilder func checkboxToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.button)
        #endif
    }

    /// A text-link button on the Mac; a borderless button on iOS (no `.link` style there).
    @ViewBuilder func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
