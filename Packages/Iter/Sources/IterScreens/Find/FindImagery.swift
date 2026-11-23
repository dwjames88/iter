import SwiftUI
import MapKit
import IterFeatures
import IterModel
import IterSources
import IterUI

/// The card's picture of the place: Look Around when Apple has street-level imagery there, else a satellite view.
/// Inset and rounded like the card's other content; fixed at the image-strip height.
struct FindImagery: View {
    let coordinate: Coordinate
    let availability: LookAroundAvailability
    @State private var scene: MKLookAroundScene?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous) }

    var body: some View {
        ZStack {
            if availability == .available, let scene {
                LookAroundPreview(initialScene: scene)
            } else {
                FindSatelliteView(coordinate: coordinate)
            }
        }
        .frame(height: IterSize.imageStripHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        .task(id: LookKey(coordinate: coordinate, availability: availability)) {
            scene = nil
            guard availability == .available else { return }
            let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            scene = try? await request.scene
        }
        .accessibilityLabel(Text(availability == .available ? "Look Around preview" : "Satellite view of the place"))
    }

    private struct LookKey: Hashable { var coordinate: Coordinate; var availability: LookAroundAvailability }
}

/// A satellite-style map at street scale with the place marked; not interactive (it is a picture).
struct FindSatelliteView: View {
    let coordinate: Coordinate

    var body: some View {
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 1200, longitudinalMeters: 1200)),
            interactionModes: []) {
            Marker("", coordinate: center).tint(IterColor.mapPin)
        }
        .mapStyle(.imagery)
        .allowsHitTesting(false)
    }
}

/// A licensed photo with its credit, licence and a link to the page it came from.
struct FindPhotoView: View {
    let photo: LicensedPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            AsyncImage(url: photo.imageURL ?? photo.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(ControlFill())
                    Image(systemName: "photo").font(.title2).foregroundStyle(IterColor.textTertiary)
                }
            }
            .frame(height: IterSize.imageStripHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            .accessibilityLabel(Text(verbatim: photo.title))
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(verbatim: photo.credit)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: IterSpace.xs) {
                    Text(verbatim: "Licence: " + photo.licenceName)
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textTertiary)
                    if let page = photo.pageURL {
                        Text(verbatim: "·").font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
                        Link("View Photo", destination: page).font(IterFont.caption)
                    }
                }
            }
        }
    }
}
