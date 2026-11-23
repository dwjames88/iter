import Foundation
import SwiftUI
import Testing
import IterFeatures
import IterModel
import IterSources
import IterDiscovery
@testable import IterScreens

/// Row equality and the ordering of what the card shows, the Search Here rule, source words and the cluster zoom.
@MainActor @Suite struct FindLogicTests {
    /// A real row from the preview model, with the fields this suite cares about set (the row's initialiser is the model's).
    static func row(_ id: String = "a", name: String = "Mesa Arch", drive: DriveTime? = nil, saved: Bool = false) async throws -> FindRow {
        var row = try #require(try await FindPreviewData.model(.results).rows.first)
        row.id = id
        row.name = name
        row.kindsText = "Arch, Viewpoint"
        row.verification = .confirmed
        row.distanceKm = 23
        row.distanceBasis = .fromYou
        row.drive = drive
        row.isSaved = saved
        row.sourceNames = ["OpenStreetMap"]
        row.photo = nil
        row.score = nil
        return row
    }

    // MARK: Rows

    @Test func aScoreChangesTheRowAndIsSpokenWithoutInventingANumber() async throws {
        let base = FindRowView(row: try await Self.row(), locality: "Canyonlands")
        var scored = try await Self.row()
        scored.score = FindScore(kind: .goldenEvening, start: Date(timeIntervalSince1970: 1_791_850_000), value: 72, confidence: .high,
                                 isLoading: false, zoneIdentifier: "America/Denver")
        #expect(base != FindRowView(row: scored, locality: "Canyonlands"))
        #expect(FindText.rowAccessibility(scored, locality: "Canyonlands").contains("score 72"))
        scored.score?.value = nil
        scored.score?.isLoading = true
        let words = FindText.rowAccessibility(scored, locality: "Canyonlands")
        #expect(words.contains("not available yet") && !words.contains("score 7"))
    }

    @Test func equalRowsAreEqualViews() async throws {
        let a = FindRowView(row: try await Self.row(), locality: "Canyonlands")
        let b = FindRowView(row: try await Self.row(), locality: "Canyonlands")
        #expect(a == b)
    }

    @Test func aDriveTimeOrASaveOrAnotherLocalityChangesTheRow() async throws {
        let base = FindRowView(row: try await Self.row(), locality: "Canyonlands")
        #expect(base != FindRowView(row: try await Self.row(drive: DriveTime(basis: .drive, minutes: 25)), locality: "Canyonlands"))
        #expect(base != FindRowView(row: try await Self.row(saved: true), locality: "Canyonlands"))
        #expect(base != FindRowView(row: try await Self.row(), locality: "Moab"))
    }

    @Test func rowWordsLabelDriveAndStraightLine() async throws {
        #expect(FindText.distanceLine(distanceText: "23 km from you", drive: DriveTime(basis: .drive, minutes: 25)) == "23 km from you · 25 min drive")
        #expect(FindText.distanceLine(distanceText: "23 km from you", drive: DriveTime(basis: .straightLine, minutes: 25)) == "23 km from you · ~25 min straight-line")
        #expect(FindText.distanceLine(distanceText: nil, drive: nil) == nil)
        #expect(FindText.verificationShort(.confirmed) == "Confirmed")
        #expect(FindText.verificationShort(.singleSource) == "Single source")
        let words = FindText.rowAccessibility(try await Self.row(), locality: "Canyonlands")
        #expect(words == "Mesa Arch, Canyonlands, Arch, Viewpoint, 23 km from you, Confirmed")
    }

    // MARK: Progress and sources

    @Test func progressLine() {
        let running = FindProgress(done: 3, total: 7, elapsed: 4.2, isRunning: true)
        #expect(FindText.progressLine(running, phase: .discovering) == "3 of 7 sources done · 4 s")
        #expect(FindText.progressLine(FindProgress(done: 7, total: 7, elapsed: 65, isRunning: false), phase: .finished) == "7 sources searched · 1 min 5 s")
        #expect(FindText.progressLine(FindProgress(done: 3, total: 7, elapsed: 4, isRunning: false), phase: .cancelled) == "Stopped · 3 of 7 sources answered · 4 s")
        #expect(FindText.progressLine(FindProgress(isRunning: true), phase: .discovering) == "Planning the search · 0 s")
    }

