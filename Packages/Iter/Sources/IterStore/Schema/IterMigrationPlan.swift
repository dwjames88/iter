import Foundation
import SwiftData

/// Every step only adds optional relationships, new models and attributes with defaults, so each migration is
/// lightweight. V1 to V4 are the old app's stages, V5 is the rebuild's.
public enum IterMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [IterSchemaV1.self, IterSchemaV2.self, IterSchemaV3.self, IterSchemaV4.self, IterSchemaV5.self]
    }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: IterSchemaV1.self, toVersion: IterSchemaV2.self),
         .lightweight(fromVersion: IterSchemaV2.self, toVersion: IterSchemaV3.self),
         .lightweight(fromVersion: IterSchemaV3.self, toVersion: IterSchemaV4.self),
         .lightweight(fromVersion: IterSchemaV4.self, toVersion: IterSchemaV5.self)]
    }
}

/// The same plan stopping at the frozen V4 schema. The backup opens a scratch copy with this, so it can read every
/// trip through the frozen V4 classes without ever involving V5.
public enum IterMigrationPlanToV4: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [IterSchemaV1.self, IterSchemaV2.self, IterSchemaV3.self, IterSchemaV4.self]
    }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: IterSchemaV1.self, toVersion: IterSchemaV2.self),
         .lightweight(fromVersion: IterSchemaV2.self, toVersion: IterSchemaV3.self),
         .lightweight(fromVersion: IterSchemaV3.self, toVersion: IterSchemaV4.self)]
    }
}
