import SwiftUI
import IterCore
import IterFeatures

/// The More menu of the Explore header: Near You radius, sort, filters and Clear Filters (what the Mac list header offers).
struct ExploreMoreMenu: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Picker(selection: radiusBinding) {
                ForEach(UserLocationModel.radiusChoices, id: \.self) { miles in
                    Text(LightText.radiusChoice(miles)).tag(miles)
                }
            } label: { Text(LightText.nearYouRadius) }
            .pickerStyle(.inline)
            Picker(selection: $explore.sort) {
                ForEach(ExploreSort.allCases) { sort in Text(LightText.name(sort)).tag(sort) }
            } label: { Text("Sort by", comment: "Menu section title") }
            .pickerStyle(.inline)
            Menu(String(localized: "Category", comment: "Filters submenu")) {
                ForEach(SpotCategory.allCases) { category in
                    Toggle(LightText.name(category), isOn: member(category, of: \.categories))
                }
            }
            Menu(String(localized: "Known for", comment: "Filters submenu: what the spot is best at")) {
                ForEach(BestLight.allCases) { best in
                    Toggle(LightText.name(best), isOn: member(best, of: \.bestLight))
                }
            }
            Menu(String(localized: "Source", comment: "Filters submenu")) {
                ForEach(ExploreSource.allCases) { source in
                    Toggle(LightText.name(source), isOn: member(source, of: \.sources))
                }
            }
            Divider()
            Button(String(localized: "Clear filters", comment: "Menu item")) { explore.filters = .none }
                .disabled(!explore.filters.isActive)
        } label: {
            Label(String(localized: "Sort and filters", comment: "Explore header menu"),
                  systemImage: explore.filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "ellipsis")
        }
        .accessibilityLabel(Text("Sort and filters", comment: "Explore header menu"))
        .accessibilityValue(explore.filters.activeCount > 0
                            ? Text("\(explore.filters.activeCount) filters active", comment: "VoiceOver: number of active filters")
                            : Text("No filters active", comment: "VoiceOver"))
    }

    private var radiusBinding: Binding<Int> {
        Binding(get: { model.location.radiusMiles }, set: { model.location.radiusMiles = $0 })
    }

    private func member<Element: Hashable>(_ element: Element, of keyPath: WritableKeyPath<ExploreFilters, Set<Element>>) -> Binding<Bool> {
        Binding(get: { explore.filters[keyPath: keyPath].contains(element) },
                set: { on in
                    if on { explore.filters[keyPath: keyPath].insert(element) } else { explore.filters[keyPath: keyPath].remove(element) }
                })
    }
}