    @Test func sourceStatesReadPlainly() {
        func chip(_ state: SourceChipState, reason: String? = nil, role: SourceRole = .gazetteer) -> SourceChip {
            SourceChip(id: "x", sourceID: "x", name: "OpenStreetMap", role: role, state: state, text: "", reason: reason)
        }
        #expect(FindText.sourceDisplay(chip(.found(14))).detail == "14 places")
        #expect(FindText.sourceDisplay(chip(.found(1))).detail == "1 place")
        #expect(FindText.sourceDisplay(chip(.slow)).tone == .warning)
        #expect(FindText.sourceDisplay(chip(.down, reason: "HTTP 504")).detail == "Down: HTTP 504")
        #expect(FindText.sourceDisplay(chip(.unavailable, reason: "needs your own key")).detail == "Unavailable: needs your own key")
        #expect(FindText.sourceDisplay(chip(.skipped, reason: "off in Settings")).detail == "Skipped: off in Settings")
        #expect(FindText.sourceDisplay(chip(.searching)).isWorking)
        #expect(FindText.sourceTrouble([chip(.slow), chip(.down), chip(.found(2))]) == "1 slow, 1 down")
        #expect(FindText.sourceTrouble([chip(.found(2))]) == nil)
    }

    @Test func theSourceListNamesRedditAndGoogleAsUnavailable() async throws {
        let model = try await FindPreviewData.model(.results)
        let shown = model.chips.map(FindText.sourceDisplay)
        for name in ["Reddit", "Google"] {
            let one = try #require(shown.first { $0.name == name })
            #expect(one.detail.hasPrefix("Unavailable"))
        }
    }

