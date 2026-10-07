import Foundation
import IterCore
import IterServices
import IterFeatures

/// Phrasing for Ask in Explore's search field (the old Scout screen's words, moved). The model's own wording is
/// always labelled as Apple Intelligence's; everything else here is Iter's.
extension LightText {
    // MARK: Suggestions

    static func suggestionGroup(_ suggestion: SearchSuggestion) -> String {
        switch suggestion.kind {
        case .appleMaps: String(localized: "Apple Maps", comment: "Search suggestions group title: place lookup")
        case .ask: String(localized: "Ask Iter", comment: "Search suggestions group title: ask Apple Intelligence")
        }
    }

    static func suggestionTitle(_ suggestion: SearchSuggestion) -> String {
        switch suggestion.kind {
        case .appleMaps(let query): searchApple(query)
        case .ask(let query, _): String(localized: "Ask Iter: \(query)", comment: "Search suggestion that puts the search text to Apple Intelligence")
        }
    }

    /// Second line: what the row does, or, for an Ask that cannot run, why not.
    static func suggestionDetail(_ suggestion: SearchSuggestion) -> String? {
        switch suggestion.kind {
        case .appleMaps: nil
        case .ask(_, let availability):
            availability == .available
                ? String(localized: "Find real places that fit, with a note on why", comment: "Second line of the Ask Iter suggestion")
                : askUnavailableShort(availability)
        }
    }

    static func askUnavailableShort(_ availability: ScoutAvailability) -> String {
        switch availability {
        case .available, .unavailable:
            String(localized: "Ask Iter isn't available right now", comment: "Ask suggestion, disabled: no specific reason")
        case .deviceNotEligible:
            String(localized: "Ask Iter isn't available: this Mac can't run Apple Intelligence", comment: "Ask suggestion, disabled: device not eligible")
        case .appleIntelligenceNotEnabled:
            String(localized: "Ask Iter isn't available: Apple Intelligence is off", comment: "Ask suggestion, disabled: Apple Intelligence off")
        case .modelNotReady:
            String(localized: "Ask Iter isn't available: Apple Intelligence is still downloading", comment: "Ask suggestion, disabled: model not ready")
        }
    }

    static func suggestionAccessibility(_ suggestion: SearchSuggestion) -> String {
        switch suggestion.kind {
        case .appleMaps(let query):
            String(localized: "Search Apple Maps for \(query)", comment: "VoiceOver label of the Apple Maps suggestion")
        case .ask(let query, let availability):
            availability == .available
                ? String(localized: "Ask Iter: \(query)", comment: "VoiceOver label of the Ask suggestion")
                : String(localized: "Ask Iter: \(query), unavailable. \(askUnavailableShort(availability))", comment: "VoiceOver label of the disabled Ask suggestion, with the reason")
        }
    }

    // MARK: Section

    static func askRequest(_ request: String) -> String {
        String(localized: "“\(request)”", comment: "The request an Ask section answers, shown under its header")
    }

    static let askSourceLine = String(
        localized: "Places come from Apple Maps and Iter's curated list. Iter checks every place exists; the notes are written by Apple Intelligence.",
        comment: "Ask section footer: where places and notes come from")

    static let askNoteLabel = String(localized: "Note from Apple Intelligence", comment: "VoiceOver prefix and tooltip of the on-device model's one-line reason for a suggestion")

    static func askRowAccessibility(_ row: ExploreRow, showsDistance: Bool) -> String {
        var parts = [rowDescription(row, showsDistance: showsDistance)]
        if let seconds = row.driveSeconds { parts.append(askDrive(seconds)) }
        if let note = row.note { parts.append(askNoteLabel + ": " + note) }
        return parts.joined(separator: ", ")
    }

    // MARK: Progress

    static let askStageCount = 4

    /// Zero-based position in the four stages.
    static func askStageIndex(_ stage: ScoutProgress) -> Int {
        switch stage {
        case .understanding: 0
        case .searching: 1
        case .checkingDrive: 2
        case .writing: 3
        }
    }

    static func askStage(_ stage: ScoutProgress) -> String {
        switch stage {
        case .understanding:
            String(localized: "Understanding your request", comment: "Ask progress stage")
        case .searching(let place):
            place.isEmpty
                ? String(localized: "Searching for places", comment: "Ask progress stage")
                : String(localized: "Searching near \(place)", comment: "Ask progress stage, with the place being searched")
        case .checkingDrive(let place):
            place.isEmpty
                ? String(localized: "Checking the drive", comment: "Ask progress stage")
                : String(localized: "Checking the drive to \(place)", comment: "Ask progress stage, with the destination")
        case .writing:
            String(localized: "Choosing the best matches", comment: "Ask progress stage")
        }
    }

