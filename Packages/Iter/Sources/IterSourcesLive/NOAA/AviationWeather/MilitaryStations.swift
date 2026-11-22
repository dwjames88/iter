import Foundation

/// Whether a METAR station is a military airfield. The feed has no such field, so this is derived:
/// (a) a curated list of ICAO ids, and (b) markers in the station name. Civil stations are never marked, and a
/// military field missing from both lists is reported as not military (the flag is a best effort, never a claim of civil).
public enum MilitaryStations {
    /// Known military airfields (US and allied) that publish METARs through aviationweather.gov.
    public static let icaoIDs: Set<String> = [
        "KNID", "KNFL", "KEDW", "KLSV", "KNKX", "KNZY", "KVBG", "KSKA", "KDMA", "KBAB", "KBIF", "KHMN",
        "ETAR", "LIPA", "ETAD", "EGUN", "EGUL", "RJTY", "RODN", "PAED", "PHNG",
        // Swiss Air Force: Meiringen, Emmen, Alpnach (helicopters), Payerne.
        "LSMM", "LSME", "LSMA", "LSMP",
    ]

    /// Uppercase abbreviations matched as whole words in the station name.
    static let abbreviationMarkers: Set<String> = ["AFB", "NAS", "NAWS", "MCAS", "AAF", "ANGB", "JRB"]
    /// Phrases matched case-insensitively.
    static let phraseMarkers = ["air force base", "naval air", "army airfield", "air base"]

    public static func isMilitary(icaoID: String, name: String?) -> Bool {
        if icaoIDs.contains(icaoID.uppercased()) { return true }
        guard let name else { return false }
        let words = name.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: abbreviationMarkers.contains) { return true }
        let lower = name.lowercased()
        return phraseMarkers.contains { lower.contains($0) }
    }
}
