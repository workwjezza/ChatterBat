import XCTest
@testable import ChatterBat

final class ChatCoordinatorAdvancedSettingsTests: XCTestCase {
    private func makeModel(
        service: AIService,
        id: String = "test-model",
        supportsReasoning: CapabilitySupport = .supported,
        contextLength: Int? = nil
    ) -> ModelInfo {
        ModelInfo(
            identity: ModelIdentity(service: service, modelID: id),
            displayName: id,
            contextLength: contextLength,
            maxOutputTokens: nil,
            pricing: .unknown,
            supportsTools: .unknown,
            supportsReasoning: supportsReasoning,
            supportsVision: .unknown,
            privacyDescription: nil
        )
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor
    func testSendPassesApplicableSettingsThroughToClient() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice, supportsReasoning: .supported)
        let settings = AdvancedChatSettings(reasoningEffort: .high)

        coordinator.send(text: "Hello", in: conversationID, using: model, settings: settings)
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertEqual(client.receivedSettings.last?.reasoningEffort, .high)
    }

    @MainActor
    func testSendDropsInapplicableSettingsBeforeReachingClient() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        // Model does not support reasoning -> reasoningEffort must be
        // dropped before it ever reaches the streaming client.
        let model = makeModel(service: .venice, supportsReasoning: .unsupported)
        let settings = AdvancedChatSettings(reasoningEffort: .high)

        coordinator.send(text: "Hello", in: conversationID, using: model, settings: settings)
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertNil(client.receivedSettings.last?.reasoningEffort)
    }

    @MainActor
    func testContextBoundaryExcludesEarlierMessagesFromNextSend() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "First", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }
        coordinator.send(text: "Second", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        guard let secondUserMessage = coordinator.messages(for: conversationID).first(where: { $0.content == "Second" }) else {
            return XCTFail("Expected to find the second user message")
        }
        coordinator.setContextBoundary(secondUserMessage.id, in: conversationID)

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.send(text: "Third", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        let lastCallMessages = client.receivedMessages.last ?? []
        XCTAssertFalse(lastCallMessages.contains { $0.content == "First" })
        XCTAssertTrue(lastCallMessages.contains { $0.content == "Second" })
        XCTAssertTrue(lastCallMessages.contains { $0.content == "Third" })
    }

    @MainActor
    func testClearingContextBoundaryRestoresFullHistory() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "First", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }
        guard let firstUserMessage = coordinator.messages(for: conversationID).first(where: { $0.content == "First" }) else {
            return XCTFail("Expected to find the first user message")
        }
        coordinator.setContextBoundary(firstUserMessage.id, in: conversationID)
        coordinator.setContextBoundary(nil, in: conversationID)

        XCTAssertNil(coordinator.contextBoundaryMessageID(for: conversationID))

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.send(text: "Second", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        let lastCallMessages = client.receivedMessages.last ?? []
        XCTAssertTrue(lastCallMessages.contains { $0.content == "First" })
    }

    @MainActor
    func testContextBoundaryPersistsThroughRepository() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let repository = InMemoryConversationRepository()
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], repository: repository)
        let conversation = try repository.createConversation(title: "Test")
        let model = makeModel(service: .venice)

        coordinator.send(text: "First", in: conversation.id, using: model)
        await waitUntil { coordinator.generationState == .idle }
        guard let firstUserMessage = coordinator.messages(for: conversation.id).first(where: { $0.content == "First" }) else {
            return XCTFail("Expected to find the first user message")
        }
        coordinator.setContextBoundary(firstUserMessage.id, in: conversation.id)

        XCTAssertEqual(try repository.contextBoundaryMessageID(for: conversation.id), firstUserMessage.id)
    }

    @MainActor
    func testContextUsageEstimateReflectsCurrentBoundary() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice, contextLength: 1000)

        coordinator.send(text: "Hello", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        let estimate = coordinator.contextUsageEstimate(for: conversationID, model: model)
        XCTAssertGreaterThan(estimate.messageCount, 0)
        XCTAssertNotNil(estimate.percentOfContextWindow)
    }
}
