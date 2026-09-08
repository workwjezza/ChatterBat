import XCTest
@testable import ChatterBat

final class ChatRequestBuilderTests: XCTestCase {
    private let messages = [OutgoingChatMessage(role: .user, content: "Hi")]

    func testDefaultSettingsProduceNoAdvancedFields() {
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["venice_parameters"])
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

    func testVeniceParametersOmittedWhenBothFlagsFalse() {
        let settings = AdvancedChatSettings(venice: VeniceAdvancedSettings(disableThinking: false, stripThinkingResponse: false))
        let body = ChatRequestBuilder.body(modelID: "m", messages: messages, service: .venice, settings: settings)
        XCTAssertNil(body["venice_parameters"])
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
}
