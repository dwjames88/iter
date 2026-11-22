import SwiftUI

/// The car on a drive row: a 20 pt disc in the user-location blue with a white car, as Maps marks driving.
/// Figma part: drive badge.
public struct DriveBadge: View {
    public var size: CGFloat

    public init(size: CGFloat = 20) { self.size = size }

    public var body: some View {
        Image(systemName: "car.fill")
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(IterColor.userLocation, in: Circle())
            .accessibilityHidden(true)
    }
}
