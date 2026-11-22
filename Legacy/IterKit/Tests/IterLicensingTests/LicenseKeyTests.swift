import Testing
@testable import IterLicensing

@Suite("LicenseKey")
struct LicenseKeyTests {
    @Test func parsesUUIDShapeAndUppercases() throws {
        let key = try #require(LicenseKey(parsing: "38b1460a-5104-4067-a91d-77b872934d51"))
        #expect(key.value == "38B1460A-5104-4067-A91D-77B872934D51")
        #expect(key.apiValue == "38b1460a-5104-4067-a91d-77b872934d51")
    }

    @Test func toleratesWhitespaceNewlinesAndMissingDashes() throws {
        let canonical = "38B1460A-5104-4067-A91D-77B872934D51"
        #expect(LicenseKey(parsing: "  38b1460a51044067a91d77b872934d51\n")?.value == canonical)
        #expect(LicenseKey(parsing: "38b1460a 5104 4067 a91d 77b872934d51")?.value == canonical)
        #expect(LicenseKey(parsing: "38B1460A-5104-\n4067-A91D-77B872934D51 ")?.value == canonical)
    }

    @Test func keepsFourByEightShape() throws {
        let key = try #require(LicenseKey(parsing: "aaaaaaaa-bbbbbbbb-cccccccc-dddddddd"))
        #expect(key.value == "AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD")
    }

    @Test(arguments: ["", "hello", "1234", "38b1460a-5104-4067-a91d-77b872934d5", "g8b1460a-5104-4067-a91d-77b872934d51", "38b1460a-5104-4067-a91d-77b872934d511"])
    func rejectsGarbage(input: String) {
        #expect(LicenseKey(parsing: input) == nil)
    }

    @Test func masksAllButLastFour() throws {
        let key = try #require(LicenseKey(parsing: "38b1460a-5104-4067-a91d-77b872934d51"))
        #expect(key.masked.hasSuffix("4D51"))
        #expect(!key.masked.contains("38B1"))
        #expect(key.masked.count == key.value.count)
        #expect(key.description == key.masked)
    }
}
