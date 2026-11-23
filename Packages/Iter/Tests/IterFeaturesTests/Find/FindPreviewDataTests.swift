import Foundation
import Testing
import IterModel
import IterDiscovery
@testable import IterFeatures

@MainActor
@Suite("Find preview data")
struct FindPreviewDataTests {
    @Test func emptyHasNothing() async throws {
        let m = try await FindPreviewData.model(.empty)
        #expect(m.phase == .idle && m.rows.isEmpty && m.chips.isEmpty)
    }

    @Test func searchingShowsOneSlowSourceAndPartialPlaces() async throws {
        let m = try await FindPreviewData.model(.searching)
        #expect(m.phase == .discovering && m.progress.isRunning)
        #expect(m.chips.first { $0.sourceID == FindFixtures.osm }?.state == .slow)
        #expect(m.chips.first { $0.role == .placeSearch }?.state == .searching)
        #expect(m.rows.count == 2 && m.progress.elapsed == 7)
        #expect(m.chips.contains { $0.state == .unavailable })
    }

    @Test func resultsHaveCitationsPhotoConfirmedAndSingleSource() async throws {
        let m = try await FindPreviewData.model(.results)
        #expect(m.phase == .finished && !m.isBasicSearch && m.planLabel == nil)
        #expect(m.rows.contains { $0.verification == .confirmed } && m.rows.contains { $0.verification == .singleSource })
        #expect(m.rows.first { $0.photo != nil }?.photo?.licenceName == "CC BY-SA 4.0")
        #expect(m.rows.first?.whyIsModelWritten == true)
        #expect(m.rows.allSatisfy { $0.drive?.basis == .drive })
        #expect(m.chips.first { $0.role == .ai }?.state == .found(1))
    }

    @Test func pendingDriveTimesSayStraightLine() async throws {
        let m = try await FindPreviewData.model(.driveTimesPending)
        #expect(m.rows.allSatisfy { $0.drive?.basis == .straightLine })
    }

    @Test func basicSearchNamesTheReason() async throws {
        let m = try await FindPreviewData.model(.basicSearch)
        #expect(m.planLabel == "Basic search: AI unavailable (Apple Intelligence is turned off)")
        #expect(m.isBasicSearch && !m.rows.isEmpty)
    }

    @Test func aDownSourceShowsAsDownAndTheRestStillAnswer() async throws {
        let m = try await FindPreviewData.model(.sourceDown)
        #expect(m.chips.first { $0.sourceID == FindFixtures.osm }?.state == .down)
        #expect(!m.rows.isEmpty)
    }
}
