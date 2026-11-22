import Foundation
import IterAI
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

@Suite("Extraction")
struct ExtractionTests {
    let plan = QueryPlan(areaText: "Yosemite", features: [.waterfall])

    @Test func literalNameRule() {
        let d = doc("Yosemite", "Bridalveil Fall drops 188 m. Hikers also visit Hidden Falls and Mount Starr King.")
        #expect(DiscoveryNames.occursLiterally("Bridalveil Falls", in: d.text) == false)   // "falls" is not "fall": names must be literal
        #expect(DiscoveryNames.occursLiterally("Bridalveil Fall", in: d.text))
        #expect(DiscoveryNames.occursLiterally("bridalveil fall", in: d.text))
        #expect(DiscoveryNames.occursLiterally("Hidden Falls (37.7, -119.6)", in: d.text))   // brackets are not part of the name
        #expect(DiscoveryNames.occursLiterally("Invented Cascade", in: d.text) == false)
        #expect(DiscoveryNames.occursLiterally("Hidden Starr", in: d.text) == false)   // words must be adjacent
    }

    @Test func filterDropsInventedNamesAndKeepsTheDocumentCitation() {
        let d = doc("Waterfalls of Yosemite", "Bridalveil Fall is the first. Vernal Fall follows.")
        let raw: [(name: String, document: EvidenceDocument, hint: FeatureKind?)] = [
            ("Bridalveil Fall", d, .waterfall), ("Phantom Falls", d, .waterfall), ("Vernal Fall", d, nil), ("Vernal Fall", d, nil),
            ("Bridalveil Fall (37.7, -119.6)", d, nil), ("Mount Lyell", d, .peak),
        ]
        let out = ExtractionFilter.accept(raw, plan: plan)
        #expect(out.map(\.name) == ["Bridalveil Fall", "Vernal Fall"])
        #expect(out.allSatisfy { $0.citation == d.citation && $0.source == .wikipedia })
        #expect(out[0].snippet?.contains("Bridalveil") == true)
    }

    @Test func deterministicExtractorFindsFeatureLikePhrases() {
        let d = doc("Lone Pine area", "Visit Mobius Arch at sunrise. From Dante's View you see Badwater. Lake Sabrina and Mount Whitney are near. Bad Bridge Overlook is closed.")
        let all = DeterministicExtractor.extract(from: [d], plan: QueryPlan())
        let names = Set(all.map(\.name))
        #expect(names.contains("Mobius Arch"))
        #expect(names.contains("Lake Sabrina"))
        #expect(names.contains("Mount Whitney"))
        #expect(names.contains("Bad Bridge Overlook"))
        #expect(!names.contains { $0.hasPrefix("Visit") })
        // Filtered to the plan's feature kinds.
        let arches = DeterministicExtractor.extract(from: [d], plan: QueryPlan(features: [.arch]))
        #expect(arches.map(\.name) == ["Mobius Arch"])
        #expect(arches[0].featureHint == .arch)
    }

    @Test func documentsAboutAPlaceBecomeStructuredCandidatesOnlyWhenGeotaggedAndTitledLikeOne() {
        let c = Coordinate(latitude: 37.71, longitude: -119.65)
        let docs = [doc("Bridalveil Fall", "A waterfall.", at: c), doc("Yosemite Valley", "A valley.", at: c), doc("Vernal Fall", "No tag."), doc("Yosemite", "Park", at: c)]
        let out = DocumentCandidates.candidates(from: docs, plan: plan, areaName: "Yosemite")
        #expect(out.map(\.name) == ["Bridalveil Fall"])
        #expect(out[0].coordinate == c && out[0].source == .wikipedia)
    }

    @Test func chunksFitTheContextAndPrioritiseRelevantDocuments() {
        var docs: [EvidenceDocument] = (0..<30).map { doc("Article \($0)", String(repeating: "word ", count: 400)) }
        docs.append(doc("Waterfall guide", "Bridalveil Fall and others."))
        let chunks = EvidenceChunker.chunks(docs, plan: plan)
        #expect(chunks.allSatisfy { $0.documents.count <= EvidenceChunker.maxDocumentsPerChunk })
        #expect(chunks.allSatisfy { $0.prompt.count <= EvidenceChunker.maxCharactersPerChunk + 400 })
        #expect(chunks.first?.documents.first?.title == "Waterfall guide")
        #expect(chunks.flatMap(\.documents).count == docs.count)
        #expect(EvidenceChunker.capped(String(repeating: "x", count: 5000)).count == EvidenceChunker.maxCharactersPerDocument)
    }

    @Test func modelExtractionIsFilteredByTheLiteralRuleAndFallsBackPerChunk() async {
        let d0 = doc("Yosemite falls", "Bridalveil Fall is famous. Hidden Falls is quiet.")
        let d1 = doc("Other", "Nothing here but Vernal Fall.")
        let model = FakeModel()
        model.set {
            $0.json["ExtractionDTO"] = """
            {"places":[{"name":"Bridalveil Fall","documentIndex":0,"featureHint":"waterfall"},
                       {"name":"Invented Falls (37.7, -119.6)","documentIndex":0},
                       {"name":"Vernal Fall","documentIndex":0},
                       {"name":"Vernal Fall","documentIndex":1,"featureHint":"waterfall"},
                       {"name":"Hidden Falls","documentIndex":7}]}
            """
        }
        let chunks = EvidenceChunker.chunks([d0, d1], plan: plan)
        let names = await ModelExtractor(model: model, timeout: .seconds(1)).extract(chunks: chunks, plan: plan)
        #expect(Set(names.map(\.name)) == ["Bridalveil Fall", "Vernal Fall"])
        // "Vernal Fall" is attributed to the document that contains it.
        #expect(names.first { $0.name == "Vernal Fall" }?.citation == d1.citation)

        model.set { $0.generateError = .generation("down") }
        let fallback = await ModelExtractor(model: model, timeout: .seconds(1)).extract(chunks: chunks, plan: plan)
        #expect(Set(fallback.map(\.name)).isSuperset(of: ["Bridalveil Fall", "Hidden Falls", "Vernal Fall"]))
    }
}
