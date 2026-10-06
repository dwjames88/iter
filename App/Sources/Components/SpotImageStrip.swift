import SwiftUI
import IterCore
import IterData
import IterDesign
import IterServices

extension EnvironmentValues {
    /// Where spot images come from. Tests inject a fake; the app uses MapKit (Look Around, then satellite).
    @Entry var spotImagery: any SpotImageryProviding = MapKitSpotImagery.shared
}

/// The images of a spot, shown at the top of the map's place card: the images page horizontally (Look Around, then
/// satellite), each with a quiet source label; a calm placeholder stands in while loading or when there are none.
///
/// This view only draws the list it is given, so a new source is one more `SpotImage` in the list. User photos will
/// slot in here: add `case userPhoto` to `SpotImageSource`, have the provider return the spot's own photos first,
/// and give `label(for:)` and `accessibilityLabel(for:)` their words. Nothing else in the strip changes.
struct SpotImageStrip: View {
    let images: [SpotImage]
    let isLoading: Bool
    let spotName: String
    let category: SpotCategory

    @State private var page: SpotImage.ID?
    @State private var isHovering = false

    private var currentIndex: Int {
        images.firstIndex { $0.id == page } ?? 0
    }

    var body: some View {
        Group {
            if images.isEmpty {
                placeholder
            } else {
                pager
            }
        }
        .frame(height: IterSize.placeCardImageHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Images

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(images) { item in
                    SpotImagePage(item: item, spotName: spotName)
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .overlay(alignment: .bottom) {
            if images.count > 1 { dots }
        }
        .overlay { if images.count > 1 { arrows } }
        .onHover { isHovering = $0 }
    }

    private var dots: some View {
        HStack(spacing: IterSpace.xs + IterSpace.xxs) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index == currentIndex ? IterColor.textPrimary : IterColor.textTertiary)
                    .frame(width: IterSpace.xs + IterSpace.xxs, height: IterSpace.xs + IterSpace.xxs)
            }
        }
        .padding(.horizontal, IterSpace.sm)
        .padding(.vertical, IterSpace.xs + IterSpace.xxs)
        .background(.regularMaterial, in: Capsule())
        .padding(IterSpace.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Image \(currentIndex + 1) of \(images.count)", comment: "VoiceOver: position in the place card's image strip"))
    }

    /// Previous and next, on hover: a mouse has no swipe.
    private var arrows: some View {
        HStack {
            if currentIndex > 0 { arrow("chevron.left", label: String(localized: "Previous image", comment: "VoiceOver and tooltip")) { move(to: currentIndex - 1) } }
            Spacer(minLength: 0)
            if currentIndex < images.count - 1 { arrow("chevron.right", label: String(localized: "Next image", comment: "VoiceOver and tooltip")) { move(to: currentIndex + 1) } }
        }
        .padding(.horizontal, IterSpace.sm)
        .opacity(isHovering ? 1 : 0)
        .animation(.smooth, value: isHovering)
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(IterFont.subheadline)
                .foregroundStyle(IterColor.textPrimary)
                .frame(width: IterSize.hitTarget, height: IterSize.hitTarget)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func move(to index: Int) {
        guard images.indices.contains(index) else { return }
        withAnimation(.smooth) { page = images[index].id }
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

/// One image of the strip with its source label.
private struct SpotImagePage: View {
    let item: SpotImage
    let spotName: String
    var body: some View {
        Image(decorative: item.image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                label
                    .font(IterFont.captionStrong)
                    .foregroundStyle(IterColor.textPrimary)
                    .padding(.horizontal, IterSpace.sm)
                    .padding(.vertical, IterSpace.xs)
                    .background(.regularMaterial, in: Capsule())
                    .padding(IterSpace.sm)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }

    private var label: Text {
        switch item.source {
        case .lookAround: Text("Look Around", comment: "Source label on a spot image")
        case .satellite: Text("Satellite", comment: "Source label on a spot image")
        }
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
                         pointSize: CGSize(width: IterSize.placeCardWidth, height: IterSize.placeCardImageHeight),
                         scale: displayScale)
    }

    var body: some View {
        SpotImageStrip(images: loaded ?? imagery.cachedImages(for: request) ?? [],
                       isLoading: loaded == nil && imagery.cachedImages(for: request) == nil && renderMode == .live,
                       spotName: spot.name, category: spot.category)
            .task(id: request) {
                if let cached = imagery.cachedImages(for: request) { loaded = cached; return }
                guard renderMode == .live else { return }
                loaded = nil
                loaded = await imagery.images(for: request)
            }
    }
}
