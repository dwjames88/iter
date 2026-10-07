import Foundation

/// iOS-only Explore launch switches. `-IterSheet peek|half|full` sets the phone sheet's starting detent.
extension AppLaunch {
    static var sheetDetent: SheetDetent? {
        UserDefaults.standard.string(forKey: "IterSheet").flatMap(SheetDetent.init(rawValue:))
    }

    /// Debug aid: shows the search screen in the Explore tab (`-IterSearchPreview YES`).
    static var previewSearch: Bool { UserDefaults.standard.bool(forKey: "IterSearchPreview") }
    /// `-IterQuery <text>`: fills the search field without running a search, so the suggestions show.
    static var queryText: String? { UserDefaults.standard.string(forKey: "IterQuery") }
}
