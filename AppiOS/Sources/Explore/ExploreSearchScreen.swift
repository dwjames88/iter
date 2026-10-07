import SwiftUI

/// The search tab (iOS 26 `Tab(role: .search)`): Apple Maps and Ask suggestions and results.
struct ExploreSearchScreen: View {
    var onShowPlace: () -> Void = {}
    var body: some View { Text(verbatim: "Search") }
}
