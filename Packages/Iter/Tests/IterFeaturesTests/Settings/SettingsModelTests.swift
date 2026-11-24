import Foundation
import Testing
import IterModel
import IterSources
import IterDiscovery
@testable import IterFeatures

@MainActor
@Suite("Settings model") struct SettingsModelTests {
    private func live() throws -> (AppContainer, SettingsModel) {
        let c = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: "com.dwjames.iter.render", environment: [:])
        return (c, c.settingsModel())
    }

    @Test func generalAndSearchSettingsWriteThroughToPreferences() throws {
        let (c, s) = try live()
        s.mapStyle = "imagery"; s.showDaylight = false
        s.preferenceText = "waterfalls and dark skies"; s.ordering = .unique; s.resultCap = 25
        #expect(c.preferences.mapStyle == "imagery" && !c.preferences.showDaylight)
        #expect(c.preferences.preferenceText == "waterfalls and dark skies" && c.preferences.ordering == .unique && c.preferences.resultCap == 25)
        s.resultCap = 5000
        #expect(s.resultCap == SettingsModel.resultCapRange.upperBound)
        #expect(s.keysSummary.contains("No source Iter uses needs a key"))
        #expect(s.keyRows.isEmpty)
    }

    @Test func redditAndGoogleShowAsUnavailableWithTheirReasons() throws {
        let (_, s) = try live()
        let reddit = try #require(s.discoverySources.first { $0.id == FixedSources.reddit })
        let google = try #require(s.discoverySources.first { $0.id == FixedSources.google })
        #expect(reddit.status == .unavailable(FixedSources.redditReason) && !reddit.isToggleable)
        #expect(google.status == .unavailable(FixedSources.googleReason) && !google.isToggleable)
        #expect(s.rows.last?.id == FixedSources.google)
        // Every real discovery source is there too, and only discovery ones.
        let ids = Set(s.discoverySources.map(\.id))
        #expect(ids.isSuperset(of: [.osmOverpass, .usgsGNIS, .wikipedia, .wikivoyage, .wikimediaCommons, .appleSearch, .applePOI, .appleGeocoder]))
        #expect(!ids.contains(.noaaNOMADS))
    }

    @Test func militaryOriginIsLabelledHonestly() throws {
        let (_, s) = try live()
        let metar = try #require(s.rows.first { $0.id == .aviationWeather })
        #expect(metar.isMilitaryOrigin && metar.tier == .military)
        #expect(metar.originLabel.hasPrefix("Military-origin via NOAA Aviation Weather Center"))
        #expect(metar.originLabel.contains("military airfields"))   // not every station is military
        #expect(metar.kinds == ["Observations"] && metar.coverage == "Worldwide")
        let wmm = try #require(s.rows.first { $0.id == .worldMagneticModel })
        #expect(wmm.originLabel.contains("Military-origin") && wmm.originLabel.contains("computed on this device"))
        let mgrs = try #require(s.rows.first { $0.id == .mgrs })
        #expect(mgrs.originLabel == "Military-origin standard (NGA), computed on this device")
        let nomads = try #require(s.rows.first { $0.id == .noaaNOMADS })
        #expect(!nomads.isMilitaryOrigin && nomads.originLabel.hasPrefix("Government"))
        // Military sources group first.
        #expect(s.rowsByTier.first?.tier == .military)
        #expect(s.rowsByTier.first?.rows.map(\.id).contains(.aviationWeather) == true)
    }

    @Test func everyRowCarriesItsAttribution() throws {
        let (c, s) = try live()
        for row in s.rows where !SettingsModel.unavailableIDs.contains(row.id) {
            #expect(!row.attributionFull.isEmpty, "\(row.name)")
            #expect(!row.attributionFull.hasPrefix("No attribution text"), "\(row.name) has no registered attribution")
        }
        #expect(s.rows.count == c.sources.count + 2)
        let terrain = try #require(s.rows.first { $0.id == .terrariumTiles })
        #expect(terrain.attributionFull.contains("ArcticDEM"))   // the full Tilezen list
        #expect(s.namedGaps.map(\.title) == ["Light Pollution", "Seeing and Transparency"])
    }

    @Test func togglingASourceUpdatesTheRowAndThePreferences() throws {
        let (c, s) = try live()
        #expect(s.rows.first { $0.id == .osmOverpass }?.status == .enabled)
        #expect(s.rows.first { $0.id == .osmOverpass }?.toggleTiming == .nextSearch)
        #expect(s.rows.first { $0.id == .noaaNOMADS }?.toggleTiming == .nextLaunch)
        s.setSource(.osmOverpass, enabled: false)
        #expect(s.rows.first { $0.id == .osmOverpass }?.status == .disabled)
        #expect(c.preferences.disabledSources == [.osmOverpass])
        s.setSource(.osmOverpass, enabled: true)
        #expect(c.preferences.disabledSources.isEmpty)

        // Off by default until the owner turns it on.
        #expect(s.rows.first { $0.id == .eumetsatView }?.status == .offByDefault)
        s.setSource(.eumetsatView, enabled: true)
        #expect(s.rows.first { $0.id == .eumetsatView }?.status == .enabled)
        #expect(c.preferences.enabledOverrides == [.eumetsatView])
        s.setSource(.eumetsatView, enabled: false)
        #expect(s.rows.first { $0.id == .eumetsatView }?.status == .disabled)

        // On-device and routing sources are always used; unknown and unavailable ones do nothing.
        s.setSource(.mgrs, enabled: false)
        s.setSource(FixedSources.reddit, enabled: true)
        #expect(!c.preferences.disabledSources.contains(.mgrs) && !c.preferences.disabledSources.contains(FixedSources.reddit))
    }

    @Test func keysGoThroughTheVaultAndAreNeverShown() throws {
        let vault = KeyVault(keychain: InMemoryKeychain())
        let optional = SourceDescriptor(id: "demo.keyed", name: "Demo Keyed", operatorName: "Demo", tier: .userKey,
                                        origin: SourceOrigin(tier: .userKey, producer: "Demo"), kinds: [.forecast], coverage: .global,
                                        key: .optional("demo.keyed"), cacheTTL: .seconds(60), licence: LicenceTag(key: "iter.none", mayStore: true))
        let s = SettingsModel(preferences: .ephemeral(), keyVault: vault, sources: [optional])
        #expect(s.keyRows == [KeyRow(id: "demo.keyed", sourceName: "Demo Keyed", isRequired: false, hasKey: false)])
        try s.setKey("  abc123  ", for: "demo.keyed")
        #expect(s.keyRows.first?.hasKey == true)
        #expect(vault.key(for: "demo.keyed") == "abc123")
        #expect(!String(describing: s.keyRows).contains("abc123"))
        try s.removeKey(for: "demo.keyed")
        #expect(s.keyRows.first?.hasKey == false && vault.key(for: "demo.keyed") == nil)
    }

    @Test func aRequiredKeyThatIsMissingShowsAsNeedsKey() throws {
        let required = SourceDescriptor(id: "demo.req", name: "Demo Required", operatorName: "Demo", tier: .userKey,
                                        origin: SourceOrigin(tier: .userKey, producer: "Demo"), kinds: [.places], coverage: .global,
                                        key: .required("demo.req"), cacheTTL: .seconds(60), licence: LicenceTag(key: "iter.none", mayStore: true))
        let vault = KeyVault(keychain: InMemoryKeychain())
        let s = SettingsModel(preferences: .ephemeral(), keyVault: vault, sources: [required])
        #expect(s.rows.first { $0.id == "demo.req" }?.status == .needsKey)
        try s.setKey("k", for: "demo.req")
        #expect(s.rows.first { $0.id == "demo.req" }?.status == .enabled)
    }

    @Test func sampleModeSaysSampleData() throws {
        let c = try AppContainer.test()
        let s = c.settingsModel()
        let sample = try #require(s.rows.first { $0.id == SampleConditions.sourceID })
        #expect(sample.name == "Sample data" && sample.attributionShort == "Sample data")
        #expect(sample.attributionFull.contains("not real weather") && !sample.isToggleable)
        #expect(s.rows.contains { $0.id == SampleRouting.sourceID && $0.name.contains("estimate") })
        let routing = try #require(s.rows.first { $0.id == SampleRouting.sourceID })
        #expect(routing.attributionFull.hasPrefix("Sample routing:") && !routing.attributionFull.contains("weather"))
        let places = try #require(s.rows.first { $0.name == "Sample place lookup" })
        #expect(places.attributionFull.contains("built-in catalogue") && !places.attributionFull.contains("weather"))
    }
}

