import SwiftUI
import MapKit
import CoreLocation
import IterCore
import IterDesign
import IterFeatures

/// "Good to know": the best window over the forecast's days first (the answer to "when should I be here?", or the sun
/// times when nothing is scored), then a fixed row of facts (walk-in, elevation, facing, best at, time zone), the
/// blurb and the notes. `page` is nil until the spot's model is built; the facts show meanwhile.
struct SpotFactsSection: View {
    @Environment(AppModel.self) private var model
    let spot: Spot
    var page: SpotModel?

    var body: some View {
        ModuleCard(title: LightText.factsTitle, symbol: "info.circle") {
            VStack(alignment: .leading, spacing: IterGrid.inset) {
                    if let page { BestWindowLead(page: page) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: IterSize.listMin / 2), alignment: .leading)], alignment: .leading, spacing: IterSpace.sm) {
                        fact("figure.walk", LightText.walkIn(spot.walkInMinutes), known: spot.walkInMinutes != nil)
                        if let elevation = spot.elevationMeters {
                            fact("mountain.2", LightText.elevation(elevation))
                        }
                        fact("safari", LightText.facing(spot.facing), known: spot.facing != nil)
                        if let best = LightText.bestAt(spot.bestLight) {
                            fact("sun.horizon", best)
                        }
                        if let zone = TimeText.zoneNote(for: spot.timeZone, now: model.now()) {
                            fact("clock", zone)
                        }
                    }
                    if !spot.blurb.isEmpty {
                        Text(spot.blurb).font(IterFont.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if !spot.notes.isEmpty {
                        VStack(alignment: .leading, spacing: IterSpace.xs) {
                            Text(LightText.notesTitle).font(IterFont.moduleTitle).foregroundStyle(IterColor.textSecondary)
                            Text(spot.notes).font(IterFont.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
            }
        }
    }

    private func fact(_ symbol: String, _ text: String, known: Bool = true) -> some View {
        Label {
            Text(text).foregroundStyle(known ? IterColor.textPrimary : IterColor.textSecondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(IterColor.textSecondary)
        }
        .font(IterFont.body)
    }
}

/// Look Around, when Apple has imagery here. Absent otherwise, and in snapshot renders.
struct LookAroundSection: View {
    @Environment(\.renderMode) private var renderMode
    let coordinate: Coordinate
    @State private var scene: MKLookAroundScene?

    var body: some View {
        Group {
            if renderMode == .live, let scene {
                ModuleCard(title: LightText.lookAroundTitle, symbol: "binoculars") {
                    LookAroundPreview(initialScene: scene)
                        .frame(height: IterSize.arcHeight + IterSize.timelineHeight)
                        .clipShape(RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
                }
            }
        }
        .task(id: coordinate) {
            guard renderMode == .live else { return }
            let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            scene = try? await request.scene
        }
    }
}
