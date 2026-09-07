import XCTest
@testable import ChatterBat

final class ChatCoordinatorTests: XCTestCase {
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
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor
    func testSendAppendsUserAndStreamingAssistantMessagesThenCompletes() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .contentDelta("Hi"), .contentDelta(" there"), .finished(reason: "stop")
        ])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        let messages = coordinator.messages(for: conversationID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Hello")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "Hi there")
        XCTAssertEqual(messages[1].status, .completed)
        XCTAssertEqual(messages[1].attribution, model.identity)
    }

    @MainActor
    func testSendWithNoStoredKeyFailsImmediatelyWithoutCallingClient() async {
        let store = InMemoryCredentialStore()
        let client = FakeChatStreamingClient(service: .venice)
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()

        coordinator.send(text: "Hello", in: conversationID, using: makeModel(service: .venice))
        await waitUntil { coordinator.generationState == .idle }

        let messages = coordinator.messages(for: conversationID)
        guard case .failed = messages.last?.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(client.streamCallCount, 0)
    }

    @MainActor
    func testSecondSendWhileGeneratingIsRejected() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.contentDelta("slow")])
        client.delayBetweenEventsNanoseconds = 200_000_000
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "First", in: conversationID, using: model)
        await waitUntil { coordinator.generationState != .idle }
        coordinator.send(text: "Second", in: conversationID, using: model)

        // Only one user message should have been appended — the second
        // send must be a no-op while a generation is active.
        let userMessages = coordinator.messages(for: conversationID).filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.first?.content, "First")

        coordinator.stopGeneration()
        await waitUntil { coordinator.generationState == .idle }
    }

    @MainActor
    func testStopMarksAssistantMessageCancelledAndPreservesPartialContent() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .contentDelta("partial"), .contentDelta(" more"), .finished(reason: "stop")
        ])
        client.delayBetweenEventsNanoseconds = 100_000_000
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()

        coordinator.send(text: "Hello", in: conversationID, using: makeModel(service: .venice))
        await waitUntil { !coordinator.messages(for: conversationID).contains { $0.content.isEmpty && $0.role == .assistant } }
        coordinator.stopGeneration()
        await waitUntil { coordinator.generationState == .idle }

        let assistant = coordinator.messages(for: conversationID).last
        XCTAssertEqual(assistant?.status, .cancelled)
        XCTAssertEqual(assistant?.content, "partial")
    }
}
