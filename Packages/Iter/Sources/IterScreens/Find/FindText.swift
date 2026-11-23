import Foundation
import IterFeatures
import IterUI
import IterModel
import IterDiscovery

// Pure words and rules for the Find screens: nothing here draws, reads a clock or touches a service, so tests check it
// without rendering. Copy is Title Style on buttons; lines say what the thing is.

enum FindText {
    // MARK: Progress

    /// "1 min 5 s", "4 s".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 60 ? (s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s") : "\(s) s"
    }

    /// "3 of 7 sources done · 4 s" while running; "7 sources searched · 12 s" when over; "Stopped · 3 of 7 sources answered · 4 s".
    static func progressLine(_ p: FindProgress, phase: FindPhase) -> String {
        let time = elapsed(p.elapsed)
        guard p.total > 0 else { return phase == .discovering ? "Planning the search · \(time)" : "" }
        let sources = p.total == 1 ? "1 source" : "\(p.total) sources"
        switch phase {
        case .discovering: return "\(p.done) of \(sources) done · \(time)"
        case .cancelled: return "Stopped · \(p.done) of \(sources) answered · \(time)"
        case .failed: return "\(p.done) of \(sources) answered · \(time)"
        default: return "\(sources) searched · \(time)"
        }
    }

    /// "5 Places", "1 Place".
    static func resultCount(_ n: Int) -> String { n == 1 ? "1 Place" : "\(n) Places" }

    // MARK: Plan label

    /// The honest plan line: the model's own label, or a plain fallback when it says the search is basic without one.
    static func planLine(label: String?, isBasic: Bool) -> String? {
        if let label, !label.isEmpty { return label }
        return isBasic ? "Basic search: AI unavailable" : nil
    }

    // MARK: Verification and rows

    static func verificationShort(_ v: Verification) -> String {
        switch v {
        case .confirmed: "Confirmed"
        case .singleSource: "Single source"
        case .userPlaced: "Placed by you"
        }
    }

    static func verificationSymbol(_ v: Verification) -> String {
        switch v {
        case .confirmed: "checkmark.seal.fill"
        case .singleSource: "circle.lefthalf.filled"
        case .userPlaced: "mappin.circle.fill"
        }
    }

    /// "23 km from you · 25 min drive", "~25 min straight-line" when no router has answered.
    static func distanceLine(distanceText: String?, drive: DriveTime?) -> String? {
        let parts = [distanceText, drive?.text].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Mesa Arch, Canyonlands, Arch and Viewpoint, 23 km from you, Confirmed".
    static func rowAccessibility(_ row: FindRow, locality: String) -> String {
        var parts = [row.name]
        if !locality.isEmpty { parts.append(locality) }
        if !row.kindsText.isEmpty { parts.append(row.kindsText) }
        if let line = distanceLine(distanceText: row.distanceText, drive: row.drive) { parts.append(line) }
        parts.append(verificationShort(row.verification))
        if row.isSaved { parts.append("Saved") }
        if let score = row.score {
            parts.append(score.value == nil ? "Light score not available yet"
                         : ScoreChip.accessibilityText(kind: score.kind, start: score.start, zone: score.timeZone, score: score.value,
                                                       isLowConfidence: score.isLowConfidence))
        }
        return parts.joined(separator: ", ")
    }

    /// The locality and kinds line of a row: "Canyonlands · Arch, Viewpoint".
    static func subtitle(locality: String, kinds: String) -> String {
        [locality, kinds].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Sources

    enum Tone: Equatable { case normal, quiet, warning, danger }

    struct SourceDisplay: Equatable, Identifiable {
        var id: String
        var name: String
        var detail: String
        var symbol: String
        var tone: Tone
        var isWorking: Bool
    }

    /// One row of the per-source list: the name and a plain state (count, slow, down with reason, unavailable with reason, skipped).
    static func sourceDisplay(_ c: SourceChip) -> SourceDisplay {
        let noun: String
        switch c.role {
        case .geocoder: noun = "area"
        case .boundary: noun = "outline"
        case .gazetteer, .placeSearch: noun = "place"
        case .text: noun = "document"
        case .photos: noun = "photo"
        case .ai: noun = "plan"
        }
        let detail: String, symbol: String, tone: Tone
        switch c.state {
        case .searching: (detail, symbol, tone) = ("Searching…", "ellipsis.circle", .quiet)
        case .slow: (detail, symbol, tone) = ("Slow: still searching, others are not held up", "tortoise.fill", .warning)
        case .found(let n):
            let what = c.role == .ai ? "Planned the search" : (n == 1 ? "1 \(noun)" : "\(n) \(noun)s")
            (detail, symbol, tone) = (what, "checkmark.circle.fill", .normal)
        case .empty: (detail, symbol, tone) = ("Nothing found", "minus.circle", .quiet)
        case .down: (detail, symbol, tone) = ("Down: \(c.reason ?? "no answer")", "exclamationmark.triangle.fill", .danger)
        case .unavailable: (detail, symbol, tone) = ("Unavailable: \(c.reason ?? "cannot be used")", "nosign", .quiet)
        case .skipped: (detail, symbol, tone) = ("Skipped: \(c.reason ?? "not asked")", "forward.circle", .quiet)
        }
        return SourceDisplay(id: c.id, name: c.name, detail: detail, symbol: symbol, tone: tone, isWorking: c.isWorking)
    }

    /// "1 slow, 1 down" for the disclosure's closed label; nil when everything is fine.
    static func sourceTrouble(_ chips: [SourceChip]) -> String? {
        let slow = chips.filter { $0.state == .slow }.count
        let down = chips.filter { $0.state == .down }.count
        let parts = [slow > 0 ? "\(slow) slow" : nil, down > 0 ? "\(down) down" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Coordinates

    /// "38.3884°N 109.8680°W".
    static func coordinateLine(_ c: Coordinate) -> String {
        let lat = String(format: "%.4f°%@", abs(c.latitude), c.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.4f°%@", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
        return "\(lat) \(lon)"
    }

    /// The quiet provenance line under the readouts: "Military Grid Reference System, Military-origin standard (NGA), computed on device".
    static func readoutSources(_ r: PositionReadout) -> [String] {
        var lines: [String] = []
        if let s = r.mgrsSource, r.mgrs != nil { lines.append("MGRS: \(s)") }
        if let s = r.declinationSource, r.declinationText != nil { lines.append("Declination: \(s)") }
        if let n = r.declinationNote { lines.append(n) }
        return lines
    }
}

/// What the floating card shows, in order of precedence: an open place card, then the discovery run (progress and results),
/// then a typed lookup, then the suggestion rows for text not yet run, else no card at all.
enum FindCardMode: Equatable {
    case hidden
    case suggestions
    case lookup
    case results
    case place

    static func resolve(hasCard: Bool, phase: FindPhase, hasChips: Bool, hasRows: Bool, hasMatches: Bool, hasText: Bool) -> FindCardMode {
        if hasCard { return .place }
        let ranDiscovery = hasChips || hasRows
        switch phase {
        case .discovering: return .results
        case .lookingUp: return .lookup
        case .finished, .cancelled, .failed:
            if ranDiscovery { return .results }
            if case .failed = phase { return .results }
            if hasMatches { return .lookup }
            if phase == .finished, hasText { return .lookup }
            return hasText ? .suggestions : .hidden
        case .idle:
            return hasText ? .suggestions : .hidden
        }
    }
}

/// When the Search Here button shows: the map has a region, nothing is running, and the list does not describe the map any more.
enum FindSearchHereRule {
    /// The centre moved more than a quarter of the searched area, or the zoom changed by more than a factor of 1.6.
    static func isStale(searched: GeoRegion?, visible: GeoRegion?) -> Bool {
        guard let visible else { return false }
        guard let searched else { return true }
        let dLat = abs(visible.center.latitude - searched.center.latitude) / max(searched.latitudeDelta, 1e-6)
        let dLon = abs(visible.center.longitude - searched.center.longitude) / max(searched.longitudeDelta, 1e-6)
        if max(dLat, dLon) > 0.25 { return true }
        let zoom = visible.latitudeDelta / max(searched.latitudeDelta, 1e-6)
        return zoom > 1.6 || zoom < 1 / 1.6
    }

    static func shows(phase: FindPhase, searched: GeoRegion?, visible: GeoRegion?) -> Bool {
        if phase == .discovering || phase == .lookingUp { return false }
        return isStale(searched: searched, visible: visible)
    }
}

/// The region that fits a cluster's members, for a click on a cluster.
enum FindClusterZoom {
    static func region(for cluster: FindCluster, rows: [FindRow]) -> GeoRegion? {
        let members = Set(cluster.memberIDs)
        let coordinates = rows.filter { members.contains($0.id) }.map(\.coordinate)
        return GeoRegion.enclosing(coordinates.isEmpty ? [cluster.coordinate] : coordinates, padding: 0.4, minimumDelta: 0.01)
    }
}
