import XCTest
@testable import ChatterBat

/// Manually driven streams avoid timing-dependent overlap tests. Every
/// continuation and capture is protected because transport is Sendable.
private final class ControlledChatClient: ChatStreamingClient, @unchecked Sendable {
    let service: AIService = .venice
    private let lock = NSLock()
    private var streams: [String: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation] = [:]
    private var calls: [(String, [OutgoingChatMessage], AdvancedChatSettings, [AgentTool])] = []
    private var terminated: [String] = []

    func streamChatCompletion(apiKey: String, modelID: String, messages: [OutgoingChatMessage],
                              settings: AdvancedChatSettings, tools: [AgentTool]) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            streams[modelID] = continuation
            calls.append((modelID, messages, settings, tools))
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.terminated.append(modelID)
                self.lock.unlock()
            }
        }
    }

    var started: [String] { lock.withLock { calls.map { $0.0 } } }
    var stopped: [String] { lock.withLock { terminated } }
    func messages(_ id: String) -> [OutgoingChatMessage]? { lock.withLock { calls.last { $0.0 == id }?.1 } }
    func settings(_ id: String) -> AdvancedChatSettings? { lock.withLock { calls.last { $0.0 == id }?.2 } }
    func tools(_ id: String) -> [AgentTool]? { lock.withLock { calls.last { $0.0 == id }?.3 } }
    func yield(_ id: String, _ event: ChatStreamEvent) { lock.withLock { streams[id] }?.yield(event) }
    func finish(_ id: String, error: Error? = nil) { lock.withLock { streams[id] }?.finish(throwing: error) }
}

@MainActor
private final class BlockingPanel: AgentToolPanelPresenting {
    var count = 0
    var waiting: CheckedContinuation<URL?, Never>?
    func presentPanel(for tool: AgentTool) async -> URL? {
        count += 1
        return await withCheckedContinuation { waiting = $0 }
    }
    func release(_ url: URL? = nil) { waiting?.resume(returning: url); waiting = nil }
}

@MainActor
final class ChatConcurrencyTests: XCTestCase {
    private func model(_ id: String) -> ModelInfo {
        ModelInfo(identity: ModelIdentity(service: .venice, modelID: id), displayName: id,
                  contextLength: 32_000, maxOutputTokens: nil, pricing: .unknown,
                  supportsTools: .supported, supportsReasoning: .supported,
                  supportsVision: .unsupported, privacyDescription: "private")
    }

    private func fixture(limit: Int = 2, queue: Int = 8, repository: ConversationRepository? = nil,
                         panel: AgentToolPanelPresenting = FakeAgentToolPanelPresenter()) throws
        -> (ChatCoordinator, ControlledChatClient, InMemoryCredentialStore) {
        let keys = InMemoryCredentialStore()
        try keys.saveKey("fixture", for: .venice)
        let client = ControlledChatClient()
        let coordinator = ChatCoordinator(credentialStore: keys, clients: [.venice: client], repository: repository,
                                          toolPanelPresenter: panel, maxConcurrentTurns: limit, maxQueuedTurns: queue)
        return (coordinator, client, keys)
    }

