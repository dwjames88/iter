import Foundation
import IterCore

/// A place a tool returned. The ONLY source of names and coordinates in a scout answer.
struct RegisteredPlace: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case curated(Spot)
        case map(PlaceResult)
    }

    /// Short ID the model sees: "m1", "m2" (MapKit) or "c:<slug>" (curated).
    var id: String
    var source: Source
    var driveSeconds: TimeInterval?
    /// The compact table row the tool showed, reused to list candidates for the answer step.
    var summary: String = ""
    /// Time zone found by reverse geocoding after generation, for map places whose result carried none.
    var resolvedTimeZoneIdentifier: String?

    var name: String {
        switch source {
        case .curated(let s): s.name
        case .map(let r): r.name
        }
    }

    var coordinate: Coordinate {
        switch source {
        case .curated(let s): s.coordinate
        case .map(let r): r.coordinate
        }
    }

    var needsTimeZone: Bool {
        if case .map(let r) = source { return r.timeZoneIdentifier == nil && resolvedTimeZoneIdentifier == nil }
        return false
    }
}

/// Everything the tools returned during one scout run, keyed by the short ID. Also holds the drive budget and a geocode cache.
actor ScoutRegistry {
    static let driveBudget = 5
    /// Search and curated lookups share this budget so the transcript stays inside the model's 4,096-token context.
    static let searchBudget = 4

    private var places: [String: RegisteredPlace] = [:]
    private var order: [String] = []
    private var mapIDs: [String: String] = [:]
    private var nextMapNumber = 1
    private var driveCalls = 0
    private var searchCalls = 0
    private var geocodes: [String: PlaceResult] = [:]

    /// Registers a MapKit result; the same underlying place always gets the same short ID.
    func register(_ result: PlaceResult, summary: String = "") -> RegisteredPlace {
        let key = result.id.isEmpty ? "\(result.name)|\(result.coordinate.cacheKey)" : result.id
        if let existing = mapIDs[key], let place = places[existing] { return place }
        let id = "m\(nextMapNumber)"
        nextMapNumber += 1
        let place = RegisteredPlace(id: id, source: .map(result), driveSeconds: nil, summary: summary, resolvedTimeZoneIdentifier: nil)
        places[id] = place
        order.append(id)
        mapIDs[key] = id
        return place
    }

    func registerCurated(_ spot: Spot, summary: String = "") -> RegisteredPlace {
        let id = "c:" + spot.id.lowercased()
        if let existing = places[id] { return existing }
        let place = RegisteredPlace(id: id, source: .curated(spot), driveSeconds: nil, summary: summary, resolvedTimeZoneIdentifier: nil)
        places[id] = place
        order.append(id)
        return place
    }

    /// Candidate rows in the order the tools returned them, for the answer step.
    func candidateRows(limit: Int) -> [String] {
        order.prefix(limit).compactMap { places[$0].map { "\($0.id) | \($0.summary.isEmpty ? $0.name : $0.summary)" } }
    }

    func place(_ id: String) -> RegisteredPlace? { places[Self.normalise(id)] }

    func snapshot() -> [String: RegisteredPlace] { places }

    /// Takes one drive call from the budget. False once the budget is spent.
    func reserveDriveCall() -> Bool {
        guard driveCalls < Self.driveBudget else { return false }
        driveCalls += 1
        return true
    }

    /// Takes one search or curated lookup from the budget. False once the budget is spent.
    func reserveSearchCall() -> Bool {
        guard searchCalls < Self.searchBudget else { return false }
        searchCalls += 1
        return true
    }

    func recordDrive(id: String, seconds: TimeInterval) {
        places[Self.normalise(id)]?.driveSeconds = seconds
    }

    func setTimeZone(id: String, identifier: String) {
        places[Self.normalise(id)]?.resolvedTimeZoneIdentifier = identifier
    }

    func cachedGeocode(_ query: String) -> PlaceResult? { geocodes[Self.normalise(query)] }
    func cacheGeocode(_ query: String, _ result: PlaceResult) { geocodes[Self.normalise(query)] = result }

    /// Models sometimes change case or add spaces to an ID they were given.
    static func normalise(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
