import Foundation
import SwiftData

/// Version 1 of the persisted schema.
///
/// Per the brief: "Plan schema versioning from the first persisted
/// release." `ChatterBatSchemaV1` is a plain namespace enum listing
/// which model types belong to this schema version; the `@Model`
/// classes themselves (`PersistedConversation`, `PersistedMessage`) are
/// declared at file scope below, NOT nested inside this enum.
///
/// This deliberately deviates from Apple's commonly-shown sample pattern
/// of nesting `@Model` classes inside the `VersionedSchema` enum body —
/// see docs/DECISIONS.md: nesting them reproducibly caused
/// `ModelContext.fetch`/`insert`/`save` to crash the process with
/// EXC_BREAKPOINT on this toolchain (Xcode 26.6 / macOS 26.6.2),
/// consistent with a known class of SwiftData bugs around nested
/// `@Model` type metadata. File-scope model classes referenced by a
/// plain enum give the same versioning/migration capability without
/// that crash.
enum ChatterBatSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PersistedConversation.self, PersistedMessage.self]
    }
}
