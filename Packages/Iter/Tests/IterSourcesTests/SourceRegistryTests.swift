import Foundation
import Testing
import IterModel
@testable import IterSources

private struct D: SourceDescribing { let descriptor: SourceDescriptor }

@Suite("SourceRegistry")
struct SourceRegistryTests {
    static let W = Coordinate(latitude: 36.5785, longitude: -118.2923)
    static let S = Coordinate(latitude: 46.5586, longitude: 8.5610)
    static let O = Coordinate(latitude: 0, longitude: -160)

    static func registry(_ settings: SourceSettings = SourceSettings()) -> SourceRegistry {
        SourceRegistry(sources: SourceCatalogue.all.map { D(descriptor: $0) }, settings: settings)
    }

    func ids(_ r: SourceRegistry, _ kind: DataKind, _ p: Coordinate) -> [String] {
        r.descriptors(kind: kind, at: p).map(\.id.rawValue)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        var kind: DataKind
        var w: [String]
        var s: [String]
        var o: [String]
        var testDescription: String { kind.rawValue }
    }

    static let cases: [Case] = [
        Case(kind: .forecast, w: ["noaa.nomads", "metno.locationforecast"], s: ["noaa.nomads", "metno.locationforecast"],
             o: ["noaa.nomads", "metno.locationforecast"]),
        Case(kind: .observation, w: ["noaa.awc.metar", "noaa.nws.api"], s: ["noaa.awc.metar"], o: ["noaa.awc.metar"]),
        Case(kind: .alerts, w: ["noaa.nws.api"], s: [], o: []),
        Case(kind: .elevation, w: ["usgs.epqs", "aws.terrain-tiles"], s: ["aws.terrain-tiles"], o: ["aws.terrain-tiles"]),
        Case(kind: .horizon, w: ["aws.terrain-tiles"], s: ["aws.terrain-tiles"], o: ["aws.terrain-tiles"]),
        Case(kind: .smoke, w: ["noaa.nomads.hrrr-smoke", "noaa.nesdis.hms"], s: [], o: []),
        Case(kind: .aerosol, w: ["noaa.nomads.hrrr-smoke"], s: [], o: []),
        Case(kind: .imagery, w: ["nasa.gibs", "apple.lookaround"], s: ["nasa.gibs", "apple.lookaround"],
             o: ["nasa.gibs", "apple.lookaround"]),
        Case(kind: .satelliteCloud, w: ["nasa.gibs"], s: ["nasa.gibs"], o: ["nasa.gibs"]),
        Case(kind: .gazetteer, w: ["usgs.gnis", "apple.mapkit.poi", "osm.overpass"], s: ["apple.mapkit.poi", "osm.overpass"],
             o: ["apple.mapkit.poi", "osm.overpass"]),
        Case(kind: .aurora, w: ["noaa.swpc"], s: ["noaa.swpc"], o: ["noaa.swpc"]),
        Case(kind: .lightPollution, w: ["iter.none.sky-brightness"], s: ["iter.none.sky-brightness"],
             o: ["iter.none.sky-brightness"]),
        Case(kind: .magnetic, w: ["nga.wmm2025"], s: ["nga.wmm2025"], o: ["nga.wmm2025"]),
    ]

    @Test(arguments: cases) func catalogueSelection(_ c: Case) {
        let r = Self.registry()
        #expect(ids(r, c.kind, Self.W) == c.w)
        #expect(ids(r, c.kind, Self.S) == c.s)
        #expect(ids(r, c.kind, Self.O) == c.o)
    }

    @Test func gapsExplainEmptyResults() {
        let r = Self.registry()
        #expect(r.gaps(kind: .alerts, at: Self.S).contains(.outsideCoverage))
        #expect(r.gaps(kind: .smoke, at: Self.O).contains(.outsideCoverage))
        #expect(r.gaps(kind: .alerts, at: Self.W) == [])
        #expect(Self.registry(SourceSettings()).gaps(kind: .airQuality, at: Self.W) == [.notProvidedBySource])
        // Disabled sources are not gaps.
        let off = Self.registry(SourceSettings(disabled: ["noaa.nws.api"]))
        #expect(off.gaps(kind: .alerts, at: Self.S) == [])
    }

    @Test func disabledSourceIsDropped() {
        let r = Self.registry(SourceSettings(disabled: ["noaa.nomads"]))
        #expect(ids(r, .forecast, Self.W) == ["metno.locationforecast"])
        // Disabled wins over an override.
        let both = Self.registry(SourceSettings(disabled: ["eumetsat.view"], enabledOverrides: ["eumetsat.view"]))
        #expect(!ids(both, .imagery, Self.S).contains("eumetsat.view"))
    }

