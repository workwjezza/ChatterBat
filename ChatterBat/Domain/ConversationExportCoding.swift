import Foundation

/// Converts between `ConversationExport` (the versioned file format)
/// and ChatterBat's in-memory domain types, and encodes/decodes it as
/// pretty-printed, sorted-key JSON (sorted keys purely so exported
/// files are stable/diffable, not a correctness requirement).
enum ConversationExportCoding {
    /// Builds an export value from a conversation and its full
    /// transcript. Does not touch any repository or file system
    /// itself — callers own I/O.
    static func export(conversation: Conversation, messages: [TranscriptMessage]) -> ConversationExport {
        ConversationExport(
            schemaVersion: ConversationExport.currentSchemaVersion,
            id: conversation.id,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            messages: messages.map { message in
                ConversationExport.ExportedMessage(
                    id: message.id,
                    role: message.role.rawValue,
                    content: message.content,
                    status: MessageStatusCoding.rawValue(for: message.status),
                    failureMessage: MessageStatusCoding.failureMessage(for: message.status),
                    attributionService: message.attribution?.service.rawValue,
                    attributionModelID: message.attribution?.modelID,
                    promptTokens: message.usage?.promptTokens,
                    completionTokens: message.usage?.completionTokens,
                    totalTokens: message.usage?.totalTokens,
                    toolName: message.toolInvocation?.tool.rawValue,
                    toolCallID: message.toolInvocation?.toolCallID,
                    toolModelStatedReason: message.toolInvocation?.modelStatedReason,
                    toolApprovedItemName: message.toolInvocation?.approvedItemName
                )
            }
        )
    }

    /// Plain `.iso8601` truncates sub-second precision entirely, which
    /// would make an encode/decode round trip badly lossy for
    /// `updatedAt` (losing everything below one full second);
    /// `.withFractionalSeconds` narrows that to millisecond precision
    /// only, which is more than sufficient for a "when was this
    /// conversation last updated" display field. Built fresh on each call
    /// (rather than cached in a `static let`) since `ISO8601DateFormatter`
    /// is not `Sendable` and this enum has no actor context to isolate
    /// a shared mutable instance to; formatter construction is cheap
    /// enough that this isn't a meaningful performance concern at
    /// ChatterBat's scale (one export/import at a time, user-initiated).
    private static func fractionalSecondsFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func encode(_ export: ConversationExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsFormatter().string(from: date))
        }
        return try encoder.encode(export)
    }

    /// Errors specific to *importing* a file — distinct from a plain
    /// JSON-decoding failure, so the UI can show a more specific
    /// message than "couldn't read file" for the one case ChatterBat
    /// can actually anticipate: a future, incompatible schema version.
    enum ImportError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }

    /// Decodes a `ConversationExport` from `data`, rejecting any
    /// `schemaVersion` newer than what this build understands — per
    /// the brief's versioning requirement, a future format must never
    /// be silently misread as the current one.
    static func decode(_ data: Data) throws -> ConversationExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalSecondsFormatter().date(from: string) {
                return date
            }
            // Falls back to plain (no-fractional-seconds) ISO 8601 for
            // forward/backward compatibility with any file that
            // doesn't carry fractional seconds.
            let fallbackFormatter = ISO8601DateFormatter()
            if let date = fallbackFormatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        let export = try decoder.decode(ConversationExport.self, from: data)
        guard export.schemaVersion <= ConversationExport.currentSchemaVersion else {
            throw ImportError.unsupportedSchemaVersion(export.schemaVersion)
        }
        return export
    }

    /// Converts a decoded export back into domain types. Always
    /// assigns a fresh conversation ID (and, transitively, keeps each
    /// message's own ID only for internal round-trip consistency —
    /// callers pass these straight to `ConversationRepository`, which
    /// treats them as a brand-new conversation) rather than reusing
    /// the exported conversation ID, so importing the same file twice
    /// creates two independent conversations instead of colliding with
    /// an existing one.
    static func importAsNewConversation(_ export: ConversationExport) -> (conversation: Conversation, messages: [TranscriptMessage]) {
        let conversation = Conversation(
            title: export.title,
            lastMessagePreview: export.messages.last?.content.prefix(120).description ?? "",
            updatedAt: export.updatedAt
        )
        let messages = export.messages.map { exported -> TranscriptMessage in
            let attribution: ModelIdentity? = {
                guard
                    let serviceRaw = exported.attributionService,
                    let service = AIService(rawValue: serviceRaw),
                    let modelID = exported.attributionModelID
                else { return nil }
                return ModelIdentity(service: service, modelID: modelID)
            }()
            let usage: ChatUsage? = {
                guard exported.promptTokens != nil || exported.completionTokens != nil || exported.totalTokens != nil else {
                    return nil
                }
                return ChatUsage(
                    promptTokens: exported.promptTokens,
                    completionTokens: exported.completionTokens,
                    totalTokens: exported.totalTokens
                )
            }()
            let toolInvocation: ToolInvocationRecord? = {
                guard
                    let toolName = exported.toolName,
                    let tool = AgentTool(rawValue: toolName),
                    let toolCallID = exported.toolCallID
                else { return nil }
                return ToolInvocationRecord(
                    tool: tool,
                    toolCallID: toolCallID,
                    modelStatedReason: exported.toolModelStatedReason ?? "",
                    approvedItemName: exported.toolApprovedItemName
                )
            }()
            return TranscriptMessage(
                role: ChatRole(rawValue: exported.role) ?? .user,
                content: exported.content,
                status: MessageStatusCoding.status(fromRaw: exported.status, failureMessage: exported.failureMessage),
                attribution: attribution,
                usage: usage,
                toolInvocation: toolInvocation
            )
        }
        return (conversation, messages)
    }
}
