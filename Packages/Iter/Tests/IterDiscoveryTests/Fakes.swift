import Foundation
import IterAI
import IterModel
import IterSources
import Synchronization
import Testing
@testable import IterDiscovery

// Scripted fakes for every provider kind and for the language model. No network, no clock reads.

let testNow = Date(timeIntervalSince1970: 1_800_000_000)

func descriptor(_ id: SourceID, _ name: String, kinds: Set<DataKind>, coverage: Coverage = .global, timeout: Duration = .seconds(20)) -> SourceDescriptor {
    SourceDescriptor(id: id, name: name, operatorName: name, tier: .openData, origin: SourceOrigin(tier: .openData, producer: name), kinds: kinds,
                     coverage: coverage, policy: RequestPolicy(timeout: timeout), cacheTTL: .seconds(3600),
                     licence: LicenceTag(key: "test", mayStore: true))
}

func citation(_ source: SourceID, _ title: String) -> Citation {
    Citation(source: source, url: URL(string: "https://example.test/\(title.replacingOccurrences(of: " ", with: "_"))"), title: title, retrievedAt: testNow)
}

/// Records what a fake saw: calls, and cancellations delivered while it waited.
final class CallLog: Sendable {
    private let state = Mutex<(calls: [String], cancelled: Int)>(([], 0))
    func record(_ s: String) { state.withLock { $0.calls.append(s) } }
    func noteCancelled() { state.withLock { $0.cancelled += 1 } }
    var calls: [String] { state.withLock { $0.calls } }
    var cancelledCount: Int { state.withLock { $0.cancelled } }
}

struct Script: Sendable {
    var delay: Duration = .zero
    var error: SourceError?
}

private func play(_ script: Script, _ log: CallLog) async throws {
    if script.delay > .zero {
        do { try await Task.sleep(for: script.delay) } catch { log.noteCancelled(); throw SourceError.cancelled }
    }
    if let e = script.error { throw e }
}

struct FakeGeocoder: Geocoder {
    var descriptor: SourceDescriptor = IterDiscoveryTests.descriptor("fake.geocoder", "Fake Geocoder", kinds: [.geocode])
    /// Lower-case fragment of the query to results.
    var answers: [String: [GeocodeResult]] = [:]
    var script = Script()
    var log = CallLog()

    func geocode(_ text: String, near region: GeoRegion?) async throws -> [GeocodeResult] {
        log.record("geocode:\(text)")
        try await play(script, log)
        let lower = text.lowercased()
        for key in answers.keys.sorted(by: { $0.count > $1.count }) where lower.contains(key) { return answers[key] ?? [] }
        return []
    }
    func reverse(_ coordinate: Coordinate) async throws -> GeocodeResult { throw SourceError.noSource }
    func boundary(of name: String, near coordinate: Coordinate?) async throws -> GeoPolygon? { nil }
}

struct FakeBoundary: BoundaryProvider {
    var descriptor: SourceDescriptor = IterDiscoveryTests.descriptor("fake.boundary", "Fake Boundaries", kinds: [.boundary])
    var answer: NamedBoundary?
    var script = Script()
    var log = CallLog()
    func boundary(named name: String, near: Coordinate?) async throws -> NamedBoundary? {
        log.record("boundary:\(name)")
        try await play(script, log)
        return answer
    }
}

struct FakeGazetteer: GazetteerProvider {
    var descriptor: SourceDescriptor
    var places: [PlaceCandidate]
    var script = Script()
    var log = CallLog()
    func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] {
        log.record("gazetteer")
        try await play(script, log)
        return places
    }
}

struct FakePlaceSearch: PlaceSearchProvider {
    var descriptor: SourceDescriptor
    /// Lower-case fragment of the query to results.
    var answers: [String: [PlaceCandidate]]
    var script = Script()
    var log = CallLog()
    func search(_ text: String, near region: GeoRegion) async throws -> [PlaceCandidate] {
        log.record("search:\(text)")
        try await play(script, log)
        let lower = text.lowercased()
        var out: [PlaceCandidate] = []
        for (k, v) in answers where lower.contains(k) { out += v }
        return out
    }
}

struct FakeText: TextEvidenceProvider {
    var descriptor: SourceDescriptor
    var docs: [EvidenceDocument]
    var script = Script()
    var log = CallLog()
    func documents(for query: TextQuery, in area: DiscoveryArea) async throws -> [EvidenceDocument] {
        log.record("documents")
        try await play(script, log)
        return docs
    }
}