    @Test func offByDefaultSourcesNeedAnOverride() {
        #expect(!ids(Self.registry(), .imagery, Self.S).contains("eumetsat.view"))
        let on = Self.registry(SourceSettings(enabledOverrides: ["eumetsat.view"]))
        #expect(ids(on, .imagery, Self.S) == ["nasa.gibs", "eumetsat.view", "apple.lookaround"])
        #expect(ids(on, .satelliteCloud, Self.S) == ["nasa.gibs", "eumetsat.view"])
        // Meteosat's disc does not reach the central Pacific.
        #expect(!ids(on, .imagery, Self.O).contains("eumetsat.view"))
    }

    @Test func iemNeedsOverrideAndUS() {
        #expect(!ids(Self.registry(), .imagery, Self.W).contains("iem.nexrad"))
        #expect(!ids(Self.registry(), .imagery, Self.O).contains("iem.nexrad"))
        let on = Self.registry(SourceSettings(enabledOverrides: ["iem.nexrad"]))
        #expect(ids(on, .imagery, Self.W) == ["nasa.gibs", "iem.nexrad", "apple.lookaround"])
        #expect(!ids(on, .imagery, Self.S).contains("iem.nexrad"))
    }

    @Test func requiredKeySourceNeedsItsKey() {
        let keyed = SourceDescriptor(
            id: "test.keyed", name: "Keyed", operatorName: "t", tier: .userKey, origin: SourceOrigin(tier: .userKey, producer: "t"),
            kinds: [.forecast], coverage: .global, key: .required("test.keyed"), cacheTTL: .seconds(60),
            licence: LicenceTag(key: LicenceKey.none, mayStore: true), ranks: [.forecast: 1])
        let optional = SourceDescriptor(
            id: "test.optional", name: "Optional", operatorName: "t", tier: .userKey,
            origin: SourceOrigin(tier: .userKey, producer: "t"), kinds: [.forecast], coverage: .global,
            key: .optional("test.optional"), cacheTTL: .seconds(60), licence: LicenceTag(key: LicenceKey.none, mayStore: true))
        let sources: [any SourceDescribing] = [D(descriptor: keyed), D(descriptor: optional), D(descriptor: SourceCatalogue.noaaNOMADS)]
        let without = SourceRegistry(sources: sources, settings: SourceSettings(hasKey: { _ in false }))
        #expect(without.descriptors(kind: .forecast, at: Self.W).map(\.id.rawValue) == ["noaa.nomads", "test.optional"])
        #expect(without.gaps(kind: .forecast, at: Self.W) == [.needsKey("test.keyed")])
        let with = SourceRegistry(sources: sources, settings: SourceSettings(hasKey: { $0 == "test.keyed" }))
        #expect(with.descriptors(kind: .forecast, at: Self.W).map(\.id.rawValue) == ["noaa.nomads", "test.keyed", "test.optional"])
        #expect(with.gaps(kind: .forecast, at: Self.W) == [])
    }

    @Test func sortsByTierThenRankThenId() {
        func d(_ id: String, _ tier: SourceTier, _ rank: Int?) -> SourceDescriptor {
            SourceDescriptor(id: SourceID(id), name: id, operatorName: "t", tier: tier, origin: SourceOrigin(tier: tier, producer: "t"),
                             kinds: [.forecast], coverage: .global, cacheTTL: .seconds(60),
                             licence: LicenceTag(key: LicenceKey.none, mayStore: true), ranks: rank.map { [.forecast: $0] } ?? [:])
        }
        let list = [d("z", .device, 1), d("b", .government, 5), d("a", .government, 5), d("c", .government, nil),
                    d("m", .military, 99), d("o", .openData, 1), d("k", .userKey, 1)]
        let out = SourceRegistry.rank(list, kind: .forecast, at: Self.W, settings: SourceSettings())
        #expect(out.map(\.id.rawValue) == ["m", "a", "b", "c", "o", "k", "z"])
    }

    @Test func typedProvidersFilterByProtocol() {
        struct Fc: SourceDescribing, ForecastProvider {
            let descriptor: SourceDescriptor
            func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> { throw SourceError.noSource }
        }
        let r = SourceRegistry(sources: [Fc(descriptor: SourceCatalogue.metNorway), D(descriptor: SourceCatalogue.noaaNOMADS)])
        let typed = r.providers((any ForecastProvider).self, kind: .forecast, at: Self.W)
        #expect(typed.map { $0.descriptor.id.rawValue } == ["metno.locationforecast"])
        #expect(r.candidates(kind: .forecast, at: Self.W).count == 2)
    }

