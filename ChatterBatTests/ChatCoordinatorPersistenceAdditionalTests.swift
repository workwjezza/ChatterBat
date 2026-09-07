import XCTest
@testable import ChatterBat

final class ChatCoordinatorPersistenceAdditionalTests: XCTestCase {
    private func makeModel(service: AIService, id: String = "test-model") -> ModelInfo {
        ModelInfo(
            identity: ModelIdentity(service: service, modelID: id),
            displayName: id,
            contextLength: nil,
            maxOutputTokens: nil,
            pricing: .unknown,
            supportsTools: .unknown,
            supportsReasoning: .unknown,
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
    func testMarkInterruptedGenerationsAtLaunchDelegatesToRepository() {
        let store = InMemoryCredentialStore()
        let repository = InMemoryConversationRepository()
        let coordinator = ChatCoordinator(credentialStore: store, clients: [:], repository: repository)

        coordinator.markInterruptedGenerationsAtLaunch()

        XCTAssertEqual(repository.interruptCallCount, 1)
    }

    @MainActor
    func testMessagesLazilyLoadsFromRepositoryOnFirstAccessOnly() throws {
        let store = InMemoryCredentialStore()
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Chat")
        try repository.appendMessage(
            TranscriptMessage(role: .user, content: "existing", status: .completed),
            toConversation: conversation.id
        )
        let coordinator = ChatCoordinator(credentialStore: store, clients: [:], repository: repository)

        let messages = coordinator.messages(for: conversation.id)

        XCTAssertEqual(messages.map(\.content), ["existing"])
    }

    @MainActor
    func testRetryDeletesFailedAndUserMessagesFromRepository() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Chat")
        let client = FakeChatStreamingClient(
            service: .venice,
            scriptedEvents: [],
            errorToThrowAfterEvents: ChatRequestError.providerFailure("boom")
        )
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], repository: repository)
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversation.id, using: model)
        await waitUntil { coordinator.generationState == .idle }
        XCTAssertEqual(try repository.loadMessages(for: conversation.id).count, 2)

        client.scriptedEvents = [.finished(reason: "stop")]
        client.errorToThrowAfterEvents = nil
        coordinator.retryLastTurn(in: conversation.id, using: model)
        await waitUntil { coordinator.generationState == .idle }

        // The original failed pair should have been deleted from the
        // repository (not just the in-memory transcript), leaving one
        // fresh user + one fresh assistant message.
        XCTAssertEqual(repository.deleteMessageCallCount, 2)
        let finalMessages = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(finalMessages.count, 2)
        XCTAssertEqual(finalMessages.first?.content, "Hello")
    }
}
