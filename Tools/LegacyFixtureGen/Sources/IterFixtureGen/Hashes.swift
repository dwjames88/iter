import Foundation
import CoreData
import SwiftData
@testable import IterData

/// The Core Data model SwiftData builds for a versioned schema, via `NSManagedObjectModel.makeManagedObjectModel(for:)`.
func modelInfo(_ schemaType: any VersionedSchema.Type) -> J {
    guard let model = NSManagedObjectModel.makeManagedObjectModel(for: schemaType.models) else { return .null }
    var entities: [J] = []
    for e in model.entities.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
        var rels: [J] = []
        for (name, r) in e.relationshipsByName.sorted(by: { $0.key < $1.key }) {
            rels.append(.object(["name": .string(name), "destination": .opt(r.destinationEntity?.name), "inverse": .opt(r.inverseRelationship?.name),
                                 "toMany": .bool(r.isToMany), "deleteRule": .int(Int(r.deleteRule.rawValue))]))
        }
        entities.append(.object([
            "name": .opt(e.name), "managedObjectClassName": .string(e.managedObjectClassName ?? ""),
            "versionHash": .string(e.versionHash.base64EncodedString()),
            "versionHashModifier": .opt(e.versionHashModifier),
            "attributes": .array(e.attributesByName.keys.sorted().map { .string($0) }),
            "relationships": .array(rels)]))
    }
    let swiftDataNames = Schema(versionedSchema: schemaType).entities.map(\.name).sorted()
    return .object(["schemaVersion": .string(String(describing: schemaType.versionIdentifier)),
                    "swiftDataSchemaEntityNames": .array(swiftDataNames.map { .string($0) }),
                    "modelVersionIdentifiers": .array(model.versionIdentifiers.compactMap { $0 as? String }.sorted().map { .string($0) }),
                    "entities": .array(entities)])
}

/// `NSStoreModelVersionHashes` / `NSStoreModelVersionIdentifiers` (and the other metadata keys) of the store at `url`.
func storeMetadata(at url: URL) throws -> J {
    let md = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url, options: nil)
    var hashes: [String: J] = [:]
    for (k, v) in (md[NSStoreModelVersionHashesKey] as? [String: Data]) ?? [:] { hashes[k] = .string(v.base64EncodedString()) }
    let ids = (md[NSStoreModelVersionIdentifiersKey] as? [Any])?.compactMap { $0 as? String } ?? []
    return .object(["NSStoreModelVersionHashes": .object(hashes),
                    "NSStoreModelVersionIdentifiers": .array(ids.sorted().map { .string($0) }),
                    "NSStoreType": .opt(md[NSStoreTypeKey] as? String),
                    "otherMetadataKeys": .array(md.keys.filter { $0 != NSStoreModelVersionHashesKey && $0 != NSStoreModelVersionIdentifiersKey && $0 != NSStoreUUIDKey }.sorted().map { .string($0) })])
}