    private func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for controlled execution")
    }

    func testTwoStreamsOverlapAndCancelOnlyTheirOwner() async throws {
        let (coordinator, client, _) = try fixture()
        let a = UUID(), b = UUID()
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"))
        await wait { client.started.count == 2 }
        XCTAssertEqual(coordinator.activeTurnCount, 2)
        client.yield("a", .contentDelta("partial A"))
        client.yield("b", .contentDelta("partial B"))
        await wait { coordinator.messages(for: a).last?.content == "partial A" }
        coordinator.stopGeneration(in: a)
        await wait { !coordinator.isBusy(a) }
        XCTAssertTrue(coordinator.isBusy(b))
        XCTAssertTrue(client.stopped.contains("a"))
        client.yield("a", .contentDelta("late ignored"))
        client.yield("b", .contentDelta(" finished"))
        client.finish("b")
        await wait { coordinator.busyConversationIDs.isEmpty }
        XCTAssertEqual(coordinator.messages(for: a).last?.content, "partial A")
        XCTAssertEqual(coordinator.messages(for: a).last?.status, .cancelled)
        XCTAssertEqual(coordinator.messages(for: b).last?.content, "partial B finished")
        XCTAssertEqual(coordinator.messages(for: b).last?.status, .completed)
    }

    func testFIFOAndQueueCapRejectWithoutTranscriptMutation() async throws {
        let (coordinator, client, _) = try fixture(limit: 1, queue: 2)
        let a = UUID(), b = UUID(), c = UUID(), rejected = UUID()
        XCTAssertTrue(coordinator.send(text: "A", in: a, using: model("a")))
        XCTAssertTrue(coordinator.send(text: "B", in: b, using: model("b")))
        XCTAssertTrue(coordinator.send(text: "C", in: c, using: model("c")))
        XCTAssertFalse(coordinator.send(text: "Full", in: rejected, using: model("x")))
        XCTAssertFalse(coordinator.send(text: "Duplicate", in: b, using: model("b")))
        XCTAssertTrue(coordinator.messages(for: rejected).isEmpty)
        XCTAssertEqual(coordinator.queuePosition(for: b), 1)
        XCTAssertEqual(coordinator.queuePosition(for: c), 2)
        await wait { client.started == ["a"] }
        client.finish("a")
        await wait { client.started == ["a", "b"] }
        XCTAssertEqual(coordinator.queuePosition(for: c), 1)
        client.finish("b")
        await wait { client.started == ["a", "b", "c"] }
        client.finish("c")
        await wait { coordinator.busyConversationIDs.isEmpty }
    }

    func testQueuedCancellationNeverStartsProviderAndKeepsSubmittedPrompt() async throws {
        let (coordinator, client, _) = try fixture(limit: 1)
        let a = UUID(), b = UUID()
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "Queued prompt", in: b, using: model("b"))
        coordinator.stopGeneration(in: b)
        XCTAssertFalse(coordinator.isBusy(b))
        XCTAssertEqual(coordinator.messages(for: b).first?.content, "Queued prompt")
        XCTAssertEqual(coordinator.messages(for: b).last?.status, .cancelled)
        await wait { client.started == ["a"] }
        client.finish("a")
        await wait { coordinator.busyConversationIDs.isEmpty }
        XCTAssertEqual(client.started, ["a"])
    }

    func testStopAllDoesNotDrainQueueOrSendApprovalFollowup() async throws {
        let (coordinator, client, _) = try fixture()
        let a = UUID(), b = UUID(), c = UUID()
        coordinator.send(text: "A", in: a, using: model("a"), tools: [.readFile])
        coordinator.send(text: "B", in: b, using: model("b"))
        coordinator.send(text: "C", in: c, using: model("c"))
        await wait { client.started.count == 2 }
        client.yield("a", .toolCallDelta(index: 0, id: "call", name: "read_file", argumentsFragment: "{}"))
        client.finish("a")
        await wait { coordinator.pendingToolApproval(for: a) != nil }
        coordinator.stopAllGenerations()
        await wait { coordinator.busyConversationIDs.isEmpty }
        XCTAssertEqual(Set(client.started), ["a", "b"])
        XCTAssertEqual(client.started.count, 2)
        XCTAssertEqual(coordinator.messages(for: a).last?.status, .toolDenied)
        XCTAssertEqual(coordinator.messages(for: c).last?.status, .cancelled)
    }

    func testApprovalHoldsOnlyItsOwnSlotAndDenialContinuesOnlyOwner() async throws {
        let (coordinator, client, _) = try fixture()
        let a = UUID(), b = UUID(), c = UUID()
        coordinator.send(text: "A", in: a, using: model("a"), tools: [.readFile])
        coordinator.send(text: "B", in: b, using: model("b"))
        coordinator.send(text: "C", in: c, using: model("c"))
        await wait { client.started.count == 2 }
        client.yield("a", .toolCallDelta(index: 0, id: "call", name: "read_file", argumentsFragment: "{}"))
        client.finish("a")
        await wait { coordinator.pendingToolApproval(for: a) != nil }
        XCTAssertEqual(coordinator.queuePosition(for: c), 1)
        client.finish("b")
        await wait { client.started.contains("c") }
        coordinator.respondToToolApproval(in: a, approve: false, expectedToolCallID: "call")
        await wait { client.started.filter { $0 == "a" }.count == 2 }
        XCTAssertEqual(client.messages("a")?.last?.role, .tool)
        client.finish("a")
        client.finish("c")
        await wait { coordinator.busyConversationIDs.isEmpty }
    }

    func testQueueCapturesContextSettingsToolsAndModelBeforeDispatch() async throws {
        let (coordinator, client, _) = try fixture(limit: 1)
        let a = UUID(), b = UUID()
        var settings = AdvancedChatSettings(reasoningEffort: .high)
        coordinator.send(text: "Block", in: a, using: model("a"))
        coordinator.send(text: "Original", in: b, using: model("b"), settings: settings, tools: [.readFile])
        settings.reasoningEffort = .low
        coordinator.setContextBoundary(UUID(), in: b)
        await wait { client.started.count == 1 }
        client.finish("a")
        await wait { client.started.count == 2 }
        XCTAssertEqual(client.messages("b")?.map(\.content), ["Original"])
        XCTAssertEqual(client.settings("b")?.reasoningEffort, .high)
        XCTAssertEqual(client.tools("b"), [.readFile])
        client.finish("b")
        await wait { coordinator.busyConversationIDs.isEmpty }
    }

    func testDispatchValidationFailureSkipsProviderAndDrainsNext() async throws {
        let (coordinator, client, _) = try fixture(limit: 1)
        let a = UUID(), b = UUID(), c = UUID()
        var valid = true
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"), validateBeforeStart: { valid ? nil : "Policy expired" })
        coordinator.send(text: "C", in: c, using: model("c"))
        valid = false
        await wait { client.started == ["a"] }
        client.finish("a")
        await wait { client.started == ["a", "c"] }
        XCTAssertEqual(coordinator.messages(for: b).last?.status, .failed("Policy expired"))
        client.finish("c")
        await wait { coordinator.busyConversationIDs.isEmpty }
    }

    func testRemovedCredentialAtDispatchPreventsQueuedNetworkCall() async throws {
        let (coordinator, client, keys) = try fixture(limit: 1)
        let a = UUID(), b = UUID()
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"))
        await wait { client.started == ["a"] }
        try keys.deleteKey(for: .venice)
        client.finish("a")
        await wait { coordinator.busyConversationIDs.isEmpty }
        XCTAssertEqual(client.started, ["a"])
        guard case .failed = coordinator.messages(for: b).last?.status else { return XCTFail("Expected credential failure") }
    }

    func testLimitChangesAreClampedAndDoNotCancelAdmittedTurns() async throws {
        let (coordinator, client, _) = try fixture(limit: 1)
        let a = UUID(), b = UUID(), c = UUID()
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"))
        coordinator.send(text: "C", in: c, using: model("c"))
        coordinator.setConcurrencyLimit(2)
        await wait { client.started.count == 2 }
        coordinator.setConcurrencyLimit(0)
        XCTAssertEqual(coordinator.maxConcurrentTurns, 1)
        XCTAssertEqual(coordinator.activeTurnCount, 2)
        client.finish("a")
        await wait { !coordinator.isBusy(a) }
        XCTAssertEqual(client.started.count, 2)
        client.finish("b")
        await wait { client.started.count == 3 }
        coordinator.setConcurrencyLimit(99)
        XCTAssertEqual(coordinator.maxConcurrentTurns, 4)
        client.finish("c")
        await wait { coordinator.busyConversationIDs.isEmpty }
    }

    func testPersistenceRecoversAllUnfinishedQueuedAndActiveMessages() async throws {
        let repository = InMemoryConversationRepository()
        let a = try repository.createConversation(title: "A").id
        let b = try repository.createConversation(title: "B").id
        let (coordinator, client, keys) = try fixture(limit: 1, repository: repository)
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"))
        await wait { client.started.count == 1 }
        let recovered = ChatCoordinator(credentialStore: keys, clients: [.venice: client], repository: repository)
        recovered.markInterruptedGenerationsAtLaunch()
        XCTAssertEqual(recovered.messages(for: a).last?.status, .interrupted)
        XCTAssertEqual(recovered.messages(for: b).last?.status, .interrupted)
        XCTAssertTrue(recovered.busyConversationIDs.isEmpty)
        XCTAssertEqual(client.started.count, 1, "Recovery must not resume queued requests.")
        coordinator.stopAllGenerations()
        await wait { coordinator.busyConversationIDs.isEmpty }
    }

    func testPanelSerializationAndCancellationDiscardsLateSelection() async throws {
        let panel = BlockingPanel()
        let (coordinator, client, _) = try fixture(panel: panel)
        let a = UUID(), b = UUID()
        coordinator.send(text: "A", in: a, using: model("a"), tools: [.readFile])
        coordinator.send(text: "B", in: b, using: model("b"), tools: [.readFile])
        await wait { client.started.count == 2 }
        for id in ["a", "b"] {
            client.yield(id, .toolCallDelta(index: 0, id: id, name: "read_file", argumentsFragment: "{}"))
            client.finish(id)
        }
        await wait { coordinator.pendingToolApproval(for: a) != nil && coordinator.pendingToolApproval(for: b) != nil }
        coordinator.respondToToolApproval(in: a, approve: true)
        await wait { panel.count == 1 }
        coordinator.respondToToolApproval(in: b, approve: true)
        coordinator.stopGeneration(in: b)
        await wait { !coordinator.isBusy(b) }
        XCTAssertEqual(panel.count, 1)
        coordinator.stopGeneration(in: a)
        XCTAssertEqual(coordinator.state(for: a), .cancelling(conversationID: a))
        panel.release(URL(fileURLWithPath: "/must/not/read/after/cancellation"))
        await wait { coordinator.busyConversationIDs.isEmpty }
        XCTAssertEqual(client.started.count, 2, "No cancelled tool follow-up request")
        XCTAssertEqual(coordinator.messages(for: a).last?.status, .toolDenied)
    }

    func testImmediateStopBeforeTaskStartsAndLaterReplacementDoNotOverlap() async throws {
        let (coordinator, client, _) = try fixture()
        let a = UUID()
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.stopGeneration(in: a)
        XCTAssertFalse(coordinator.send(text: "Too soon", in: a, using: model("new")))
        await wait { !coordinator.isBusy(a) }
        XCTAssertTrue(client.started.isEmpty)
        XCTAssertTrue(coordinator.send(text: "Replacement", in: a, using: model("new")))
        await wait { client.started == ["new"] }
        client.yield("new", .contentDelta("new result"))
        client.finish("new")
        await wait { !coordinator.isBusy(a) }
        XCTAssertEqual(coordinator.messages(for: a).last?.content, "new result")
    }

    func testFailureAndExplicitRetryDoNotStopOtherConversation() async throws {
        let (coordinator, client, _) = try fixture()
        let a = UUID(), b = UUID()
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"))
        await wait { client.started.count == 2 }
        client.finish("a", error: ChatRequestError.offlineOrTimeout("fixture failure"))
        await wait { !coordinator.isBusy(a) }
        XCTAssertTrue(coordinator.isBusy(b))
        XCTAssertEqual(client.started.count, 2, "No automatic retry")
        coordinator.retryLastTurn(in: a, using: model("retry"))
        await wait { client.started.contains("retry") }
        XCTAssertTrue(coordinator.isBusy(b))
        client.finish("retry")
        client.finish("b")
        await wait { coordinator.busyConversationIDs.isEmpty }
        XCTAssertEqual(coordinator.messages(for: a).filter { $0.role == .user }.count, 1)
    }

    func testAllBusyChatsIncludingQueueAreProtectedFromDeletion() async throws {
        let (coordinator, client, _) = try fixture(limit: 1)
        let conversations = [Conversation(title: "A"), Conversation(title: "B")]
        let app = AppViewModel(conversations: conversations)
        app.busyConversationIDs = { coordinator.busyConversationIDs }
        coordinator.send(text: "A", in: conversations[0].id, using: model("a"))
        coordinator.send(text: "B", in: conversations[1].id, using: model("b"))
        for conversation in conversations {
            XCTAssertFalse(app.canDelete(conversation))
            app.delete(conversation)
        }
        XCTAssertEqual(app.conversations.count, 2)
        await wait { client.started == ["a"] }
        coordinator.stopAllGenerations()
        await wait { coordinator.busyConversationIDs.isEmpty }
        for conversation in conversations { XCTAssertTrue(app.canDelete(conversation)) }
    }

    func testConcurrentCompletedUsagePersistsToCorrectConversation() async throws {
        let repository = InMemoryConversationRepository()
        let a = try repository.createConversation(title: "A").id
        let b = try repository.createConversation(title: "B").id
        let (coordinator, client, _) = try fixture(repository: repository)
        coordinator.send(text: "A", in: a, using: model("a"))
        coordinator.send(text: "B", in: b, using: model("b"))
        await wait { client.started.count == 2 }
        client.yield("b", .contentDelta("B result"))
        client.yield("a", .contentDelta("A result"))
        client.yield("b", .usage(ChatUsage(promptTokens: 2, completionTokens: 3, totalTokens: 5)))
        client.yield("a", .usage(ChatUsage(promptTokens: 7, completionTokens: 11, totalTokens: 18)))
        client.finish("a")
        client.finish("b")
        await wait { coordinator.busyConversationIDs.isEmpty }
        let savedA = try repository.loadMessages(for: a).last
        let savedB = try repository.loadMessages(for: b).last
        XCTAssertEqual(savedA?.content, "A result")
        XCTAssertEqual(savedA?.usage?.totalTokens, 18)
        XCTAssertEqual(savedA?.attribution, model("a").identity)
        XCTAssertEqual(savedB?.content, "B result")
        XCTAssertEqual(savedB?.usage?.totalTokens, 5)
        XCTAssertEqual(savedB?.attribution, model("b").identity)
    }
}