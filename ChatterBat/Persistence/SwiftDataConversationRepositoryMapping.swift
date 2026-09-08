import Foundation
import SwiftData

/// SwiftData <-> plain-struct mapping for `SwiftDataConversationRepository`,
/// split into its own file to keep the query logic file focused.
extension SwiftDataConversationRepository {
    static func map(_ persisted: PersistedConversation) -> Conversation {
        Conversation(
            id: persisted.id,
            title: persisted.title,
            lastMessagePreview: persisted.lastMessagePreview,
            updatedAt: persisted.updatedAt
        )
    }

    static func map(_ persisted: PersistedMessage) -> TranscriptMessage {
        let attribution: ModelIdentity? = {
            guard
                let serviceRaw = persisted.attributionServiceRaw,
                let service = AIService(rawValue: serviceRaw),
                let modelID = persisted.attributionModelID
            else { return nil }
            return ModelIdentity(service: service, modelID: modelID)
        }()
        let usage: ChatUsage? = {
            guard persisted.promptTokens != nil || persisted.completionTokens != nil || persisted.totalTokens != nil else {
                return nil
            }
            return ChatUsage(
                promptTokens: persisted.promptTokens,
                completionTokens: persisted.completionTokens,
                totalTokens: persisted.totalTokens
            )
        }()
        let toolInvocation: ToolInvocationRecord? = {
            guard
                let toolRaw = persisted.toolRaw,
                let tool = AgentTool(rawValue: toolRaw),
                let toolCallID = persisted.toolCallID
            else { return nil }
            return ToolInvocationRecord(
                tool: tool,
                toolCallID: toolCallID,
                modelStatedReason: persisted.toolModelStatedReason ?? "",
                approvedItemName: persisted.toolApprovedItemName
            )
        }()
        return TranscriptMessage(
            id: persisted.id,
            role: ChatRole(rawValue: persisted.roleRaw) ?? .user,
            content: persisted.content,
            status: MessageStatusCoding.status(fromRaw: persisted.statusRaw, failureMessage: persisted.failureMessage),
            attribution: attribution,
            usage: usage,
            toolInvocation: toolInvocation
        )
    }

    static func map(_ message: TranscriptMessage, conversationID: UUID, sortIndex: Int) -> PersistedMessage {
        PersistedMessage(
            id: message.id,
            conversationID: conversationID,
            roleRaw: message.role.rawValue,
            content: message.content,
            statusRaw: MessageStatusCoding.rawValue(for: message.status),
            failureMessage: MessageStatusCoding.failureMessage(for: message.status),
            attributionServiceRaw: message.attribution?.service.rawValue,
            attributionModelID: message.attribution?.modelID,
            promptTokens: message.usage?.promptTokens,
            completionTokens: message.usage?.completionTokens,
            totalTokens: message.usage?.totalTokens,
            sortIndex: sortIndex,
            createdAt: .now,
            toolRaw: message.toolInvocation?.tool.rawValue,
            toolCallID: message.toolInvocation?.toolCallID,
            toolModelStatedReason: message.toolInvocation?.modelStatedReason,
            toolApprovedItemName: message.toolInvocation?.approvedItemName
        )
    }

    static func apply(_ message: TranscriptMessage, to persisted: PersistedMessage) {
        persisted.content = message.content
        persisted.statusRaw = MessageStatusCoding.rawValue(for: message.status)
        persisted.failureMessage = MessageStatusCoding.failureMessage(for: message.status)
        persisted.promptTokens = message.usage?.promptTokens
        persisted.completionTokens = message.usage?.completionTokens
        persisted.totalTokens = message.usage?.totalTokens
        persisted.toolApprovedItemName = message.toolInvocation?.approvedItemName
    }
}
