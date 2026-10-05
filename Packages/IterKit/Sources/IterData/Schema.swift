import Foundation
import SwiftData

/// Version 1 of the store. Later versions add a new `VersionedSchema` and a migration stage to `IterMigrationPlan`.
public enum IterSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [PlaceRecord.self, TripRecord.self, StopRecord.self] }
}

public enum IterMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [IterSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum IterSchema {
    /// The current schema.
    public static var current: Schema { Schema(versionedSchema: IterSchemaV1.self) }

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
}
