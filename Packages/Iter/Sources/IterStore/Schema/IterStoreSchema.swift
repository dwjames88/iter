import Foundation
import SwiftData

/// Entry points for building containers on the live schema. (Not named `IterStore`: that is the module name.)
public enum IterStoreSchema {
    /// The current schema.
    public static var current: Schema { Schema(versionedSchema: IterSchemaV5.self) }

    /// An on-disk container at `url`, migrating an older store there if needed. iCloud sync is off.
    /// Callers that open a user's store go through `StoreOpener`, which backs up first.
    public static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = current
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: IterMigrationPlan.self, configurations: [configuration])
    }

    /// An in-memory container with a unique name, so two of them (parallel tests) never share a store.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = current
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: IterMigrationPlan.self, configurations: [configuration])
    }

    /// A container at `url` on the frozen V4 schema, migrating V1 to V3 stores up to V4 and no further. Used only by
    /// the backup, on a scratch copy.
    static func makeLegacyV4Container(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: IterSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: IterMigrationPlanToV4.self, configurations: [configuration])
    }
}
