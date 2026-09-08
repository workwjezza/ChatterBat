import Foundation

/// A versioned, self-describing JSON representation of one exported
/// conversation.
///
/// Per the brief's requirement to "plan schema versioning from the
/// first persisted release" — applied here to files, not just the
/// SwiftData store — every export carries an explicit `schemaVersion`
/// so a future format change can still read (or knowingly reject) an
/// older file rather than silently misinterpreting it.
///
/// Deliberately excludes anything sensitive: no API keys (this format
/// has no field for one at all), and no provider-account identifiers.
/// Only conversation/message content the user already sees in the
/// transcript is included.
struct ConversationExport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let title: String
    let updatedAt: Date
    let messages: [ExportedMessage]

    struct ExportedMessage: Codable, Equatable, Sendable {
        let id: UUID
        let role: String
        let content: String
        let status: String
        /// Present only for a `.failed` message — mirrors
        /// `MessageStatusCoding`'s on-disk representation so export/
        /// import round-trips through the same status vocabulary the
        /// SwiftData store already uses, rather than inventing a
        /// second encoding.
        let failureMessage: String?
        let attributionService: String?
        let attributionModelID: String?
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        /// Stage 7: present only for a `.tool`-role message — see
        /// `ToolInvocationRecord`. All four travel together or not at
        /// all, mirroring how `ToolInvocationRecord` itself is either
        /// fully present or `nil` on `TranscriptMessage`.
        let toolName: String?
        let toolCallID: String?
        let toolModelStatedReason: String?
        let toolApprovedItemName: String?
    }
}
