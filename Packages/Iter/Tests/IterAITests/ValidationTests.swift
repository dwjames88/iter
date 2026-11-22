import Foundation
import Testing
@testable import IterAI

@Suite struct ValidationTests {
    let nested = AISchema.object(name: "Root", properties: [
        AIProperty("places", .array(of: .object(name: "Place", properties: [
            AIProperty("name", .string()),
            AIProperty("tags", .array(of: .string(choices: ["a", "b"]), maxCount: 2)),
            AIProperty("rank", .integer(range: 1...5)),
            AIProperty("open", .boolean(), optional: true),
        ]), maxCount: 2)),
    ])

    @Test func conformingValueRoundTrips() throws {
        let json = #"{"places":[{"name":"x","tags":["a"],"rank":3,"open":true},{"name":"y","tags":[],"rank":1}]}"#
        try AISchemaValidation.validate(json: Data(json.utf8), against: nested)
    }

    @Test(arguments: [
        #"{"places":[{"name":"x","tags":["c"],"rank":3}]}"#,
        #"{"places":[{"name":"x","tags":[],"rank":9}]}"#,
        #"{"places":[{"name":"x","tags":[],"rank":1.5}]}"#,
        #"{"places":[{"name":"x","tags":[]}]}"#,
        #"{"places":[{"name":"x","tags":["a","b","a"],"rank":1}]}"#,
        #"{"places":[{"name":"x","tags":[],"rank":1,"extra":1}]}"#,
        #"{"places":[{"name":"x","tags":[],"rank":true}]}"#,
        #"{"places":[{"name":1,"tags":[],"rank":1}]}"#,
        #"{"places":[{"name":"a","tags":[],"rank":1},{"name":"b","tags":[],"rank":1},{"name":"c","tags":[],"rank":1}]}"#,
        #"not json"#,
    ])
    func rejects(json: String) {
        #expect(throws: AIError.self) { try AISchemaValidation.validate(json: Data(json.utf8), against: nested) }
        #expect(!AISchemaValidation.problems(json: Data(json.utf8), against: nested).isEmpty)
    }

    @Test func coordinateNamesAreDetected() {
        func obj(_ n: String) -> AISchema { .object(name: "O", properties: [AIProperty(n, .string())]) }
        for bad in ["lat", "latitude", "lon", "lng", "Longitude", "coordinate", "placeLat", "map_lng", "coords"] {
            #expect(obj(bad).mentionsCoordinates, "\(bad)")
        }
        for good in ["template", "name", "latest", "slong", "reason"] {
            #expect(!obj(good).mentionsCoordinates, "\(good)")
        }
        #expect(AISchema.array(of: obj("lat")).mentionsCoordinates)
        #expect(!Toy.aiSchema.mentionsCoordinates)
    }
}
