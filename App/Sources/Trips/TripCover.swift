import SwiftUI
import IterCore
import IterDesign
import IterServices

/// A trip's picture: the first image of its first stop (Look Around, else satellite), the same request and cache as the
/// place card's strip, so a spot seen once shows at once here. Without an image (no stops, offline, still loading) a calm
/// sky gradient stands in. It fills whatever frame it is given; the caller clips it.
struct TripCover: View {
    let spot: Spot?

    @Environment(\.spotImagery) private var imagery
    @Environment(\.displayScale) private var displayScale
    @Environment(\.renderMode) private var renderMode
    @State private var loaded: [SpotImage]?

    private var request: SpotImageRequest? {
        spot.map {
            SpotImageRequest(spotID: $0.id, coordinate: $0.coordinate,
                             pointSize: CGSize(width: IterSize.imageRequestWidth, height: IterSize.imageStripHeight),
                             scale: displayScale)
        }
    }

    private var image: SpotImage? {
        guard let request else { return nil }
        return (loaded ?? imagery.cachedImages(for: request))?.first
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(decorative: image.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipped()
            .task(id: request) {
                guard let request else { return }
                if let cached = imagery.cachedImages(for: request) { loaded = cached; return }
                guard renderMode == .live else { return }
                loaded = await imagery.images(for: request)
            }
            .accessibilityHidden(true)
    }

    /// Night into the blue hour into gold: the light the app is about, at a whisper.
    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [IterColor.skyNight, IterColor.skyBlue, IterColor.skyGolden],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.55)
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}
