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

    init(id: UUID, title: String, lastMessagePreview: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
