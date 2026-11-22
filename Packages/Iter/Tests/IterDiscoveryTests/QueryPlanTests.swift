import Foundation
import IterAI
import IterModel
import Testing
@testable import IterDiscovery

/// Walks an `AISchema` for anything that could carry a coordinate: property names or descriptions about latitude, longitude
/// or coordinates, and any floating-point-like number. (The AI worker's public `AISchema.mentionsCoordinates` is not
/// available to this branch, so this helper is private to the tests.)
func schemaMentionsCoordinates(_ schema: AISchema) -> Bool {
    let bad = ["lat", "lon", "lng", "latitude", "longitude", "coordinate", "coordinates", "coord", "location", "position", "gps"]
    func words(_ s: String) -> [String] {
        // split camelCase and separators into lower-case words
        var out: [String] = [], cur = ""
        for ch in s {
            if ch.isUppercase, !cur.isEmpty { out.append(cur.lowercased()); cur = "" }
            if ch.isLetter { cur.append(ch) } else if !cur.isEmpty { out.append(cur.lowercased()); cur = "" }
        }
        if !cur.isEmpty { out.append(cur.lowercased()) }
        return out
    }
    func hit(_ s: String?) -> Bool { s.map { words($0).contains(where: bad.contains) } ?? false }
    switch schema {
    case .string(let d, let choices): return hit(d) || (choices ?? []).contains { hit($0) }
    case .integer(let d, _): return hit(d)
    case .boolean(let d): return hit(d)
    case .array(let of, let d, _): return hit(d) || schemaMentionsCoordinates(of)
    case .object(let name, let d, let props):
        return hit(name) || hit(d) || props.contains { hit($0.name) || hit($0.description) || schemaMentionsCoordinates($0.schema) }
    }
}

@Suite("QueryPlan and planner")
struct QueryPlanTests {
    @Test func schemasNeverMentionCoordinates() {
        #expect(!schemaMentionsCoordinates(QueryPlanDTO.aiSchema))
        #expect(!schemaMentionsCoordinates(ExtractionDTO.aiSchema))
        // The helper itself catches what it should.
        let bad = AISchema.object(name: "X", properties: [AIProperty("centerLatitude", .integer())])
        #expect(schemaMentionsCoordinates(bad))
        let bad2 = AISchema.object(name: "X", properties: [AIProperty("p", .array(of: .object(name: "Y", properties: [AIProperty("lon", .integer())])))])
        #expect(schemaMentionsCoordinates(bad2))
    }

    @Test func schemasAreObjectsWithChoicesFromTheModel() {
        guard case .object(_, _, let props) = QueryPlanDTO.aiSchema else { Issue.record("not an object"); return }
        let names = Set(props.map(\.name))
        #expect(names == ["areaMode", "areaText", "features", "windows", "dateHint", "maxDriveMinutes", "keywords", "exclude"])
        if case .array(let of, _, _) = props.first(where: { $0.name == "features" })!.schema, case .string(_, let choices) = of {
            #expect(Set(choices ?? []) == Set(FeatureKind.allCases.map(\.rawValue)))
        } else { Issue.record("features is not an array of choices") }
    }

    @Test func validatorDropsUnknownChoicesAndClamps() {
        let basic = BasicQueryParser.parse("waterfalls in Yosemite")
        let dto = QueryPlanDTO(areaMode: "named", areaText: "Yosemite", features: ["waterfall", "unicorn", "waterfall"], windows: ["night", "noon"],
                               dateHint: nil, maxDriveMinutes: 100_000, keywords: ["moody", "a", "37.7, -119.6", "37.75", "x1", "moody", "b2", "c3", "d4", "e5", "f6", "g7"],
                               exclude: ["crowds"])
        let plan = QueryPlanValidator.plan(from: dto, userText: "waterfalls in Yosemite", basic: basic)
        #expect(plan.features == [.waterfall])
        #expect(plan.windows == [.night])
        // The user did not mention a drive, so the model's limit is not used at all.
        #expect(plan.maxDriveMinutes == nil)
        let spoken = QueryPlanValidator.plan(from: dto, userText: "waterfalls in Yosemite, a short drive", basic: BasicQueryParser.parse("waterfalls in Yosemite, a short drive"))
        #expect(spoken.maxDriveMinutes == 720)
        #expect(QueryPlanner.mentionsDriveTime("within 2 hours of Bishop") && !QueryPlanner.mentionsDriveTime("waterfalls in Yosemite"))
        #expect(plan.keywords.count <= QueryPlan.maximumKeywords)
        #expect(!plan.keywords.contains { $0.contains("37") && $0.contains(".") })
        #expect(plan.keywords.first == "moody")
        #expect(Set(plan.keywords).count == plan.keywords.count)
    }

