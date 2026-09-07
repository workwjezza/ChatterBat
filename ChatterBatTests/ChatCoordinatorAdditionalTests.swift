import XCTest
@testable import ChatterBat

final class ChatCoordinatorAdditionalTests: XCTestCase {
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
    func testFailedStreamMarksMessageFailedAndAllowsRetry() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(
            service: .venice,
            scriptedEvents: [.contentDelta("oops")],
            errorToThrowAfterEvents: ChatRequestError.providerFailure("boom")
        )
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        guard case .failed = coordinator.messages(for: conversationID).last?.status else {
            return XCTFail("Expected failed status")
        }

        // Retry with a fresh, successful client outcome.
        client.scriptedEvents = [.contentDelta("fixed"), .finished(reason: "stop")]
        client.errorToThrowAfterEvents = nil
        coordinator.retryLastTurn(in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        let messages = coordinator.messages(for: conversationID)
        XCTAssertEqual(messages.filter { $0.role == .user }.count, 1, "Retry must not duplicate the user turn.")
        XCTAssertEqual(messages.last?.content, "fixed")
        XCTAssertEqual(messages.last?.status, .completed)
    }

    @MainActor
    func testTwoConversationsAreFullyIsolated() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let clientA = FakeChatStreamingClient(service: .venice, scriptedEvents: [.contentDelta("A reply"), .finished(reason: "stop")])
        let coordinatorA = ChatCoordinator(credentialStore: store, clients: [.venice: clientA])
        let conversationOne = UUID()
        let conversationTwo = UUID()
        let model = makeModel(service: .venice)

        coordinatorA.send(text: "First conversation", in: conversationOne, using: model)
        await waitUntil { coordinatorA.generationState == .idle }

        XCTAssertFalse(coordinatorA.messages(for: conversationOne).isEmpty)
        XCTAssertTrue(coordinatorA.messages(for: conversationTwo).isEmpty, "A different conversation ID must have no messages.")
    }

    @MainActor
    func testWouldShareHistoryAcrossServicesDetectsSwitchOnlyAfterAMessageExists() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        try store.saveKey("key2", for: .openRouter)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()

        // No messages sent yet: opening the picker / checking must not
        // report a pending cross-service switch.
        XCTAssertFalse(coordinator.wouldShareHistoryAcrossServices(conversationID: conversationID, nextService: .openRouter))

        coordinator.send(text: "Hello", in: conversationID, using: makeModel(service: .venice))
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertTrue(coordinator.wouldShareHistoryAcrossServices(conversationID: conversationID, nextService: .openRouter))
        XCTAssertFalse(
            coordinator.wouldShareHistoryAcrossServices(conversationID: conversationID, nextService: .venice),
            "Staying on the same service must not require disclosure."
        )
    }

    @MainActor
    func testCancelledMessageContentIsExcludedFromNextRequestContext() async throws {
        // Uses multiple delayed events (not just one) so there is a real
        // suspension window between events during which Stop can take
        // effect via cooperative cancellation, before the stream would
        // otherwise finish naturally — a single-event script completes
        // almost immediately and races against the test's own polling.
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(
            service: .venice,
            scriptedEvents: [.contentDelta("partial"), .contentDelta(" more"), .finished(reason: "stop")]
        )
        client.delayBetweenEventsNanoseconds = 150_000_000
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "First", in: conversationID, using: model)
        await waitUntil { !coordinator.messages(for: conversationID).contains { $0.content.isEmpty && $0.role == .assistant } }
        coordinator.stopGeneration()
        await waitUntil { coordinator.generationState == .idle }

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.send(text: "Second", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        // The second call's outgoing messages must include the first user
        // turn (still eligible) but not the cancelled assistant reply.
        let secondCallMessages = client.receivedMessages.last ?? []
        XCTAssertFalse(secondCallMessages.contains { $0.content == "partial" })
        XCTAssertTrue(secondCallMessages.contains { $0.role == .user && $0.content == "First" })
    }

    @MainActor
    func testEmptyTextDoesNotSend() {
        let store = InMemoryCredentialStore()
        let client = FakeChatStreamingClient(service: .venice)
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()

        coordinator.send(text: "   ", in: conversationID, using: makeModel(service: .venice))

        XCTAssertTrue(coordinator.messages(for: conversationID).isEmpty)
        XCTAssertEqual(client.streamCallCount, 0)
    }
}
