import Foundation
import Testing
import IterModel
import IterConditions
import IterSky
@testable import IterFeatures

/// Each result's Sky Index comes lazily from the shared Conditions stage: rows in view first, a quick score kept until the
/// complete one replaces it, and no number when there is none.
@MainActor @Suite struct FindScoresTests {
    private func score(_ r: SkyReport = ConditionsFixtures.report(day: ConditionsFixtures.today), place: Place, morning: Int, evening: Int,
                       confidence: Confidence = .high) -> SkyReport {
        let base = ConditionsFixtures.report(day: LocalDay(FindFixtures.retrievedAt, in: place.timeZone), place: place)
        return ConditionsFixtures.report(base, scores: [.goldenMorning: morning, .goldenEvening: evening], confidence: confidence)
    }

    private func finished(_ fake: FakeFindScores, lead: Int = 3) async throws -> Rig {
        var config = Rig.fastFind
        config.scoreLeadCount = lead
        let rig = try Rig(configuration: config, scores: fake)
        await rig.search()
        return rig
    }

    @Test func rowsInViewAreAskedForFirstAtOnScreenAndOthersNotAtAll() async throws {
        let fake = FakeFindScores()
        let rig = try await finished(fake, lead: 3)
        #expect(rig.model.rows.count > 3)
        let top3 = rig.model.rows.prefix(3).map(\.id)
        let asked = Set(fake.requests.map(\.placeID))
        #expect(top3.allSatisfy { id in rig.model.scoreTargets[id].map { asked.contains($0.place.id) } == true })
        #expect(fake.requests.allSatisfy { $0.priority == .onScreen })
        #expect(fake.visibleSets.last?.count == 3)
        #expect(rig.model.rows.suffix(from: 3).allSatisfy { rig.model.scoreTargets[$0.id] == nil })
        // Scrolling brings others into view: only the new ones are asked for, nothing twice.
        let before = fake.requests.count
        rig.model.setVisibleResults(Set(rig.model.rows.prefix(5).map(\.id)))
        #expect(fake.requests.count == before + 2)
    }

    @Test func aRowShowsLoadingThenItsScoreAndNeverAFakeNumber() async throws {
        let fake = FakeFindScores()
        let rig = try await finished(fake)
        let first = try #require(rig.model.rows.first)
        let loading = try #require(first.score)
        #expect(loading.isLoading && loading.value == nil)
        let target = try #require(rig.model.scoreTargets[first.id])
        let place = target.place
        #expect(fake.requests.contains { $0.placeID == place.id })
        fake.set(.ready(score(place: place, morning: 80, evening: 64)), place: place.id, day: target.day)
        #expect(await waitUntil { rig.model.rows.first?.score?.value != nil })
        let shown = try #require(rig.model.rows.first?.score)
        #expect(!shown.isLoading && shown.value != nil)
        // Another row's slot is still loading: no number for it.
        let other = rig.model.rows[1]
        #expect(other.score?.value == nil)
    }

    @Test func aQuickScoreStaysUntilTheCompleteOneReplacesIt() async throws {
        let fake = FakeFindScores()
        let rig = try await finished(fake)
        let id = try #require(rig.model.rows.first?.id)
        let target = try #require(rig.model.scoreTargets[id])
        fake.set(.ready(score(place: target.place, morning: 50, evening: 50, confidence: .low)), place: target.place.id, day: target.day)
        #expect(await waitUntil { rig.model.rows.first?.score?.value != nil })
        let quick = try #require(rig.model.rows.first?.score)
        // A refresh starts: the last good report stays under .loading, and the row keeps its number.
        let previous = try #require(fake.state(for: target.place.id, day: target.day).report)
        fake.set(.loading(previous: previous), place: target.place.id, day: target.day)
        try await Task.sleep(for: .milliseconds(50))
        #expect(rig.model.rows.first?.score == quick)
        fake.set(.ready(score(place: target.place, morning: 88, evening: 90, confidence: .high)), place: target.place.id, day: target.day)
        #expect(await waitUntil { rig.model.rows.first?.score != quick })
        #expect(rig.model.rows.first?.score?.value != nil)
    }

    @Test func aPlaceWithNoScorableDayShowsNoNumberAndNoSpinner() async throws {
        let fake = FakeFindScores()
        let rig = try await finished(fake)
        let id = try #require(rig.model.rows.first?.id)
        let target = try #require(rig.model.scoreTargets[id])
        var r = score(place: target.place, morning: 50, evening: 50)
        r.daylight.windows = r.daylight.windows.map { var w = $0; w.assessment = .unavailable(.beyondHorizon); return w }
        fake.set(.ready(r), place: target.place.id, day: target.day)
        #expect(await waitUntil { rig.model.rows.first?.score?.isLoading == false })
        #expect(rig.model.rows.first?.score?.value == nil)
    }

    @Test func aNewSearchCancelsAndForgetsTheOldScores() async throws {
        let fake = FakeFindScores()
        let rig = try await finished(fake)
        let asked = Set(fake.requests.map(\.placeID))
        #expect(!asked.isEmpty)
        rig.model.clear()
        #expect(Set(fake.cancelled) == asked)
        #expect(rig.model.rows.isEmpty && rig.model.scoreTargets.isEmpty)
    }

    @Test func theSelectedPlaceGetsTheCardsOneScore() async throws {
        let fake = FakeFindScores()
        let rig = try await finished(fake, lead: 1)
        let last = try #require(rig.model.rows.last?.id)
        rig.model.select(last)
        #expect(fake.requests.contains { $0.placeID == rig.model.card?.place.id })
        let target = try #require(rig.model.scoreTargets[last])
        fake.set(.ready(score(place: target.place, morning: 70, evening: 40)), place: target.place.id, day: target.day)
        #expect(await waitUntil { rig.model.cardScore?.value != nil })
        rig.model.deselect()
        #expect(rig.model.cardScore == nil)
    }

    @Test func withNoScoreSourceRowsCarryNoScore() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(rig.model.rows.allSatisfy { $0.score == nil })
    }

    @Test func previewResultsAreScoredDeterministically() async throws {
        let a = try await FindPreviewData.model(.results)
        let b = try await FindPreviewData.model(.results)
        #expect(a.rows.compactMap { $0.score?.value } == b.rows.compactMap { $0.score?.value })
        #expect(a.rows.compactMap { $0.score?.value }.count == a.rows.count)
    }
}