    @Test func areaTextMustBeTheUsersOwnWords() {
        let basic = BasicQueryParser.parse("waterfalls in Yosemite")
        let dto = QueryPlanDTO(areaMode: "named", areaText: "Hidden Valley (37.7, -119.6)", features: ["waterfall"], windows: [], dateHint: nil,
                               maxDriveMinutes: nil, keywords: [], exclude: [])
        let plan = QueryPlanValidator.plan(from: dto, userText: "waterfalls in Yosemite", basic: basic)
        #expect(plan.areaText == "Yosemite")
    }

    @Test func aiPlanIsUsedWhenTheModelAnswers() async {
        let model = FakeModel()
        model.set { $0.json["QueryPlanDTO"] = #"{"areaMode":"named","areaText":"Lone Pine, California","features":["viewpoint"],"windows":["goldenEvening"],"keywords":["sunset"],"exclude":[]}"# }
        let (plan, origin) = await QueryPlanner(model: model, timeout: .seconds(2)).plan(for: "viewpoints near Lone Pine, California for sunset", hasMapRegion: false)
        #expect(origin == .ai)
        #expect(plan.features == [.viewpoint])
        #expect(plan.windows == [.goldenEvening])
        #expect(plan.areaText == "Lone Pine, California")
    }

    @Test func fallsBackWhenTheModelIsUnavailableFailsOrTimesOut() async {
        let text = "viewpoints near Lone Pine, California"
        let off = FakeModel(availability: .unavailable(.appleIntelligenceNotEnabled))
        var r = await QueryPlanner(model: off, timeout: .seconds(2)).plan(for: text, hasMapRegion: false)
        #expect(r.1 == .basic(reason: .appleIntelligenceNotEnabled))
        #expect(r.0.features == [.viewpoint] && r.0.areaText == "Lone Pine, California")
        #expect(r.1.label == "Basic search: AI unavailable (Apple Intelligence is turned off)")

        let broken = FakeModel()
        broken.set { $0.generateError = .generation("boom") }
        r = await QueryPlanner(model: broken, timeout: .seconds(2)).plan(for: text, hasMapRegion: false)
        #expect(r.1 == .basic(reason: nil))
        #expect(r.0.features == [.viewpoint])

        let slow = FakeModel()
        slow.set { $0.delay = .seconds(30) }
        r = await QueryPlanner(model: slow, timeout: .milliseconds(80)).plan(for: text, hasMapRegion: false)
        #expect(r.1 == .basic(reason: nil))
        #expect(slow.cancelledCount == 1)

        r = await QueryPlanner(model: nil, timeout: .seconds(1)).plan(for: text, hasMapRegion: false)
        #expect(r.1.isBasic)
    }

    @Test func queryPlanHasNoCoordinateField() throws {
        // The plan encodes to exactly these keys: nothing positional can be added without this test noticing.
        let data = try JSONEncoder().encode(QueryPlan(areaText: "X", features: [.lake], windows: [.night], dateHint: "d", maxDriveMinutes: 5,
                                                      keywords: ["k"], exclude: ["e"]))
        let keys = Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys)
        #expect(keys == ["areaText", "areaMode", "features", "windows", "dateHint", "maxDriveMinutes", "keywords", "exclude"])
    }
}
