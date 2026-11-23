import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The ONE score a result shows: today's Sky Index for the place as a `ScoreChip`. Unknown shows the chip without a number
/// (and a spinner only while the store is still working); never a made-up value.
struct FindScoreChip: View, Equatable {
    let score: FindScore
    var size: ScoreChip.Size = .small
    var isSelected = false

    var body: some View {
        ScoreChip(kind: score.kind, start: score.start, score: score.value, zone: score.timeZone, size: size, timeStyle: .start,
                  isLowConfidence: score.isLowConfidence, isLoading: score.isLoading, isSelected: isSelected)
    }
}

extension FindPin {
    /// How many of the best-ranked result pins carry a chip (as the old Explore map did); a selected pin always does.
    static let chipRankLimit = 5

    /// True when the pin draws its score chip instead of the rank plate: it has a known score and is selected or near the top.
    func showsChip(isSelected: Bool) -> Bool {
        guard case .result(let rank) = kind, score?.value != nil else { return false }
        return isSelected || rank <= Self.chipRankLimit
    }
}
