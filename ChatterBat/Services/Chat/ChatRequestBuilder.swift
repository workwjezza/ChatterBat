import Foundation

/// Builds the JSON body for a streaming chat completion request.
///
/// Both Venice and OpenRouter accept this same minimal OpenAI-compatible
/// shape for basic text chat: `model`, `messages`, `stream`, and
/// `stream_options.include_usage`. As of Stage 6, callers may also pass
/// `AdvancedChatSettings` — already narrowed to what's applicable via
/// `AdvancedChatSettings.applicable(to:)` by the caller — which adds:
/// - `reasoning_effort` (both services, when non-`nil`)
/// - `venice_parameters.{disable_thinking, strip_thinking_response}`
///   (Venice only; never sent when both are `false`, matching Venice's
///   documented defaults exactly so an all-default settings value never
///   changes the request)
/// - `provider.{allow_fallbacks, data_collection, zdr}` (OpenRouter
///   only; each sub-field is only included when it differs from
///   OpenRouter's own documented default, for the same reason)
enum ChatRequestBuilder {
    static func body(
        modelID: String,
        messages: [OutgoingChatMessage],
        service: AIService,
        settings: AdvancedChatSettings = AdvancedChatSettings()
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelID,
            "messages": messages.map { message in
                ["role": message.role.rawValue, "content": message.content]
            },
            "stream": true,
            "stream_options": ["include_usage": true]
        ]

        if let effort = settings.reasoningEffort {
            body["reasoning_effort"] = effort.rawValue
        }

        if service == .venice {
            var veniceParameters: [String: Any] = [:]
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
        settings: AdvancedChatSettings = AdvancedChatSettings()
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: body(modelID: modelID, messages: messages, service: service, settings: settings)
        )
    }
}
