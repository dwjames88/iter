import SwiftUI
import IterCore
import IterDesign

/// The Mac place card's header, as Maps lays it out: Back at the leading corner (to the list, as Escape does), Share and
/// Close in the trailing corner, all 32 pt glass circles concentric with the card's corner. The card has no step buttons
/// or position counter: Up and Down in the list move through the places.
struct PlaceCardHeader: View {
    let spot: Spot
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.sm) {
                Button(action: onBack) {
                    Label(String(localized: "Back to Places", comment: "VoiceOver"), systemImage: "chevron.backward")
                }
                .buttonStyle(GlassCircleButtonStyle())
                .help(String(localized: "Back to Places (Esc)", comment: "Tooltip on the place card's back button"))
                Spacer(minLength: 0)
                ShareLink(item: SpotHeaderView.shareURL(for: spot), subject: Text(spot.name),
                          message: Text(SpotHeaderView.shareMessage(for: spot))) {
                    Label(LightText.share, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GlassCircleButtonStyle())
                .help(String(localized: "Share this location", comment: "Help"))
                Button(action: onClose) {
                    Label(String(localized: "Close", comment: "VoiceOver"), systemImage: "xmark")
                }
                .buttonStyle(GlassCircleButtonStyle())
                .help(String(localized: "Close", comment: "Tooltip on the place card's close button"))
            }
        }
        // Concentric with the card's corner: the buttons sit as far from the edges as Maps' do.
        .padding(.horizontal, GlassCircleButtonStyle.inset)
        .padding(.top, GlassCircleButtonStyle.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .titlebarClickable()
    }
}
