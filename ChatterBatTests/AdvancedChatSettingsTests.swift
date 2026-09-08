import XCTest
@testable import ChatterBat

final class AdvancedChatSettingsTests: XCTestCase {
    private func makeModel(
        service: AIService,
        supportsReasoning: CapabilitySupport = .unknown
    ) -> ModelInfo {
        ModelInfo(
            identity: ModelIdentity(service: service, modelID: "test-model"),
            displayName: "Test Model",
            contextLength: nil,
            maxOutputTokens: nil,
            pricing: .unknown,
            supportsTools: .unknown,
            supportsReasoning: supportsReasoning,
            supportsVision: .unknown,
            privacyDescription: nil
        )
    }

    func testDefaultSettingsAreAllNoOpValues() {
        let settings = AdvancedChatSettings()
        XCTAssertNil(settings.reasoningEffort)
        XCTAssertEqual(settings.venice, VeniceAdvancedSettings())
        XCTAssertEqual(settings.openRouterRouting, OpenRouterRoutingPreferences())
    }

    func testReasoningEffortDroppedWhenModelDoesNotSupportReasoning() {
        let settings = AdvancedChatSettings(reasoningEffort: .high)
        let model = makeModel(service: .venice, supportsReasoning: .unsupported)
        let applicable = settings.applicable(to: model)
        XCTAssertNil(applicable.reasoningEffort)
    }

    func testReasoningEffortDroppedWhenSupportIsUnknown() {
        // Unknown must be treated as unsupported for request-safety
        // purposes, even though it is displayed differently in the UI.
        let settings = AdvancedChatSettings(reasoningEffort: .medium)
        let model = makeModel(service: .openRouter, supportsReasoning: .unknown)
        let applicable = settings.applicable(to: model)
        XCTAssertNil(applicable.reasoningEffort)
    }

    func testReasoningEffortPreservedWhenModelSupportsReasoning() {
        let settings = AdvancedChatSettings(reasoningEffort: .low)
        let model = makeModel(service: .venice, supportsReasoning: .supported)
        let applicable = settings.applicable(to: model)
        XCTAssertEqual(applicable.reasoningEffort, .low)
    }

    func testVeniceSettingsDroppedForOpenRouterModel() {
        let settings = AdvancedChatSettings(
            venice: VeniceAdvancedSettings(disableThinking: true, stripThinkingResponse: true)
        )
        let model = makeModel(service: .openRouter, supportsReasoning: .supported)
        let applicable = settings.applicable(to: model)
        XCTAssertEqual(applicable.venice, VeniceAdvancedSettings())
    }

    func testVeniceSettingsDroppedWhenReasoningUnsupportedEvenForVeniceModel() {
        let settings = AdvancedChatSettings(
            venice: VeniceAdvancedSettings(disableThinking: true, stripThinkingResponse: true)
        )
        let model = makeModel(service: .venice, supportsReasoning: .unsupported)
        let applicable = settings.applicable(to: model)
        XCTAssertEqual(applicable.venice, VeniceAdvancedSettings())
    }

    func testVeniceSettingsPreservedForVeniceModelWithReasoningSupport() {
        let settings = AdvancedChatSettings(
            venice: VeniceAdvancedSettings(disableThinking: true, stripThinkingResponse: false)
        )
        let model = makeModel(service: .venice, supportsReasoning: .supported)
        let applicable = settings.applicable(to: model)
        XCTAssertEqual(applicable.venice, VeniceAdvancedSettings(disableThinking: true, stripThinkingResponse: false))
    }

    func testOpenRouterRoutingDroppedForVeniceModel() {
        let settings = AdvancedChatSettings(
            openRouterRouting: OpenRouterRoutingPreferences(allowFallbacks: false, dataCollection: .deny, zdr: true)
        )
        let model = makeModel(service: .venice, supportsReasoning: .supported)
        let applicable = settings.applicable(to: model)
        XCTAssertEqual(applicable.openRouterRouting, OpenRouterRoutingPreferences())
    }

    func testOpenRouterRoutingPreservedForOpenRouterModel() {
        let routing = OpenRouterRoutingPreferences(allowFallbacks: false, dataCollection: .deny, zdr: true)
        let settings = AdvancedChatSettings(openRouterRouting: routing)
        let model = makeModel(service: .openRouter, supportsReasoning: .unknown)
        let applicable = settings.applicable(to: model)
        XCTAssertEqual(applicable.openRouterRouting, routing)
    }
}