@MainActor
@Suite("Learn From My Library wiring") struct LearnFromLibraryWiringTests {
    private func live() throws -> AppContainer {
        let c = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: "com.dwjames.iter.render", environment: [:])
        SampleLibrary.seed(into: c.library, now: Date(timeIntervalSince1970: 1_800_000_000))
        return c
    }

    @Test func isOnByDefaultAsInTheOldAppAndWritesThrough() throws {
        let c = try live()
        #expect(c.preferences.learnFromLibrary)
        let s = c.settingsModel()
        #expect(s.learnFromLibrary)
        s.learnFromLibrary = false
        #expect(!c.preferences.learnFromLibrary)
    }

    @Test func theEngineGetsAProfileOnlyWhileTheToggleIsOn() throws {
        let c = try live()
        let profile = c.discovery.libraryProfile
        #expect(profile != nil && profile?.isEmpty == false)
        // Computed from the library alone: the same as building it directly.
        #expect(profile == LibraryProfile(savedPlaces: c.library.places.savedValues(), trips: c.library.trips.values()))
        c.preferences.learnFromLibrary = false
        #expect(c.discovery.libraryProfile == nil)
        c.preferences.learnFromLibrary = true
        #expect(c.discovery.libraryProfile != nil)
    }

    @Test func anEmptyLibraryLearnsNothing() throws {
        let c = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: "com.dwjames.iter.render", environment: [:])
        #expect(c.discovery.libraryProfile?.isEmpty == true)
    }
}
