import Foundation
import SwiftData

/// SwiftData migration plan.
///
/// Per the brief: "Plan schema versioning from the first persisted
/// release." There is only one schema version today, so this plan has an
/// empty `stages` array — but the plan itself, and the
/// `ChatterBatSchemaV1` versioned-schema wrapper it references, exist now
/// so that adding `ChatterBatSchemaV2` later is additive (new file, new
/// migration stage appended here) rather than a retrofit that risks data
/// loss for existing users.
enum ChatterBatMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ChatterBatSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
