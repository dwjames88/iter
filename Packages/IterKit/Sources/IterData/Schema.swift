import Foundation
import SwiftData

/// Version 2 of the store: the live models plus folders (and per-trip pin, per-trip and per-place ordering).
/// Version 1 is frozen in `SchemaV1.swift`.
public enum IterSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [PlaceRecord.self, TripRecord.self, StopRecord.self, FolderRecord.self]
    }
}

/// V1 to V2 only adds optional relationships and attributes with defaults, so the migration is lightweight.
public enum IterMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [IterSchemaV1.self, IterSchemaV2.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: IterSchemaV1.self, toVersion: IterSchemaV2.self)]
    }
}

public enum IterSchema {
    /// The current schema.
    public static var current: Schema { Schema(versionedSchema: IterSchemaV2.self) }

    /// The app's container. On disk it uses SwiftData's default store location (Application Support);
    /// iCloud sync is off (`cloudKitDatabase: .none`) until the app is ready for it.
    /// Attach it to the UI with model-context undo disabled: `IterStore` registers its own named undo actions.
    public static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = current
        let configuration: ModelConfiguration
        if inMemory {
            // A unique name so two in-memory containers (e.g. parallel tests) never share a store.
            configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: IterMigrationPlan.self, configurations: [configuration])
    }

    /// An on-disk container at `url` (migrating an older store there if needed). Used by the migration tests.
    public static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = current
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: IterMigrationPlan.self, configurations: [configuration])
    }
}