    // MARK: Catalogue sanity

    @Test func catalogueIsSane() {
        let all = SourceCatalogue.all
        #expect(Set(all.map(\.id)).count == all.count)
        for d in all {
            #expect(d.timeout > .zero, "\(d.id) timeout")
            #expect(d.policy.maxConcurrent >= 1)
            #expect(d.cacheTTL > .zero, "\(d.id) ttl")
            #expect(!d.kinds.isEmpty)
        }
        #expect(SourceCatalogue.osmOverpass.timeout == .seconds(60))
        #expect(SourceCatalogue.osmOverpass.timeout > .seconds(25))
    }

    @Test func onlyAppleEumetsatAndIEMAreMemoryOnly() {
        let memoryOnly = SourceCatalogue.all.filter { !$0.licence.mayStore }
        let allowed: Set<String> = [LicenceKey.apple, LicenceKey.eumetsat, LicenceKey.iem]
        #expect(!memoryOnly.isEmpty)
        for d in memoryOnly { #expect(allowed.contains(d.licence.key), "\(d.id) is memory-only") }
        // And each of the three kinds of source is in fact memory-only.
        #expect(Set(memoryOnly.map(\.licence.key)) == allowed)
    }
}

@Suite("Attribution")
struct AttributionTests {
    static let keys = [
        LicenceKey.noaaNCEP, LicenceKey.noaaNWS, LicenceKey.noaaAWC, LicenceKey.noaaSWPC, LicenceKey.noaaHMS, LicenceKey.usgs,
        LicenceKey.metNorway, LicenceKey.osm, LicenceKey.wikipedia, LicenceKey.commons, LicenceKey.terrainTiles,
        LicenceKey.nasaGIBS, LicenceKey.eumetsat, LicenceKey.iem, LicenceKey.apple, LicenceKey.wmm, LicenceKey.mgrs, LicenceKey.none,
    ]

    @Test(arguments: keys) func everyLicenceKeyHasText(_ key: String) throws {
        let t = try #require(Attribution.text(for: key))
        #expect(t.key == key)
        #expect(!t.short.isEmpty)
        #expect(t.full.count >= t.short.count)
    }

    @Test func everyCatalogueLicenceHasText() {
        for d in SourceCatalogue.all { #expect(Attribution.text(for: d.licence.key) != nil, "\(d.id)") }
        #expect(Set(Attribution.allKeys) == Set(Self.keys))
    }

    @Test func wordingMatchesTheTerms() throws {
        #expect(Attribution.text(for: LicenceKey.noaaNCEP)?.short == "Data: NOAA/NCEP")
        #expect(Attribution.text(for: LicenceKey.noaaNCEP)?.full.contains("No endorsement by NOAA is implied.") == true)
        #expect(Attribution.text(for: LicenceKey.metNorway)?.short == "Data from MET Norway (CC BY 4.0)")
        #expect(Attribution.text(for: LicenceKey.osm)?.short == "\u{00A9} OpenStreetMap contributors (ODbL)")
        #expect(Attribution.text(for: LicenceKey.wikipedia)?.short == "Text from Wikipedia (CC BY-SA 4.0)")
        #expect(Attribution.text(for: LicenceKey.commons)?.short == "Photos from Wikimedia Commons; licence per photo")
        #expect(Attribution.text(for: LicenceKey.nasaGIBS)?.short == "Imagery: NASA GIBS / NOAA GOES / JMA Himawari")
        #expect(Attribution.text(for: LicenceKey.eumetsat)?.short == "Contains EUMETSAT data")
        #expect(Attribution.text(for: LicenceKey.iem)?.short == "Radar tiles: Iowa Environmental Mesonet (NEXRAD)")
        #expect(Attribution.text(for: LicenceKey.apple)?.short == "Apple Maps")
        #expect(Attribution.text(for: LicenceKey.wmm)?.short == "World Magnetic Model 2025, NGA and UK DGC (US Government work)")
        #expect(Attribution.text(for: LicenceKey.mgrs)?.short == "MGRS (NGA standard)")
        #expect(Attribution.text(for: LicenceKey.none)?.short == "No source")
        #expect(Attribution.text(for: "nope") == nil)
    }

    @Test func terrainCreditCarriesTheWholeTilezenList() throws {
        let full = try #require(Attribution.text(for: LicenceKey.terrainTiles)).full
        #expect(Attribution.terrainCredits.count == 11)
        for line in Attribution.terrainCredits { #expect(full.contains(line)) }
        #expect(full.contains("U.S. Geological Survey"))
    }
}