    @Test func planLineIsHonest() {
        #expect(FindText.planLine(label: "Basic search: AI unavailable (Apple Intelligence is turned off)", isBasic: true)
                == "Basic search: AI unavailable (Apple Intelligence is turned off)")
        #expect(FindText.planLine(label: nil, isBasic: true) == "Basic search: AI unavailable")
        #expect(FindText.planLine(label: nil, isBasic: false) == nil)
    }

    // MARK: What the card shows

    @Test func cardModeOrder() {
        func mode(card: Bool = false, _ phase: FindPhase, chips: Bool = false, rows: Bool = false, matches: Bool = false, text: Bool = false) -> FindCardMode {
            FindCardMode.resolve(hasCard: card, phase: phase, hasChips: chips, hasRows: rows, hasMatches: matches, hasText: text)
        }
        #expect(mode(.idle) == .hidden)
        #expect(mode(.idle, text: true) == .suggestions)
        #expect(mode(.discovering) == .results)
        #expect(mode(.finished, chips: true, rows: true) == .results)
        #expect(mode(.cancelled, chips: true) == .results)
        #expect(mode(.failed("no"), text: true) == .results)
        #expect(mode(.lookingUp) == .lookup)
        #expect(mode(.finished, matches: true, text: true) == .lookup)
        #expect(mode(.finished, text: true) == .lookup)
        // An open card wins over everything.
        #expect(mode(card: true, .discovering, chips: true, rows: true) == .place)
        #expect(mode(card: true, .idle) == .place)
    }

    @Test func modeFollowsTheModel() async throws {
        #expect(FindCardMode.of(try await FindPreviewData.model(.empty)) == .hidden)
        #expect(FindCardMode.of(try await FindPreviewData.model(.results)) == .results)
        let m = try await FindPreviewData.model(.results)
        m.select(try #require(m.rows.first?.id))
        #expect(FindCardMode.of(m) == .place)
        m.deselect()
        #expect(FindCardMode.of(m) == .results)
    }

    // MARK: Search Here

    static func region(_ lat: Double, _ lon: Double, _ span: Double) -> GeoRegion {
        GeoRegion(center: Coordinate(latitude: lat, longitude: lon), latitudeDelta: span, longitudeDelta: span)
    }

    @Test func searchHereShowsOnlyWhenTheMapNoLongerMatchesTheList() {
        let searched = Self.region(38.4, -109.8, 0.4)
        #expect(!FindSearchHereRule.isStale(searched: searched, visible: nil))
        #expect(FindSearchHereRule.isStale(searched: nil, visible: searched))
        #expect(!FindSearchHereRule.isStale(searched: searched, visible: Self.region(38.42, -109.82, 0.4)))
        #expect(FindSearchHereRule.isStale(searched: searched, visible: Self.region(38.7, -109.8, 0.4)))
        #expect(FindSearchHereRule.isStale(searched: searched, visible: Self.region(38.4, -109.8, 1.2)))
        #expect(FindSearchHereRule.isStale(searched: searched, visible: Self.region(38.4, -109.8, 0.1)))
        #expect(!FindSearchHereRule.shows(phase: .discovering, searched: nil, visible: searched))
        #expect(!FindSearchHereRule.shows(phase: .lookingUp, searched: nil, visible: searched))
        #expect(FindSearchHereRule.shows(phase: .idle, searched: nil, visible: searched))
    }

    // MARK: Clusters and map

    @Test func clusterZoomFitsItsMembers() async throws {
        var near = try await Self.row("a")
        near.coordinate = Coordinate(latitude: 38.40, longitude: -109.80)
        var far = near
        far.id = "b"
        far.coordinate = Coordinate(latitude: 38.50, longitude: -109.70)
        // A real cluster from the clusterer, at a zoom where both fall in one cell.
        let wide = Self.region(38.45, -109.75, 8)
        let grouped = FindPinClusterer.cluster([("a", near.coordinate), ("b", far.coordinate)], region: wide, viewportWidth: 400)
        let cluster = try #require(grouped.clusters.first)
        let region = try #require(FindClusterZoom.region(for: cluster, rows: [near, far]))
        #expect(region.latitudeDelta > 0.1)
        #expect(FindMapGeometry.contains(region, near.coordinate, margin: 0))
        #expect(FindMapGeometry.contains(region, far.coordinate, margin: 0))
    }

    @Test func boxHasFourCorners() {
        let box = FindMapGeometry.box(Self.region(10, 20, 2))
        #expect(box.count == 4)
        #expect(Set(box.map(\.latitude)) == [11, 9])
        #expect(Set(box.map(\.longitude)) == [19, 21])
    }

    @Test func cardWidthNarrowsBeforeTheMapDoes() {
        let ideal: CGFloat = 360
        #expect(FindCardLayout<SwiftUI.EmptyView, SwiftUI.EmptyView>.width(ideal: ideal, detailWidth: 0) == ideal)
        #expect(FindCardLayout<SwiftUI.EmptyView, SwiftUI.EmptyView>.width(ideal: ideal, detailWidth: 2000) == ideal)
        #expect(FindCardLayout<SwiftUI.EmptyView, SwiftUI.EmptyView>.width(ideal: ideal, detailWidth: 700) < ideal)
    }

    // MARK: Place card words

    @Test func shareLinkCarriesTheExactCoordinate() {
        let url = FindCardText.shareURL(name: "Mesa Arch", coordinate: Coordinate(latitude: 38.3884, longitude: -109.868))
        #expect(url.absoluteString == "https://maps.apple.com?ll=38.388400,-109.868000&q=Mesa%20Arch")
    }

    @Test func placeIDsComeFromCardIDs() {
        let id = UUID()
        #expect(FindCardText.placeID(from: "place:\(id.uuidString)") == id)
        #expect(FindCardText.placeID(from: "maps:1") == nil)
    }

    @Test func aCitationKeepsItsRetrievedDate() async throws {
        let model = try await FindPreviewData.model(.results)
        model.select(try #require(model.rows.first?.id))
        let card = try #require(model.card)
        let first = try #require(card.citations.first)
        let date = FindCardText.retrievedAt(first, in: card.place)
        #expect(date == FindFixtures.retrievedAt)
        let line = FindCardText.citationDetail(first, retrieved: date, locale: Locale(identifier: "en_US"))
        #expect(line.contains("Retrieved Oct 12, 2026"))
    }

    @Test func coordinateLinesAndSources() async throws {
        #expect(FindText.coordinateLine(Coordinate(latitude: 38.3884, longitude: -109.868)) == "38.3884°N 109.8680°W")
        let model = try await FindPreviewData.model(.empty)
        let r = model.spots.readout(for: FindFixtures.mesaArch)
        let lines = FindText.readoutSources(r)
        #expect(r.mgrs != nil && r.declinationText != nil)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("MGRS: "))
        #expect(lines[1].hasPrefix("Declination: "))
        #expect(lines.joined().contains("Military-origin"))
    }
}