struct FakePhotos: PhotoEvidenceProvider {
    var descriptor: SourceDescriptor = IterDiscoveryTests.descriptor("fake.commons", "Fake Commons", kinds: [.photoEvidence])
    /// Photo count by the call's centre cache key; default `defaultCount`.
    var counts: [String: Int] = [:]
    var defaultCount = 0
    var script = Script()
    var log = CallLog()
    func evidence(near center: Coordinate, radiusM: Double) async throws -> PhotoEvidence {
        log.record("photos:\(center.cacheKey)")
        try await play(script, log)
        let n = counts[center.cacheKey] ?? defaultCount
        return PhotoEvidence(center: center, radiusM: radiusM, count: n, photos: [])
    }
}

/// A scripted language model: JSON per output type name, a text handler for `respond`, an availability switch, delays that
/// honour cancellation, and a record of every prompt.
final class FakeModel: LanguageModeling {
    struct State {
        var availability: AIAvailability = .available
        var json: [String: String] = [:]
        var respond: @Sendable (AIPrompt) -> String = { _ in "" }
        var generateError: AIError?
        var delay: Duration = .zero
        var prompts: [String] = []
        var cancelled = 0
        var respondInFlight = 0
        var respondPeak = 0
    }
    private let state = Mutex(State())

    init(availability: AIAvailability = .available) { state.withLock { $0.availability = availability } }

    func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
    var prompts: [String] { state.withLock { $0.prompts } }
    var cancelledCount: Int { state.withLock { $0.cancelled } }
    var respondPeak: Int { state.withLock { $0.respondPeak } }

    func availability() async -> AIAvailability { state.withLock { $0.availability } }

    private func wait() async throws {
        let d = state.withLock { $0.delay }
        guard d > .zero else { return }
        do { try await Task.sleep(for: d) } catch { state.withLock { $0.cancelled += 1 }; throw AIError.cancelled }
    }

    func generate<Output: AIGenerable>(_ type: Output.Type, prompt: AIPrompt, options: AICallOptions) async throws -> Output {
        state.withLock { $0.prompts.append(prompt.prompt) }
        try await wait()
        let (err, json) = state.withLock { ($0.generateError, $0.json[String(describing: Output.self)]) }
        if let err { throw err }
        guard let json else { throw AIError.generation("no script for \(Output.self)") }
        do { return try JSONDecoder().decode(Output.self, from: Data(json.utf8)) } catch { throw AIError.decoding("\(error)") }
    }

    func respond(prompt: AIPrompt, options: AICallOptions) async throws -> String {
        let handler = state.withLock { s -> @Sendable (AIPrompt) -> String in
            s.prompts.append(prompt.prompt)
            s.respondInFlight += 1
            s.respondPeak = max(s.respondPeak, s.respondInFlight)
            return s.respond
        }
        defer { state.withLock { $0.respondInFlight -= 1 } }
        try await wait()
        return handler(prompt)
    }
}

// MARK: Test geography

enum Geo {
    static let lonePine = Coordinate(latitude: 36.6063, longitude: -118.0629)
    static let yosemite = Coordinate(latitude: 37.74, longitude: -119.55)
}

func candidate(_ name: String, _ lat: Double, _ lon: Double, kinds: [FeatureKind], source: SourceID, externalID: String? = nil,
               mentions: Int = 0, snippet: String? = nil) -> PlaceCandidate {
    PlaceCandidate(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), featureKinds: kinds, source: source, externalID: externalID,
                   citations: [citation(source, name)], mentionCount: mentions, snippet: snippet)
}

let osmID = SourceID.osmOverpass
let mapkitSearchID = SourceID.appleSearch
let wikiID = SourceID.wikipedia

func doc(_ title: String, _ text: String, source: SourceID = .wikipedia, at c: Coordinate? = nil) -> EvidenceDocument {
    EvidenceDocument(title: title, text: text, url: URL(string: "https://example.test/\(title.replacingOccurrences(of: " ", with: "_"))"), coordinate: c,
                     citation: citation(source, title))
}

/// Every coordinate any fake handed out, for the grounding assertion.
struct Supplied {
    var coordinates: Set<Coordinate> = []
    mutating func add(_ c: Coordinate?) { if let c { coordinates.insert(c) } }
    mutating func add(_ cs: [PlaceCandidate]) { for c in cs { add(c.coordinate) } }
    mutating func add(_ gs: [GeocodeResult]) { for g in gs { add(g.coordinate) } }
    mutating func add(docs: [EvidenceDocument]) { for d in docs { add(d.coordinate) } }
}

/// The grounding invariant: every place sits at exactly a coordinate a provider returned.
func assertGrounded(_ places: [DiscoveredPlace], supplied: Supplied, sourceLocation: SourceLocation = #_sourceLocation) {
    for p in places {
        #expect(supplied.coordinates.contains(p.coordinate.value), "\(p.name) is at a coordinate no provider supplied", sourceLocation: sourceLocation)
    }
}
