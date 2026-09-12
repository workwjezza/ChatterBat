import XCTest
@testable import ChatterBat

final class ChatRequestBuilderTests: XCTestCase {
    private let messages = [OutgoingChatMessage(role: .user, content: "Hi")]

    func testDefaultSettingsDisableVenicePromptWithoutChangingReasoning() {
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice)
        XCTAssertNil(body["reasoning_effort"])
        let parameters = body["venice_parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["include_venice_system_prompt"] as? Bool, false)
        XCTAssertNil(body["provider"])
    }

    func testReasoningEffortIsSentAsTopLevelStringForVenice() {
        let settings = AdvancedChatSettings(reasoningEffort: .high)
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, settings: settings)
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
    }

    func testReasoningEffortIsSentAsTopLevelStringForOpenRouter() {
        let settings = AdvancedChatSettings(reasoningEffort: .low)
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .openRouter, settings: settings)
        XCTAssertEqual(body["reasoning_effort"] as? String, "low")
    }

    func testVeniceParametersContainOnlyPromptControlWhenThinkingFlagsFalse() {
        let settings = AdvancedChatSettings(venice: VeniceAdvancedSettings(disableThinking: false, stripThinkingResponse: false))
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, settings: settings)
        let parameters = body["venice_parameters"] as? [String: Any]
        XCTAssertEqual(parameters?.count, 1)
        XCTAssertEqual(parameters?["include_venice_system_prompt"] as? Bool, false)
    }

    func testVeniceSystemPromptCanBeRestored() {
        let settings = AdvancedChatSettings(venice: VeniceAdvancedSettings(includeSystemPrompt: true))
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, settings: settings)
        let parameters = body["venice_parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["include_venice_system_prompt"] as? Bool, true)
        let encoded = body["messages"] as? [[String: Any]]
        XCTAssertEqual(encoded?.count, 1)
        XCTAssertEqual(encoded?.first?["content"] as? String, "Hi")
    }

    func testVeniceParametersIncludesOnlySetFlags() {
        let settings = AdvancedChatSettings(venice: VeniceAdvancedSettings(disableThinking: true, stripThinkingResponse: false))
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, settings: settings)
        let veniceParameters = body["venice_parameters"] as? [String: Any]
        XCTAssertEqual(veniceParameters?["disable_thinking"] as? Bool, true)
        XCTAssertNil(veniceParameters?["strip_thinking_response"])
    }

    func testVeniceParametersNeverSentForOpenRouterService() {
        let settings = AdvancedChatSettings(venice: VeniceAdvancedSettings(disableThinking: true, stripThinkingResponse: true))
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .openRouter, settings: settings)
        XCTAssertNil(body["venice_parameters"])
    }

    func testProviderObjectOmittedWhenAllRoutingFieldsAreDefault() {
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .openRouter, settings: AdvancedChatSettings())
        XCTAssertNil(body["provider"])
    }

    func testProviderObjectIncludesOnlyNonDefaultRoutingFields() {
        let routing = OpenRouterRoutingPreferences(allowFallbacks: false, dataCollection: .deny, zdr: true)
        let settings = AdvancedChatSettings(openRouterRouting: routing)
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .openRouter, settings: settings)
        let provider = body["provider"] as? [String: Any]
        XCTAssertEqual(provider?["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(provider?["data_collection"] as? String, "deny")
        XCTAssertEqual(provider?["zdr"] as? Bool, true)
    }

    func testProviderObjectNeverSentForVeniceService() {
        let routing = OpenRouterRoutingPreferences(allowFallbacks: false, dataCollection: .deny, zdr: true)
        let settings = AdvancedChatSettings(openRouterRouting: routing)
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, settings: settings)
        XCTAssertNil(body["provider"])
    }

    func testBaseFieldsUnchangedFromPriorStages() {
        let body = ChatRequestBuilder.body(modelID: "llama-3.2-3b", messages: messages, service: .venice)
        XCTAssertEqual(body["model"] as? String, "llama-3.2-3b")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let streamOptions = body["stream_options"] as? [String: Any]
        XCTAssertEqual(streamOptions?["include_usage"] as? Bool, true)
    }

    // MARK: - Stage 7: tools

    func testNoToolsOmitsToolsAndParallelToolCallsFieldsEntirely() {
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice)
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["parallel_tool_calls"])
    }

    func testToolsProducesFunctionDefinitionsAndForcesParallelToolCallsFalse() {
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, tools: [.readFile, .listDirectory])
        let tools = body["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 2)
        XCTAssertEqual(tools?.first?["type"] as? String, "function")
        let function = tools?.first?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "read_file")
        XCTAssertNotNil(function?["parameters"])
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
    }

    func testAssistantMessageWithToolCallsIsEncodedInOpenAICompatibleShape() {
        let toolCall = OutgoingToolCall(id: "call_1", name: "read_file", argumentsJSON: #"{"reason":"why"}"#)
        let assistantMessage = OutgoingChatMessage(role: .assistant, content: "", toolCalls: [toolCall])
        let body = ChatRequestBuilder.body(modelID: "m", messages: [assistantMessage], service: .venice)
        let encodedMessages = body["messages"] as? [[String: Any]]
        let toolCalls = encodedMessages?.first?["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.first?["id"] as? String, "call_1")
        XCTAssertEqual(toolCalls?.first?["type"] as? String, "function")
        let function = toolCalls?.first?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "read_file")
        XCTAssertEqual(function?["arguments"] as? String, #"{"reason":"why"}"#)
    }

    func testToolResultMessageIncludesToolCallID() {
        let toolMessage = OutgoingChatMessage(role: .tool, content: "file contents", toolCallID: "call_1")
        let body = ChatRequestBuilder.body(modelID: "m", messages: [toolMessage], service: .venice)
        let encodedMessages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(encodedMessages?.first?["role"] as? String, "tool")
        XCTAssertEqual(encodedMessages?.first?["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(encodedMessages?.first?["content"] as? String, "file contents")
    }

    func testOrdinaryMessageNeverGetsToolCallsOrToolCallIDFields() {
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice)
        let encodedMessages = body["messages"] as? [[String: Any]]
        XCTAssertNil(encodedMessages?.first?["tool_calls"])
        XCTAssertNil(encodedMessages?.first?["tool_call_id"])
    }
}
