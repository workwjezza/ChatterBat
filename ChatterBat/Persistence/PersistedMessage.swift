import Foundation
import SwiftData

/// SwiftData implementation detail only — never exposed outside
/// `Persistence/`. See `ChatterBatSchemaV1.swift` for why this is a
/// file-scope class rather than nested inside the `VersionedSchema` enum.
@Model
final class PersistedMessage {
    @Attribute(.unique) var id: UUID
    /// Plain foreign key rather than a SwiftData `@Relationship` — see
    /// docs/DECISIONS.md: relationship traversal was implicated in
    /// repeated EXC_BREAKPOINT crashes on this toolchain. A plain UUID
    /// column plus explicit queries in `SwiftDataConversationRepository`
    /// avoids relationship-graph machinery entirely.
    var conversationID: UUID
    /// Raw value of `ChatRole`.
    var roleRaw: String
    var content: String
    /// Raw value of `MessageStatus`'s case name (not its associated
    /// value — see `failureMessage` for `.failed`'s detail).
    var statusRaw: String
    var failureMessage: String?
    /// `ModelIdentity` is not itself persisted as a nested type;
    /// storing its two fields as plain columns keeps the schema
    /// simple and avoids any SwiftData/Codable-nesting ambiguity.
    var attributionServiceRaw: String?
    var attributionModelID: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    /// Explicit ordering, since two messages can share a timestamp
    /// at high append rates and `createdAt` alone is not a reliable
    /// sort key.
    var sortIndex: Int
    var createdAt: Date

    init(
        id: UUID,
        conversationID: UUID,
        roleRaw: String,
        content: String,
        statusRaw: String,
        failureMessage: String?,
        attributionServiceRaw: String?,
        attributionModelID: String?,
        promptTokens: Int?,
        completionTokens: Int?,
        totalTokens: Int?,
        sortIndex: Int,
        createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.roleRaw = roleRaw
        self.content = content
        self.statusRaw = statusRaw
        self.failureMessage = failureMessage
        self.attributionServiceRaw = attributionServiceRaw
        self.attributionModelID = attributionModelID
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
