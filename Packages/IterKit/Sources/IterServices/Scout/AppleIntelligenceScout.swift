import Foundation
import FoundationModels
import IterCore
import OSLog

/// Finds photography places from a natural-language request using the on-device model and real data.
///
/// The model never names a place on its own: it can only call tools that return Apple Maps results and curated spots,
/// and refer to what they returned by ID. Every suggestion is rebuilt from the tool results afterwards.
public struct AppleIntelligenceScout: Scouting {
    private let search: any PlaceSearching
    private let geocoder: any Geocoding
    private let drives: (any DriveTimeProviding)?
    private let curated: [Spot]

    private static let log = Logger(subsystem: "studio.paused.iter", category: "scout")

    public init(search: any PlaceSearching, geocoder: any Geocoding, drives: (any DriveTimeProviding)?, curated: [Spot]) {
        self.search = search
        self.geocoder = geocoder
        self.drives = drives
        self.curated = curated
    }

    public func availability() -> ScoutAvailability {
        ScoutAvailabilityMapping.map(SystemLanguageModel.default.availability)
    }

    /// Step 1: the model gathers candidates with the tools. Its text reply is discarded.
    static let gatheringInstructions = """
    You help photographers find places to shoot. Use findPlaces and curatedSpots to look up real places for the request. \
    Queries should name a natural feature (waterfall, forest trail, viewpoint, coast), not the weather. Search at most three times with different queries, then reply with the single word DONE.
    """

    /// Step 2: a fresh session, no tools, sees only the registered candidates and answers in a fixed shape.
    static let pickingInstructions = """
    You choose photography locations. Pick only from the candidate list, and refer to each by its ID exactly as listed. \
    Never invent a place, an ID or a coordinate. Choose at most 8, best first, and skip candidates that do not fit. \
    For each give one short, specific reason tied to the request (for example fog, forest, or which way the sun rises) and the best light. \
    If nothing fits, return no picks.
    """

    static let candidateLimit = 20

    public func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] {
        let state = availability()
        guard state == .available else { throw ScoutError.unavailable(state) }

        progress(.understanding)
        let registry = ScoutRegistry()
        let context = ScoutToolContext(search: search, geocoder: geocoder, drives: drives, curated: curated, registry: registry, progress: progress)
        var tools: [any Tool] = [FindPlacesTool(context: context), CuratedSpotsTool(context: context)]
        if drives != nil { tools.append(DriveTimeTool(context: context)) }

        do {
            try Task.checkCancellation()

            // Step 1: gather. A model that keeps calling tools can overflow its small context; if it already
            // found candidates that is not fatal, the answer step works from the registry.
            do {
                let gatherer = LanguageModelSession(model: .default, tools: tools, instructions: Self.gatheringInstructions)
                _ = try await gatherer.respond(to: request, options: GenerationOptions(maximumResponseTokens: 40))
            } catch {
                guard let mapped = ScoutError.map(error) else { throw CancellationError() }
                let found = await registry.candidateRows(limit: 1)
                if mapped != .contextTooLong || found.isEmpty { throw mapped }
                Self.log.notice("Gathering ran out of context; answering from what it found")
            }
            try Task.checkCancellation()

            let rows = await registry.candidateRows(limit: Self.candidateLimit)
            guard !rows.isEmpty else { throw ScoutError.noResults }

            // Step 2: pick. Tools have run, so this is when the answer really starts being written.
            progress(.writing)
            let prompt = "Request: \(request)\n\nCandidates (id | name | details):\n" + rows.joined(separator: "\n")
            let answer = try await Self.pick(prompt: prompt)

            let inputs = answer.picks.map { ResolvedPickInput(placeID: $0.placeID, why: $0.why, window: $0.window) }
            await enrichTimeZones(for: inputs, registry: registry)
            try Task.checkCancellation()
            let suggestions = ScoutGrounding.resolve(picks: inputs, registry: await registry.snapshot())
            guard !suggestions.isEmpty else { throw ScoutError.noResults }
            return suggestions
        } catch {
            guard let mapped = ScoutError.map(error) else { throw CancellationError() }
            Self.log.error("Scout failed: \(String(describing: mapped), privacy: .public)")
            throw mapped
        }
    }

    /// Guided generation occasionally fails to parse; one retry with a fresh session is enough in practice.
    /// Guardrail, language, context and availability errors are not retried.
    private static func pick(prompt: String) async throws -> ScoutAnswer {
        var attempt = 0
        while true {
            attempt += 1
            do {
                let picker = LanguageModelSession(model: .default, instructions: pickingInstructions)
                return try await picker.respond(to: prompt, generating: ScoutAnswer.self).content
            } catch {
                guard let mapped = ScoutError.map(error) else { throw CancellationError() }
                guard attempt < 2, case .failed = mapped else { throw mapped }
                log.notice("Pick step failed (\(String(describing: mapped), privacy: .public)); retrying once")
            }
        }
    }

    /// Looks up the time zone of picked Apple Maps places whose search result carried none. Best effort.
    private func enrichTimeZones(for picks: [ResolvedPickInput], registry: ScoutRegistry) async {
        for pick in picks.prefix(ScoutGrounding.maximumSuggestions) {
            guard !Task.isCancelled else { return }
            guard let place = await registry.place(pick.placeID), place.needsTimeZone else { continue }
            if let zone = try? await geocoder.reverseGeocode(place.coordinate).timeZoneIdentifier {
                await registry.setTimeZone(id: place.id, identifier: zone)
            }
        }
    }
}
