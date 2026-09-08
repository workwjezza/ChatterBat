import XCTest
@testable import ChatterBat

/// Stage 7: permission-controlled agent tools. Every test here uses
/// `FakeAgentToolPanelPresenter` — never a real `NSOpenPanel` — per
/// the brief's testing contract.
final class ChatCoordinatorAgentToolsTests: XCTestCase {
    private func makeModel(
        service: AIService,
        id: String = "test-model",
        supportsTools: CapabilitySupport = .supported
    ) -> ModelInfo {
        ModelInfo(
            identity: ModelIdentity(service: service, modelID: id),
            displayName: id,
            contextLength: nil,
            maxOutputTokens: nil,
            pricing: .unknown,
            supportsTools: supportsTools,
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

    private func toolCallArgumentsJSON(reason: String) -> String {
        #"{"reason":"\#(reason)"}"#
    }

    @MainActor
    func testToolCallRequestPausesGenerationAwaitingApproval() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: toolCallArgumentsJSON(reason: "need the file")),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: presenter)
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        let pending = coordinator.pendingToolApproval(for: conversationID)
        XCTAssertEqual(pending?.tool, .readFile)
        XCTAssertEqual(pending?.modelStatedReason, "need the file")

        let toolMessage = coordinator.messages(for: conversationID).last
        XCTAssertEqual(toolMessage?.role, .tool)
        XCTAssertEqual(toolMessage?.status, .awaitingApproval)
    }

    @MainActor
    func testModelWithUnsupportedToolsNeverReceivesToolsField() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice, supportsTools: .unsupported)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertEqual(client.receivedTools.last, [])
    }

    @MainActor
    func testUnknownToolSupportIsTreatedAsUnsupportedForRequestSafety() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.finished(reason: "stop")])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client])
        let conversationID = UUID()
        let model = makeModel(service: .venice, supportsTools: .unknown)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertEqual(client.receivedTools.last, [])
    }

    @MainActor
    func testApprovingToolCallRunsExecutorAndSendsFollowUpWithResult() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: toolCallArgumentsJSON(reason: "need it")),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("data.txt")
        try "the answer is 42".write(to: fileURL, atomically: true, encoding: .utf8)
        presenter.urlToReturn = fileURL
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: presenter)
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        client.scriptedEvents = [.contentDelta("The answer is 42."), .finished(reason: "stop")]
        coordinator.respondToToolApproval(in: conversationID, approve: true)
        await waitUntil { coordinator.generationState == .idle }

        let messages = coordinator.messages(for: conversationID)
        let toolMessage = messages.first { $0.role == .tool }
        XCTAssertEqual(toolMessage?.status, .completed)
        XCTAssertEqual(toolMessage?.content, "the answer is 42")
        XCTAssertEqual(toolMessage?.toolInvocation?.approvedItemName, "data.txt")

        let followUpMessages = client.receivedMessages.last ?? []
        XCTAssertTrue(followUpMessages.contains { $0.role == .tool && $0.content == "the answer is 42" })
        XCTAssertTrue(followUpMessages.contains { !$0.toolCalls.isEmpty })

        XCTAssertEqual(messages.last?.content, "The answer is 42.")
        XCTAssertEqual(messages.last?.status, .completed)
    }

    @MainActor
    func testDenyingToolCallNeverPresentsPanelAndMarksToolDenied() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: toolCallArgumentsJSON(reason: "need it")),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = URL(fileURLWithPath: "/should/never/be/used")
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: presenter)
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.respondToToolApproval(in: conversationID, approve: false)
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertEqual(presenter.presentedForTools, [], "Denying must never present the panel.")
        let toolMessage = coordinator.messages(for: conversationID).first { $0.role == .tool }
        XCTAssertEqual(toolMessage?.status, .toolDenied)
    }

    @MainActor
    func testCancellingPanelAfterApprovingIsReportedAsToolDenied() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "list_directory", argumentsFragment: toolCallArgumentsJSON(reason: "need it")),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = nil
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: presenter)
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.listDirectory])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.respondToToolApproval(in: conversationID, approve: true)
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertEqual(presenter.presentedForTools, [.listDirectory])
        let toolMessage = coordinator.messages(for: conversationID).first { $0.role == .tool }
        XCTAssertEqual(toolMessage?.status, .toolDenied)
    }

    @MainActor
    func testStopGenerationWhileAwaitingApprovalDeniesThePendingCall() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: toolCallArgumentsJSON(reason: "need it")),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: presenter)
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.stopGeneration()
        await waitUntil { coordinator.generationState == .idle }

        XCTAssertEqual(presenter.presentedForTools, [], "Stop must deny, never approve, the pending call.")
        let toolMessage = coordinator.messages(for: conversationID).first { $0.role == .tool }
        XCTAssertEqual(toolMessage?.status, .toolDenied)
    }

    @MainActor
    func testSecondSendWhileAwaitingApprovalIsRejected() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: toolCallArgumentsJSON(reason: "need it")),
            .finished(reason: "tool_calls")
        ])
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: FakeAgentToolPanelPresenter())
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        coordinator.send(text: "Second", in: conversationID, using: model, tools: [.readFile])

        let userMessages = coordinator.messages(for: conversationID).filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1, "A send while awaiting tool approval must be rejected.")

        coordinator.respondToToolApproval(in: conversationID, approve: false)
        await waitUntil { coordinator.generationState == .idle }
    }

    @MainActor
    func testToolMessagesAreExcludedFromFutureTurnContext() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("key", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: toolCallArgumentsJSON(reason: "need it")),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        let coordinator = ChatCoordinator(credentialStore: store, clients: [.venice: client], toolPanelPresenter: presenter)
        let conversationID = UUID()
        let model = makeModel(service: .venice)

        coordinator.send(text: "Hello", in: conversationID, using: model, tools: [.readFile])
        await waitUntil { coordinator.generationState == .awaitingToolApproval(conversationID: conversationID) }

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.respondToToolApproval(in: conversationID, approve: false)
        await waitUntil { coordinator.generationState == .idle }

        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.send(text: "Second turn", in: conversationID, using: model)
        await waitUntil { coordinator.generationState == .idle }

        let lastCallMessages = client.receivedMessages.last ?? []
        XCTAssertFalse(lastCallMessages.contains { $0.role == .tool }, "Tool messages must never be replayed as ordinary context.")
    }
}