    static func askStep(_ stage: ScoutProgress) -> String {
        String(localized: "Step \(askStageIndex(stage) + 1) of \(askStageCount)", comment: "Ask progress, e.g. Step 2 of 4")
    }

    static func askElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static let askSlow = String(localized: "Still working. A request can take up to a minute.", comment: "Ask is taking longer than usual")

    static let askCancel = String(localized: "Cancel", comment: "Button: stop the running Ask")
    static let askCancelHelp = String(localized: "Stop looking", comment: "Tooltip on the Cancel button while an Ask runs")

    // MARK: Availability

    struct AskNotice {
        var title: String
        var detail: String
        var symbol: String
    }

    static func askUnavailable(_ availability: ScoutAvailability) -> AskNotice {
        switch availability {
        case .available:
            AskNotice(title: "", detail: "", symbol: "sparkles")
        case .deviceNotEligible:
            AskNotice(title: String(localized: "This Mac can't run Apple Intelligence", comment: "Ask unavailable title"),
                      detail: String(localized: "Ask Iter needs Apple Intelligence, which this Mac doesn't support. Searching places in Explore works without it.",
                                     comment: "Ask unavailable detail: device not eligible"),
                      symbol: "macbook.slash")
        case .appleIntelligenceNotEnabled:
            AskNotice(title: String(localized: "Apple Intelligence is turned off", comment: "Ask unavailable title"),
                      detail: String(localized: "Turn on Apple Intelligence in System Settings to describe the place you want in your own words.",
                                     comment: "Ask unavailable detail: Apple Intelligence not enabled"),
                      symbol: "sparkles")
        case .modelNotReady:
            AskNotice(title: String(localized: "Apple Intelligence is still downloading", comment: "Ask unavailable title"),
                      detail: String(localized: "Ask Iter will be ready when the download finishes. It can take a while the first time.",
                                     comment: "Ask unavailable detail: model not ready"),
                      symbol: "arrow.down.circle")
        case .unavailable:
            AskNotice(title: String(localized: "Ask Iter isn't available right now", comment: "Ask unavailable title"),
                      detail: String(localized: "Apple Intelligence reported it can't run. Searching places in Explore still works.",
                                     comment: "Ask unavailable detail: other reason"),
                      symbol: "exclamationmark.triangle")
        }
    }

    // MARK: Failures

    static func askFailure(_ failure: ScoutFailure) -> AskNotice {
        switch failure {
        case .unavailable(let a):
            askUnavailable(a)
        case .noResults:
            AskNotice(title: String(localized: "Nothing matched", comment: "Ask failure title"),
                      detail: String(localized: "Nothing matched; try a wider area or a simpler description.", comment: "Ask failure: no results"),
                      symbol: "magnifyingglass")
        case .guardrail:
            AskNotice(title: String(localized: "Ask Iter can't help with that request", comment: "Ask failure title"),
                      detail: String(localized: "Apple Intelligence declined it. Try describing the kind of scenery and the area you want.",
                                     comment: "Ask failure: safety guardrail"),
                      symbol: "hand.raised")
        case .tooLong:
            AskNotice(title: String(localized: "That request is too long", comment: "Ask failure title"),
                      detail: String(localized: "Shorten it to a sentence: the kind of place, the area and the light.", comment: "Ask failure: too long"),
                      symbol: "text.line.first.and.arrowtriangle.forward")
        case .unsupportedLanguage:
            AskNotice(title: String(localized: "Ask Iter doesn't support that language", comment: "Ask failure title"),
                      detail: String(localized: "Apple Intelligence can't read this language yet. Try another language, or search in Explore.",
                                     comment: "Ask failure: unsupported language"),
                      symbol: "character.bubble")
        case .failed:
            AskNotice(title: String(localized: "Ask Iter couldn't finish", comment: "Ask failure title"),
                      detail: String(localized: "Something went wrong while searching. Try again, or search places in Explore.", comment: "Ask failure: generic"),
                      symbol: "exclamationmark.triangle")
        }
    }

    static let askSearchInstead = String(localized: "Search Apple Maps Instead", comment: "Button under an Ask that could not run: use the ordinary place search")
    static let askOpenSystemSettings = String(localized: "Open System Settings", comment: "Button: opens Apple Intelligence & Siri settings")
    static let askTryAgain = String(localized: "Try Again", comment: "Button: run the Ask again")

    static func askDrive(_ seconds: TimeInterval) -> String {
        String(localized: "\(TimeText.duration(seconds)) drive", comment: "Drive time to a suggested place, e.g. 1 h 30 min drive")
    }
}
