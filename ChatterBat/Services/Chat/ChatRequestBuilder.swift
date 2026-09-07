import Foundation

/// Builds the JSON body for a streaming chat completion request.
///
/// Both Venice and OpenRouter accept this same minimal OpenAI-compatible
/// shape for basic text chat: `model`, `messages`, `stream`, and
/// `stream_options.include_usage`. Per the brief, only fields verified as
/// supported are sent — Stage 3 deliberately sends nothing
/// provider-specific (no `venice_parameters`, no OpenRouter `provider`
/// routing object); those arrive in Stage 6 once there's a UI for them.
enum ChatRequestBuilder {
    static func body(modelID: String, messages: [OutgoingChatMessage]) -> [String: Any] {
        [
            "model": modelID,
            "messages": messages.map { message in
                ["role": message.role.rawValue, "content": message.content]
            },
            "stream": true,
            "stream_options": ["include_usage": true]
        ]
    }

    static func requestData(modelID: String, messages: [OutgoingChatMessage]) throws -> Data {
        try JSONSerialization.data(withJSONObject: body(modelID: modelID, messages: messages))
    }
}
