import Foundation
import IterFeatures

extension LightText {
    static func name(_ sort: SavedSort) -> String {
        switch sort {
        case .name: String(localized: "Name", comment: "Saved sort order")
        case .lightToday: String(localized: "Light Today", comment: "Saved sort order: best light today first")
        case .kind: String(localized: "Kind", comment: "Saved sort order: by category")
        }
    }

    static func name(_ filter: SavedFilter) -> String {
        switch filter {
        case .all: String(localized: "All Spots", comment: "Saved filter")
        case .addedByYou: String(localized: "Added by You", comment: "Saved filter")
        case .curated: String(localized: "Curated", comment: "Saved filter")
        case .appleMaps: String(localized: "Apple Maps", comment: "Saved filter")
        }
    }
}
