import XCTest
@testable import ChatterBat

final class ChatCoordinatorPersistenceTests: XCTestCase {
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
    func testSendPersistsUserAndAssistantMessagesImmediately() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Chat")
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], repository: repository)

        coordinator.send(text: "Hello", in: conversation.id, using: makeModel(service: .venice))

        // Both messages should be persisted synchronously at send-time,
        // before the network call even starts.
        XCTAssertEqual(repository.appendCallCount, 2)
        let persisted = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(persisted.map(\.role), [.user, .assistant])

        await waitUntil { coordinator.generationState == .idle }
    }

    @MainActor
    func testCheckpointIntervalOfOneWritesEveryDelta() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Chat")
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .contentDelta("a"), .contentDelta("b"), .contentDelta("c"), .finished(reason: "stop")
        ])
        let coordinator = ChatCoordinator(
            credentialStore: store,
            clients: [.venice: client],
            repository: repository,
            checkpointInterval: 1
        )

        coordinator.send(text: "Hello", in: conversation.id, using: makeModel(service: .venice))
        await waitUntil { coordinator.generationState == .idle }

        // 3 mid-stream checkpoints (one per delta) + 1 final write on
        // completion = 4 update calls.
        XCTAssertEqual(repository.updateCallCount, 4)
        let final = try repository.loadMessages(for: conversation.id).last
        XCTAssertEqual(final?.content, "abc")
        XCTAssertEqual(final?.status, .completed)
    }

    @MainActor
    func testHighCheckpointIntervalStillWritesFinalStateOnce() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Chat")
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .contentDelta("a"), .contentDelta("b"), .finished(reason: "stop")
        ])
        let coordinator = ChatCoordinator(
            credentialStore: store,
            clients: [.venice: client],
            repository: repository,
            checkpointInterval: 1000
        )

        coordinator.send(text: "Hello", in: conversation.id, using: makeModel(service: .venice))
        await waitUntil { coordinator.generationState == .idle }

        // No mid-stream checkpoint fires (interval never reached), but
        // the final terminal-state write must still happen exactly once.
        XCTAssertEqual(repository.updateCallCount, 1)
        XCTAssertEqual(try repository.loadMessages(for: conversation.id).last?.content, "ab")
    }
}
