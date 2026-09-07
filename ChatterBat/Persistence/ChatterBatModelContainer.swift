import Foundation
import SwiftData

/// Factory for the app's `ModelContainer`.
///
/// Kept separate from `AppDependencies` so tests can construct an
/// isolated in-memory container without touching the app's real
/// on-disk store, per the brief's testing contract (persistence tests
/// must use isolated/in-memory stores).
enum ChatterBatModelContainer {
    /// The real, on-disk container used by the running app.
    @MainActor
    static func live() -> ModelContainer {
        let schema = Schema(ChatterBatSchemaV1.models)
        do {
            return try ModelContainer(for: schema, migrationPlan: ChatterBatMigrationPlan.self)
        } catch {
            // A failure to open the on-disk store (corrupt file, disk
            // full, etc.) is rare but must not silently discard the
            // user's history by falling back to an in-memory store as if
            // nothing were wrong. Surfacing this as a fatal startup error
            // is the honest choice until Stage 8's hardening pass adds a
            // recovery/backup UI; a partially-working app that silently
            // can't save is worse than a clear failure at launch.
            fatalError("Failed to open the ChatterBat data store: \(error)")
        }
    }

    /// An isolated, in-memory container for tests and previews. Never
    /// persists to disk and never shares state with `live()` or with
    /// another call to this function.
    @MainActor
    static func inMemory() -> ModelContainer {
        let schema = Schema(ChatterBatSchemaV1.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: ChatterBatMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create an in-memory test data store: \(error)")
        }
    }
}
