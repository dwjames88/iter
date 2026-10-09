import SwiftUI
import MapKit
import IterCore
import IterData
import IterDesign
import IterServices

extension EnvironmentValues {
    /// Where spot images come from. Tests inject a fake; the app uses MapKit (Look Around, then satellite).
    @Entry var spotImagery: any SpotImageryProviding = MapKitSpotImagery.shared
}

/// The images of a spot, shown at the top of the map's place card: one image at a time, Look Around and satellite, with a
/// system segmented control over the image to switch between them (a mouse has no swipe). With one image the control is a
/// quiet source label. Look Around is live: once MapKit has the scene, the snapshot is replaced by an interactive
/// `LookAroundPreview` that you can look around in; when there is no scene the image is not offered at all. A calm
/// placeholder stands in while loading or when there are none.
///
/// This view only draws the list it is given, so a new source is one more `SpotImage` in the list. User photos will
/// slot in here: add `case userPhoto` to `SpotImageSource`, have the provider return the spot's own photos first,
/// and give `label(for:)` and `accessibilityLabel(for:)` their words. Nothing else in the strip changes.
struct SpotImageStrip: View {
    let images: [SpotImage]
    let isLoading: Bool
    let spotName: String
    let category: SpotCategory
    /// Where Look Around looks, for the live preview. Nil draws the snapshots only (tests, snapshots).
    var coordinate: Coordinate?

    @State private var selected: SpotImage.ID?

    private var current: SpotImage? {
        images.first { $0.id == selected } ?? images.first
    }

    var body: some View {
        Group {
            if let current {
                ZStack {
                    SpotImagePage(item: current, spotName: spotName, coordinate: coordinate)
                        .id(current.id)
                        .transition(.opacity)
                }
                .overlay(alignment: .topLeading) { sourceControl(current) }
            } else {
                placeholder
            }
        }
        .animation(.smooth(duration: 0.25), value: current?.id)
        .frame(height: IterSize.imageStripHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Source

    /// The system segmented control with more than one source; the plain label with one.
    @ViewBuilder private func sourceControl(_ current: SpotImage) -> some View {
        if images.count > 1 {
            Picker(selection: Binding(get: { current.id }, set: { selected = $0 })) {
                ForEach(images) { item in
                    Text(SpotImageStrip.title(for: item.source)).tag(item.id)
                }
            } label: {
                Text("Image", comment: "VoiceOver: the place card's image source control")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            // Over a photo: clear glass with the HIG's 35 % dimming layer, and light labels.
            .environment(\.colorScheme, .dark)
            .padding(IterSpace.xxs)
            .background(.black.opacity(0.35), in: .capsule)
            .glassEffect(.clear, in: .capsule)
            .padding(IterGrid.inset)
        } else {
            Text(SpotImageStrip.title(for: current.source))
                .font(IterFont.captionStrong)
                .foregroundStyle(.white)
                .padding(.horizontal, IterSpace.sm)
                .padding(.vertical, IterSpace.xs)
                .background(.black.opacity(0.35), in: .capsule)
                .glassEffect(.clear, in: .capsule)
                .padding(IterGrid.inset)
                .accessibilityHidden(true)
        }
    }

    static func title(for source: SpotImageSource) -> LocalizedStringKey {
        switch source {
        case .lookAround: "Look Around"
        case .satellite: "Satellite"
        }
    }

// MARK: Placeholder

    private var placeholder: some View {
        ZStack {
            IterColor.backgroundControl
            VStack(spacing: IterSpace.sm) {
                Image(systemName: LightText.symbol(category))
                    .font(IterFont.titleSection)
                    .foregroundStyle(IterColor.textTertiary)
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading
            ? Text("Loading images of \(spotName)", comment: "VoiceOver: the place card's image placeholder while loading")
            : Text("No images of \(spotName)", comment: "VoiceOver: the place card's image placeholder when there are none"))
    }
}

/// One image of the strip. Look Around becomes live when its scene is available.
private struct SpotImagePage: View {
    let item: SpotImage
    let spotName: String
    let coordinate: Coordinate?
    @State private var scene: MKLookAroundScene?

    var body: some View {
        // Sized by its container, not by the image, so a narrow column does not make the page wider than the strip.
        Color.clear
            .overlay {
                Image(decorative: item.image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                if let scene {
                    LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true, pointsOfInterest: .all)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .task(id: item.id) {
                guard item.source == .lookAround, let coordinate else { return }
                let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
                scene = try? await request.scene
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }

    private var accessibilityLabel: Text {
        switch item.source {
        case .lookAround: Text("Look Around view of \(spotName)", comment: "VoiceOver: image of a spot")
        case .satellite: Text("Satellite view of \(spotName)", comment: "VoiceOver: image of a spot")
        }
    }
}

/// Loads the images of a spot and shows them in a `SpotImageStrip`. The cache is read synchronously on the first
/// render (a warmed cache shows immediately, also in offscreen snapshots); the network is only used when live.
struct SpotImages: View {
    let spot: Spot

    @Environment(\.spotImagery) private var imagery
    @Environment(\.displayScale) private var displayScale
    @Environment(\.renderMode) private var renderMode
    @State private var loaded: [SpotImage]?

    private var request: SpotImageRequest {
        SpotImageRequest(spotID: spot.id, coordinate: spot.coordinate,
                         pointSize: CGSize(width: IterSize.imageRequestWidth, height: IterSize.imageStripHeight),
                         scale: displayScale)
    }

    var body: some View {
        SpotImageStrip(images: loaded ?? imagery.cachedImages(for: request) ?? [],
                       isLoading: loaded == nil && imagery.cachedImages(for: request) == nil && renderMode == .live,
                       spotName: spot.name, category: spot.category,
                       coordinate: renderMode == .live ? spot.coordinate : nil)
            .task(id: request) {
                if let cached = imagery.cachedImages(for: request) { loaded = cached; return }
                guard renderMode == .live else { return }
                loaded = nil
                loaded = await imagery.images(for: request)
            }
    }
}
