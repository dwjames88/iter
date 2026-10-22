import SwiftUI
import IterDesign

/// The car on a drive row: a 20 pt disc in the user-location blue with a white car, as Maps marks driving.
struct DriveBadge: View {
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: "car.fill")
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(IterColor.userLocation, in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview("Drive badge, light") { DriveBadge().padding(IterSpace.xl).background(IterColor.backgroundWindow).preferredColorScheme(.light) }
#Preview("Drive badge, dark") { DriveBadge().padding(IterSpace.xl).background(IterColor.backgroundWindow).preferredColorScheme(.dark) }
