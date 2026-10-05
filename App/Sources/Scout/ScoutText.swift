import Foundation
import IterCore
import IterServices
import IterFeatures

/// Scout phrasing. The scout's own wording is always labelled as the scout's; everything else here is Iter's.
extension LightText {
    static let scoutPrompt = String(localized: "What are you looking for?", comment: "Scout request field placeholder")

    static let scoutExamples: [String] = [
        String(localized: "Foggy forest spots within two hours of Portland for sunrise", comment: "Scout example request"),
        String(localized: "Waterfalls near Seattle that work on overcast days", comment: "Scout example request"),
        String(localized: "Dark-sky places near Moab for the Milky Way", comment: "Scout example request"),
        String(localized: "Coastal sunset viewpoints near Big Sur", comment: "Scout example request"),
    ]

    static let scoutSourceLine = String(
        localized: "Places come from Apple Maps and Iter's curated list. Iter checks every place exists; the notes are written by Apple Intelligence.",
        comment: "Scout results footer: where places and notes come from")

    static let scoutNoteLabel = String(localized: "Scout's note", comment: "Label above the on-device model's one-line reason for a suggestion")

    // MARK: Progress

    static let scoutStageCount = 4

    /// Zero-based position in the four stages.
    static func scoutStageIndex(_ stage: ScoutProgress) -> Int {
        switch stage {
        case .understanding: 0
        case .searching: 1
        case .checkingDrive: 2
        case .writing: 3
        }
    }

    static func scoutStage(_ stage: ScoutProgress) -> String {
        switch stage {
        case .understanding:
            String(localized: "Understanding your request", comment: "Scout progress stage")
        case .searching(let place):
            place.isEmpty
                ? String(localized: "Searching for places", comment: "Scout progress stage")
                : String(localized: "Searching near \(place)", comment: "Scout progress stage, with the place being searched")
        case .checkingDrive(let place):
            place.isEmpty
                ? String(localized: "Checking the drive", comment: "Scout progress stage")
                : String(localized: "Checking the drive to \(place)", comment: "Scout progress stage, with the destination")
        case .writing:
            String(localized: "Choosing the best matches", comment: "Scout progress stage")
        }
    }

    static func scoutElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static let scoutSlow = String(localized: "Still working. A request can take up to a minute.", comment: "Scout is taking longer than usual")

    // MARK: Availability

    struct ScoutNotice {
        var title: String
        var detail: String
        var symbol: String
    }

    static func scoutUnavailable(_ availability: ScoutAvailability) -> ScoutNotice {
        switch availability {
        case .available:
            ScoutNotice(title: "", detail: "", symbol: "sparkles")
        case .deviceNotEligible:
            ScoutNotice(title: String(localized: "This Mac can't run Apple Intelligence", comment: "Scout unavailable title"),
                        detail: String(localized: "Scout needs Apple Intelligence, which this Mac doesn't support. Searching places in Explore works without it.",
                                       comment: "Scout unavailable detail: device not eligible"),
                        symbol: "macbook.slash")
        case .appleIntelligenceNotEnabled:
            ScoutNotice(title: String(localized: "Apple Intelligence is turned off", comment: "Scout unavailable title"),
                        detail: String(localized: "Turn on Apple Intelligence in System Settings to describe the place you want in your own words.",
                                       comment: "Scout unavailable detail: Apple Intelligence not enabled"),
                        symbol: "sparkles")
        case .modelNotReady:
            ScoutNotice(title: String(localized: "Apple Intelligence is still downloading", comment: "Scout unavailable title"),
                        detail: String(localized: "Scout will be ready when the download finishes. It can take a while the first time.",
                                       comment: "Scout unavailable detail: model not ready"),
                        symbol: "arrow.down.circle")
        case .unavailable:
            ScoutNotice(title: String(localized: "Scout isn't available right now", comment: "Scout unavailable title"),
                        detail: String(localized: "Apple Intelligence reported it can't run. Searching places in Explore still works.",
                                       comment: "Scout unavailable detail: other reason"),
                        symbol: "exclamationmark.triangle")
        }
    }

    // MARK: Failures

    static func scoutFailure(_ failure: ScoutFailure) -> ScoutNotice {
        switch failure {
        case .unavailable(let a):
            scoutUnavailable(a)
        case .noResults:
            ScoutNotice(title: String(localized: "Nothing matched", comment: "Scout failure title"),
                        detail: String(localized: "Nothing matched; try a wider area or a simpler description.", comment: "Scout failure: no results"),
                        symbol: "magnifyingglass")
        case .guardrail:
            ScoutNotice(title: String(localized: "Scout can't help with that request", comment: "Scout failure title"),
                        detail: String(localized: "Apple Intelligence declined it. Try describing the kind of scenery and the area you want.",
                                       comment: "Scout failure: safety guardrail"),
                        symbol: "hand.raised")
        case .tooLong:
            ScoutNotice(title: String(localized: "That request is too long", comment: "Scout failure title"),
                        detail: String(localized: "Shorten it to a sentence: the kind of place, the area and the light.", comment: "Scout failure: too long"),
                        symbol: "text.line.first.and.arrowtriangle.forward")
        case .unsupportedLanguage:
            ScoutNotice(title: String(localized: "Scout doesn't support that language", comment: "Scout failure title"),
                        detail: String(localized: "Apple Intelligence can't read this language yet. Try another language, or search in Explore.",
                                       comment: "Scout failure: unsupported language"),
                        symbol: "character.bubble")
        case .failed:
            ScoutNotice(title: String(localized: "Scout couldn't finish", comment: "Scout failure title"),
                        detail: String(localized: "Something went wrong while searching. Try again, or search places in Explore.", comment: "Scout failure: generic"),
                        symbol: "exclamationmark.triangle")
        }
    }

    static func scoutDrive(_ seconds: TimeInterval) -> String {
        String(localized: "\(TimeText.duration(seconds)) drive", comment: "Drive time to a scouted place, e.g. 1 h 30 min drive")
    }
}
