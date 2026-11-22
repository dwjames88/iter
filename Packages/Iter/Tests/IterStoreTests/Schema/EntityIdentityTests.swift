import Foundation
import CoreData
import SwiftData
import Testing
@testable import IterStore

/// The blueprint's open question: do the rebuilt module's frozen schemas build Core Data models identical (entity names
/// and version hashes) to the ones the OLD module `IterData` built for the owner's store? `model-hashes.json` came from
/// the old module. If this fails, the owner's store would not open: stop and investigate.
@Suite struct EntityIdentityTests {
    struct Hashes: Decodable {
        struct Entity: Decodable { var name: String; var versionHash: String }
        struct Schema: Decodable { var entities: [Entity]; var schemaVersion: String }
        var schemas: [String: Schema]
    }

    func hashes() throws -> Hashes {
        let url = try TestSupport.fixturesRoot.appending(path: "model-hashes.json")
        return try JSONDecoder().decode(Hashes.self, from: Data(contentsOf: url))
    }

    func model(_ models: [any PersistentModel.Type]) throws -> NSManagedObjectModel {
        try #require(NSManagedObjectModel.makeManagedObjectModel(for: models))
    }

    func actual(_ models: [any PersistentModel.Type]) throws -> [String: String] {
        let model = try model(models)
        return Dictionary(uniqueKeysWithValues: model.entities.map { ($0.name ?? "", $0.versionHash.base64EncodedString()) })
    }

    @Test(arguments: [("IterSchemaV1", 1), ("IterSchemaV2", 2), ("IterSchemaV3", 3), ("IterSchemaV4", 4)])
    func frozenSchemaMatchesTheOldModule(name: String, version: Int) throws {
        let models: [any PersistentModel.Type]
        switch version {
        case 1: models = IterSchemaV1.models
        case 2: models = IterSchemaV2.models
        case 3: models = IterSchemaV3.models
        default: models = IterSchemaV4.models
        }
        let expected = try #require(try hashes().schemas[name])
        #expect(expected.schemaVersion == "\(version).0.0")
        let expectedByName = Dictionary(uniqueKeysWithValues: expected.entities.map { ($0.name, $0.versionHash) })
        let got = try actual(models)
        #expect(Set(got.keys) == Set(expectedByName.keys))
        for (entity, hash) in expectedByName {
            #expect(got[entity] == hash, "\(name).\(entity)")
        }
    }

    @Test func versionIdentifiers() {
        #expect(IterSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(IterSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(IterSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
    }

    @Test func v5KeepsTheOldEntityNames() throws {
        let v5 = try actual(IterSchemaV5.models)
        let v4 = try hashes().schemas["IterSchemaV4"]!
        for entity in v4.entities {
            #expect(v5[entity.name] != nil, "V5 has an entity named \(entity.name)")
        }
        #expect(Set(v5.keys) == ["PlaceRecord", "TripRecord", "StopRecord", "FolderRecord",
                                 "TripRunRecord", "StopVisitRecord", "DeletionRecord", "SyncPeerRecord"])
        // V5 really differs from V4 (it is a schema change), for the four shared models except none unchanged:
        // Folder is unchanged, so its hash must be identical.
        #expect(v5["FolderRecord"] == v4.entities.first { $0.name == "FolderRecord" }?.versionHash)
        #expect(v5["PlaceRecord"] != v4.entities.first { $0.name == "PlaceRecord" }?.versionHash)
    }
}
