import Foundation

/// Builds the JSON body for a streaming chat completion request.
///
/// Both Venice and OpenRouter accept this same minimal OpenAI-compatible
/// shape for basic text chat: `model`, `messages`, `stream`, and
/// `stream_options.include_usage`. As of Stage 6, callers may also pass
/// `AdvancedChatSettings` — already narrowed to what's applicable via
/// `AdvancedChatSettings.applicable(to:)` by the caller — which adds:
/// - `reasoning_effort` (both services, when non-`nil`)
/// - `venice_parameters.include_venice_system_prompt` (explicit opt-out
///   by default), plus non-default thinking controls (Venice only)
/// - `provider.{allow_fallbacks, data_collection, zdr}` (OpenRouter
///   only; each sub-field is only included when it differs from
///   OpenRouter's own documented default, for the same reason)
enum ChatRequestBuilder {
    static func body(
        modelID: String,
        messages: [OutgoingChatMessage],
        service: AIService,
        settings: AdvancedChatSettings = AdvancedChatSettings(),
        tools: [AgentTool] = []
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelID,
            "messages": messages.map(Self.encode),
            "stream": true,
            "stream_options": ["include_usage": true]
        ]

        // Stage 7: `tools` defaults to `[]`, which omits the field
        // entirely — never sends an empty `tools: []` array, matching
        // "no tools requested" exactly as no field at all. When tools
        // *are* present, `parallel_tool_calls: false` is always sent
        // alongside them: `ChatCoordinator` only ever approves one
        // tool call at a time, and this keeps that a documented,
        // provider-enforced guarantee rather than an assumption about
        // model behavior — see `ChatStreamEvent`'s doc comment on
        // `toolCallDelta`.
        if !tools.isEmpty {
            body["tools"] = tools.map { $0.requestDefinition() }
            body["parallel_tool_calls"] = false
        }

        if let effort = settings.reasoningEffort {
            body["reasoning_effort"] = effort.rawValue
        }

        if service == .venice {
            var veniceParameters: [String: Any] = [
                "include_venice_system_prompt": settings.venice.includeSystemPrompt
            ]
            if settings.venice.disableThinking {
                veniceParameters["disable_thinking"] = true
            }
            if settings.venice.stripThinkingResponse {
                veniceParameters["strip_thinking_response"] = true
            }
            if !veniceParameters.isEmpty {
                body["venice_parameters"] = veniceParameters
            }
        }

        if service == .openRouter {
            var provider: [String: Any] = [:]
            if settings.openRouterRouting.allowFallbacks == false {
                provider["allow_fallbacks"] = false
            }
            if settings.openRouterRouting.dataCollection == .deny {
                provider["data_collection"] = "deny"
            }
            if settings.openRouterRouting.zdr {
                provider["zdr"] = true
            }
            if !provider.isEmpty {
                body["provider"] = provider
            }
        }

        return body
    }

    static func requestData(
        modelID: String,
        messages: [OutgoingChatMessage],
        service: AIService,
        settings: AdvancedChatSettings = AdvancedChatSettings(),
        tools: [AgentTool] = []
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: body(modelID: modelID, messages: messages, service: service, settings: settings, tools: tools)
        )
    }

    /// Encodes one `OutgoingChatMessage` into the exact OpenAI-compatible
    /// per-message JSON shape both providers document: plain
    /// `{"role", "content"}` for ordinary messages; an assistant
    /// message replaying a prior tool request additionally carries
    /// `tool_calls: [{"id", "type": "function", "function": {"name",
    /// "arguments"}}]`; a `.tool` message (the result being fed back)
    /// additionally carries `tool_call_id`.
    private static func encode(_ message: OutgoingChatMessage) -> [String: Any] {
        var encoded: [String: Any] = ["role": message.role.rawValue, "content": message.content]
        if !message.toolCalls.isEmpty {
            encoded["tool_calls"] = message.toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.argumentsJSON]
                ]
            }
        }
        if let toolCallID = message.toolCallID {
            encoded["tool_call_id"] = toolCallID
        }
        return encoded
    }
}
