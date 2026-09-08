import Foundation
import SwiftData

/// SwiftData implementation detail only — never exposed outside
/// `Persistence/`. See `ChatterBatSchemaV1.swift` for why this is a
/// file-scope class rather than nested inside the `VersionedSchema` enum.
@Model
final class PersistedConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Locally-derived preview text (never model-generated), kept in
    /// sync with the conversation's most recent message so the
    /// sidebar doesn't need to fetch/sort the message relationship
    /// just to render a preview line.
    var lastMessagePreview: String
    var createdAt: Date
    var updatedAt: Date
    /// Stage 6: the message ID (if any) marking where this
    /// conversation's *sent* context starts — see
    /// `ChatCoordinator.setContextBoundary`'s doc comment. Added as a
    /// plain optional attribute with a default (rather than a new
    /// `VersionedSchema`/`SchemaMigrationPlan` stage) since it's
    /// purely additive and SwiftData performs this kind of change as
    /// an automatic lightweight migration; consistent with this
    /// project's existing "avoid relationship/predicate machinery on
    /// this toolchain" posture (see docs/DECISIONS.md), this is a
    /// plain UUID column, never a `@Relationship`. NOTE: this has only
    /// been exercised against a freshly-created store in this stage's
    /// testing, not against a pre-Stage-6 store already containing
    /// real conversations — see docs/STATUS.md for the follow-up this
    /// implies.
    var contextBoundaryMessageID: UUID?

    init(
        id: UUID,
        title: String,
        lastMessagePreview: String,
        createdAt: Date,
        updatedAt: Date,
        contextBoundaryMessageID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contextBoundaryMessageID = contextBoundaryMessageID
    }
}
