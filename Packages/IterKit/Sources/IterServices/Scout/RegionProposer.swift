import Foundation
import FoundationModels
import IterCore
import OSLog

/// What the model proposes for a map area. A shape for guided generation only: the names are checked against a real
/// search before anything is shown.
@Generable
struct RegionProposalAnswer: Equatable {
    @Guide(description: "At most 8 real, named photography locations inside the box. Fewer is better than invented.", .maximumCount(8))
    var places: [RegionProposalItem]
}

@Generable
struct RegionProposalItem: Equatable {
    @Guide(description: "The place's proper name as it appears on a map, for example \"Mirror Lake\".")
    var name: String
    @Guide(description: "One short sentence on why a photographer would go.")
    var why: String
    @Guide(description: "Approximate latitude in degrees, only if sure.")
    var latitude: Double?
    @Guide(description: "Approximate longitude in degrees, only if sure.")
    var longitude: Double?
}

extension AppleIntelligenceScout {
    static let proposalInstructions = """
    You name photography locations for a map area. Propose well-known, named photography locations (viewpoints, \
    parks, lakes, beaches, peaks, landmarks, waterfalls) inside the given box. Only real named places; fewer is \
    better than invented. Never invent a place. Use the place's proper name.
    """

    /// The prompt for one area: the box (south, west, north, east to three decimals) and the locality when known.
    static func proposalPrompt(region: GeoRegion, areaName: String?) -> String {
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        let south = region.center.latitude - region.latitudeDelta / 2
        let north = region.center.latitude + region.latitudeDelta / 2
        let west = region.center.longitude - region.longitudeDelta / 2
        let east = region.center.longitude + region.longitudeDelta / 2
        var prompt = "Area: south \(f(south)), west \(f(west)), north \(f(north)), east \(f(east))."
        if let areaName, !areaName.isEmpty { prompt += " Around \(areaName)." }
        prompt += " Propose well-known, named photography locations (viewpoints, parks, lakes, beaches, peaks, landmarks, waterfalls) inside this box."
        return prompt
    }

    /// Asks the on-device model for places in the region. Names only: the caller validates each against a search.
    /// A failed parse is retried once with greedy sampling.
    public func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal] {
        let state = availability()
        guard state == .available else { throw ScoutError.unavailable(state) }
        let prompt = Self.proposalPrompt(region: region, areaName: areaName)
        var attempt = 0
        while true {
            attempt += 1
            do {
                try Task.checkCancellation()
                let session = LanguageModelSession(model: .default, instructions: Self.proposalInstructions)
                let options = attempt == 1 ? GenerationOptions(maximumResponseTokens: 600)
                                           : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 600)
                let answer = try await session.respond(to: prompt, generating: RegionProposalAnswer.self, options: options).content
                return answer.places.prefix(8).compactMap { item in
                    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    var approximate: Coordinate?
                    if let lat = item.latitude, let lon = item.longitude, abs(lat) <= 90, abs(lon) <= 180 {
                        approximate = Coordinate(latitude: lat, longitude: lon)
                    }
                    return RegionProposal(name: name, why: item.why.trimmingCharacters(in: .whitespacesAndNewlines), approximate: approximate)
                }
            } catch {
                guard let mapped = ScoutError.map(error) else { throw CancellationError() }
                guard attempt < 2, case .failed = mapped else { throw mapped }
                Logger(subsystem: "com.dwjames.iter", category: "scout")
                    .notice("Region proposal failed (\(String(describing: mapped), privacy: .public)); retrying")
            }
        }
    }
}
