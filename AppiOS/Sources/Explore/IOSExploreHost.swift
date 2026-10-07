import SwiftUI
import IterCore
import IterData
import IterFeatures

/// Owns the one ExploreModel for the scene (Explore tab, Search tab and the iPad Find screen share it), applies the Explore
/// launch switches once, and puts it in the environment. OWNER: Explore. Contract: `IOSExploreHost { content }`.
struct IOSExploreHost<Content: View>: View {
    @Environment(AppModel.self) private var model
    @State private var explore: ExploreModel?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let explore {
            content().environment(explore)
        } else {
            Color.clear.onAppear {
                let made = ExploreModel(app: model)
                if let add = AppLaunch.addSpot {
                    let draft = SpotDraft(coordinate: add.coordinate)
                    let record = model.store.createUserSpot(name: add.name, coordinate: draft.coordinate,
                                                            timeZoneIdentifier: draft.timeZoneIdentifier)
                    model.spotSaved(record.spot)
                    made.didCreate(record.spot)
                    made.requestScroll(to: record.spot.id)
                }
                if let text = AppLaunch.searchText {
                    made.query = text
                    made.searchAppleMaps()
                }
                if let text = AppLaunch.queryText { made.query = text }
                if let text = AppLaunch.askText {
                    made.query = text
                    made.ask()
                }
                if let id = AppLaunch.selectRowID, made.row(id: id) != nil {
                    made.select(id, from: .list)
                    made.openPanel()
                    made.requestScroll(to: id)
                }
                made.start()
                explore = made
            }
        }
    }
}
