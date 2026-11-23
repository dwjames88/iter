import SwiftUI
import MapKit
import IterModel
import IterGo
import IterGoActivity
import IterFeatures
import IterUI
#if os(iOS)
import UIKit
#endif

/// Standalone Go: the map full screen under one floating system sheet that carries `GoSheetContent`. The shell may mount
/// `GoMapLayer` and `GoSheetContent` itself (so its tab bar can sit at the sheet's foot); this view is the same thing
/// composed, bound to a live `GoModel`.
public struct GoRootView: View {
    let model: GoModel
    let trips: [GoTripChoice]
    let routePath: (() -> [Coordinate])?
    let startTrip: (UUID, UUID?, Bool) async -> Void

    @Environment(\.openURL) private var openURL
    @State private var detent: PresentationDetent = .medium
    @State private var sheetShown = true

    /// `startTrip` is the shell's: only it can build a `GoTripInput` for a trip id. `routePath` supplies the line on the map
    /// (default: the model's planned road still to drive).
    public init(model: GoModel, trips: [GoTripChoice], routePath: (() -> [Coordinate])? = nil,
                startTrip: @escaping (UUID, UUID?, Bool) async -> Void = { _, _, _ in }) {
        self.model = model
        self.trips = trips
        self.routePath = routePath
        self.startTrip = startTrip
    }

    public var body: some View {
        GoClock(perSecond: model.snapshot.undo != nil) { now in
            composed(now: now)
        }
        .onChange(of: model.pendingNavigation) { _, handoff in consume(handoff) }
        .onAppear { consume(model.pendingNavigation) }
    }

    @ViewBuilder private func composed(now: Date) -> some View {
        let map = GoMapLayer(snapshot: model.snapshot, routePath: routePath?() ?? model.routePath)
        let sheet = NavigationStack {
            GoSheetContent(snapshot: model.snapshot, permissions: model.permissions, now: now, trips: trips, actions: actions)
        }
        #if os(iOS)
        map
            .ignoresSafeArea()
            .sheet(isPresented: $sheetShown) {
                sheet
                    .presentationDetents([.height(Self.peekHeight), .medium, .large], selection: $detent)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        #else
        HStack(spacing: 0) {
            map
            sheet.frame(width: 380)
        }
        #endif
    }

    /// The smallest stop of the sheet: the title and the top of the hero card.
    static let peekHeight: CGFloat = 220

    private var actions: GoActions {
        GoActions(
            leaveNow: { await model.leaveNow() },
            arrived: { await model.arrived() },
            doneHere: { await model.doneHere() },
            skip: { await model.skip($0) },
            notYet: { await model.notYet() },
            pause: { await model.pause() },
            resume: { await model.resume() },
            end: { await model.end() },
            navigate: { open($0) },
            requestLocationWhenInUse: { model.requestLocationWhenInUse() },
            requestLocationAlways: { model.requestLocationAlways() },
            requestNotifications: { await model.requestNotifications() },
            openSettings: { openAppSettings() },
            start: { tripID, stopID, there in await startTrip(tripID, stopID, there) })
    }

    private func consume(_ handoff: NavigationHandoff?) {
        guard let handoff else { return }
        open(handoff)
        model.consumeNavigation()
    }

    private func open(_ handoff: NavigationHandoff) {
        #if os(iOS)
        handoff.mapItem().openInMaps(launchOptions: handoff.launchOptions)
        #else
        openURL(handoff.appleMapsURL)
        #endif
    }

    private func openAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }
}

/// Ticks `now`: every minute, or every second while an undo counts down.
struct GoClock<Content: View>: View {
    let perSecond: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if perSecond {
            TimelineView(.periodic(from: .now, by: 1)) { content($0.date) }
        } else {
            TimelineView(.everyMinute) { content($0.date) }
        }
    }
}
