import XCTest
@testable import ChatterBat

@MainActor
final class ConversationSessionStateTests: XCTestCase {
    private func model(_ id: String, price: Decimal = 2) -> ModelInfo {
        ModelInfo(identity: ModelIdentity(service: .venice, modelID: id), displayName: id,
                  contextLength: 32_000, maxOutputTokens: nil,
                  pricing: ModelPricing(inputPerMillionTokensUSD: price, outputPerMillionTokensUSD: price),
                  supportsTools: .supported, supportsReasoning: .supported,
                  supportsVision: .unsupported, privacyDescription: "private")
    }

    private func fixture() async throws -> (AppViewModel, ModelPickerViewModel, FakeModelCatalogFetcher) {
        let credentials = InMemoryCredentialStore()
        try credentials.saveKey("fixture", for: .venice)
        let fetcher = FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([model("a"), model("b", price: 9)]))
        let catalog = ModelPickerViewModel(credentialStore: credentials, fetchers: [.venice: fetcher],
                                           preferencesStore: InMemoryModelPreferencesStore())
        await catalog.refresh(.venice)
        catalog.toggleFavorite(model("a").identity)
        catalog.toggleFavorite(model("b").identity)
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.togglePinnedDefault(model("a").identity, isBusy: false)
        app.startNewConversation()
        return (app, catalog, fetcher)
    }

    func testSwitchingRestoresDraftModelAndSettingsByIdentity() async throws {
        let (app, _, _) = try await fixture()
        let firstID = try XCTUnwrap(app.selectedConversationID)
        let first = app.currentSession
        first.draftText = "First unsent draft"
        first.advancedChatSettings.reasoningEffort = .high
        first.agentToolsEnabled = true
        app.startNewConversation()
        let second = app.currentSession
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.draftText, "")
        XCTAssertNil(second.advancedChatSettings.reasoningEffort)
        XCTAssertFalse(second.agentToolsEnabled)
        second.draftText = "Second unsent draft"
        app.selectCurrentModel(model("b"), isBusy: false)
        app.selectedConversationID = firstID
        XCTAssertTrue(app.currentSession === first)
        XCTAssertEqual(app.selectedModel?.modelID, "a")
        XCTAssertEqual(first.draftText, "First unsent draft")
        XCTAssertEqual(app.advancedChatSettings.reasoningEffort, .high)
        XCTAssertEqual(app.toolsToOffer, AgentTool.allCases)
        XCTAssertEqual(second.draftText, "Second unsent draft")
    }

    func testCapturedBindingTargetCannotWriteIntoNewlySelectedChat() async throws {
        let (app, _, _) = try await fixture()
        let captured = app.currentSession
        app.startNewConversation()
        let selected = app.currentSession
        captured.draftText = "Late old-editor callback"
        captured.advancedChatSettings.venice.disableThinking = true
        XCTAssertEqual(selected.draftText, "")
        XCTAssertFalse(selected.advancedChatSettings.venice.disableThinking)
    }

    func testNewPinAffectsCurrentAndFutureButNotExistingChatsAfterRefresh() async throws {
        let (app, catalog, _) = try await fixture()
        let firstID = try XCTUnwrap(app.selectedConversationID)
        let first = app.currentSession
        app.startNewConversation()
        app.togglePinnedDefault(model("b").identity, isBusy: false)
        XCTAssertEqual(app.selectedModel?.modelID, "b")
        await catalog.refresh(.venice)
        app.resolveSavedSelection()
        app.selectedConversationID = firstID
        XCTAssertTrue(app.currentSession === first)
        XCTAssertEqual(app.selectedModel?.modelID, "a")
        app.startNewConversation()
        XCTAssertEqual(app.selectedModel?.modelID, "b")
    }

    func testAutoPolicySnapshotSurvivesOtherChatsSavingNewPolicy() async throws {
        let (app, catalog, _) = try await fixture()
        app.saveAutoPolicyFromCurrentModel(isBusy: false)
        let firstID = try XCTUnwrap(app.selectedConversationID)
        let first = app.currentSession
        let policy = try XCTUnwrap(first.autoPolicy)
        app.startNewConversation()
        app.selectCurrentModel(model("b", price: 9), isBusy: false)
        app.saveAutoPolicyFromCurrentModel(isBusy: false)
        XCTAssertEqual(app.modelDefaults.autoPolicy?.anchor.modelID, "b")
        await catalog.refresh(.venice)
        app.resolveSavedSelection()
        XCTAssertEqual(first.autoPolicy, policy)
        app.selectedConversationID = firstID
        XCTAssertTrue(app.autoModeEnabled)
        XCTAssertEqual(app.selectedModel?.modelID, "a")
        app.setCurrentAutoEnabled(false, isBusy: false)
        app.setCurrentAutoEnabled(true, isBusy: false)
        XCTAssertEqual(app.currentSession.autoPolicy, policy)
        XCTAssertEqual(app.selectedModel?.modelID, "a")
    }

    func testUnavailableIdentityRecoversWithoutAdoptingNewDefault() async throws {
        let (app, catalog, fetcher) = try await fixture()
        let first = app.currentSession
        app.startNewConversation()
        app.togglePinnedDefault(model("b").identity, isBusy: false)
        fetcher.outcomeToReturn = .success([model("b")])
        await catalog.refresh(.venice)
        app.resolveSavedSelection()
        XCTAssertNil(first.selectedModel)
        XCTAssertEqual(first.selectedIdentity?.modelID, "a")
        fetcher.outcomeToReturn = .success([model("a"), model("b")])
        await catalog.refresh(.venice)
        app.resolveSavedSelection()
        XCTAssertEqual(first.selectedModel?.modelID, "a")
    }

    func testDeletionDropsOnlyDeletedSessionAndBlocksActiveChat() async throws {
        let (app, _, _) = try await fixture()
        let firstConversation = try XCTUnwrap(app.selectedConversation)
        weak var deletedSession = app.currentSession
        app.startNewConversation()
        let second = app.currentSession
        second.draftText = "Keep"
        app.activeConversationID = { firstConversation.id }
        app.delete(firstConversation)
        XCTAssertNotNil(deletedSession)
        XCTAssertEqual(app.conversations.count, 2)
        app.activeConversationID = { nil }
        app.delete(firstConversation)
        XCTAssertNil(deletedSession)
        XCTAssertTrue(app.currentSession === second)
        XCTAssertEqual(second.draftText, "Keep")
        XCTAssertEqual(app.conversations.count, 1)
    }

    func testRepositoryCreationAndImportStartIndependentSessions() async throws {
        let (app, _, _) = try await fixture()
        let repository = InMemoryConversationRepository()
        app.attachRepository(repository, initialConversations: [])
        app.startNewConversation()
        let firstID = try XCTUnwrap(app.selectedConversationID)
        let first = app.currentSession
        first.draftText = "Local only"
        let export = ConversationExportCoding.export(conversation: Conversation(title: "Imported"), messages: [])
        XCTAssertTrue(app.importConversation(from: try ConversationExportCoding.encode(export)))
        XCTAssertFalse(app.currentSession === first)
        XCTAssertEqual(app.currentSession.draftText, "")
        XCTAssertEqual(app.selectedModel?.modelID, "a")
        app.selectedConversationID = firstID
        XCTAssertTrue(app.currentSession === first)
        let exported = try XCTUnwrap(app.exportData(for: try XCTUnwrap(app.selectedConversation)))
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("Local only"))
    }

    func testNoConversationSetupDoesNotReusePreviousDraft() async throws {
        let (app, _, _) = try await fixture()
        let id = app.selectedConversationID
        app.currentSession.draftText = "Private draft"
        app.selectedConversationID = nil
        XCTAssertEqual(app.currentSession.draftText, "")
        app.selectedConversationID = id
        XCTAssertEqual(app.currentSession.draftText, "Private draft")
    }

    func testMetadataRefreshDoesNotChangeSessionSelectionOrDraft() async throws {
        let repository = InMemoryConversationRepository()
        let first = try repository.createConversation(title: "First")
        let second = try repository.createConversation(title: "Second")
        let app = AppViewModel()
        app.loadFromRepository(repository)
        app.selectedConversationID = second.id
        let session = app.currentSession
        session.draftText = "Keep"
        try repository.appendMessage(TranscriptMessage(role: .assistant, content: "Background result", status: .completed), toConversation: first.id)
        app.refreshConversationMetadata(conversationIDs: [first.id])
        XCTAssertEqual(app.selectedConversationID, second.id)
        XCTAssertTrue(app.currentSession === session)
        XCTAssertEqual(session.draftText, "Keep")
        XCTAssertEqual(app.conversations.first(where: { $0.id == first.id })?.lastMessagePreview, "Background result")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for fixture stream")
    }

    func testSwitchingWhileStreamingPreservesRequestAndOnlyUpdatesOwningTranscript() async throws {
        let (app, _, _) = try await fixture()
        let firstID = try XCTUnwrap(app.selectedConversationID)
        let first = app.currentSession
        first.draftText = "First request"
        first.advancedChatSettings.reasoningEffort = .high
        let credentials = InMemoryCredentialStore()
        try credentials.saveKey("fixture", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [.contentDelta("answer"), .finished(reason: "stop")])
        client.delayBetweenEventsNanoseconds = 30_000_000
        let coordinator = ChatCoordinator(credentialStore: credentials, clients: [.venice: client])
        coordinator.send(text: first.draftText, in: firstID, using: try XCTUnwrap(first.selectedModel), settings: first.effectiveChatSettings)
        first.draftText = ""
        app.startNewConversation()
        let secondID = try XCTUnwrap(app.selectedConversationID)
        let second = app.currentSession
        second.draftText = "Do not send"
        await waitUntil { coordinator.generationState == .idle }
        XCTAssertEqual(client.receivedMessages.first?.last?.content, "First request")
        XCTAssertEqual(client.receivedSettings.first?.reasoningEffort, .high)
        XCTAssertEqual(coordinator.messages(for: firstID).last?.content, "answer")
        XCTAssertTrue(coordinator.messages(for: secondID).isEmpty)
        XCTAssertEqual(second.draftText, "Do not send")
        XCTAssertEqual(client.streamCallCount, 1)
    }

    func testApprovalRemainsOwnedAndDuplicateDecisionIsIgnored() async throws {
        let (app, _, _) = try await fixture()
        let firstID = try XCTUnwrap(app.selectedConversationID)
        let first = app.currentSession
        first.agentToolsEnabled = true
        first.advancedChatSettings.reasoningEffort = .high
        let credentials = InMemoryCredentialStore()
        try credentials.saveKey("fixture", for: .venice)
        let client = FakeChatStreamingClient(service: .venice, scriptedEvents: [
            .toolCallDelta(index: 0, id: "call", name: "read_file", argumentsFragment: "{\"reason\":\"inspect\"}"),
            .finished(reason: "tool_calls")
        ])
        let presenter = FakeAgentToolPanelPresenter()
        let coordinator = ChatCoordinator(credentialStore: credentials, clients: [.venice: client], toolPanelPresenter: presenter)
        coordinator.send(text: "Inspect", in: firstID, using: try XCTUnwrap(first.selectedModel),
                         settings: first.effectiveChatSettings, tools: first.toolsToOffer)
        await waitUntil { coordinator.pendingToolApproval(for: firstID) != nil }
        app.startNewConversation()
        let secondID = try XCTUnwrap(app.selectedConversationID)
        app.currentSession.draftText = "Another chat"
        coordinator.respondToToolApproval(in: secondID, approve: true)
        coordinator.respondToToolApproval(in: firstID, approve: true, expectedToolCallID: "stale-call")
        XCTAssertNotNil(coordinator.pendingToolApproval(for: firstID))
        XCTAssertNil(coordinator.pendingToolApproval(for: secondID))
        client.scriptedEvents = [.finished(reason: "stop")]
        coordinator.respondToToolApproval(in: firstID, approve: false)
        coordinator.respondToToolApproval(in: firstID, approve: true)
        await waitUntil { coordinator.generationState == .idle }
        XCTAssertTrue(presenter.presentedForTools.isEmpty)
        XCTAssertEqual(client.streamCallCount, 2)
        XCTAssertEqual(client.receivedSettings.last?.reasoningEffort, .high)
        XCTAssertEqual(client.receivedTools.last, AgentTool.allCases)
        XCTAssertTrue(coordinator.messages(for: secondID).isEmpty)
        XCTAssertEqual(app.currentSession.draftText, "Another chat")
    }

    func testUnopenedLoadedChatKeepsInitialDefaultSnapshot() async throws {
        let (app, _, _) = try await fixture()
        let repository = InMemoryConversationRepository()
        let first = try repository.createConversation(title: "First")
        let unopened = try repository.createConversation(title: "Unopened")
        app.attachRepository(repository, initialConversations: [first, unopened])
        app.togglePinnedDefault(model("b").identity, isBusy: false)
        app.selectedConversationID = unopened.id
        XCTAssertEqual(app.selectedModel?.modelID, "a")
    }

    func testSessionDraftsAreDeliberatelyNotRestoredAcrossAppInstances() async throws {
        let (app, catalog, _) = try await fixture()
        let conversation = try XCTUnwrap(app.selectedConversation)
        app.currentSession.draftText = "Not durable yet"
        app.agentToolsEnabled = true
        let relaunched = AppViewModel(conversations: [conversation])
        relaunched.attachSelectionCatalog(catalog)
        XCTAssertEqual(relaunched.currentSession.draftText, "")
        XCTAssertFalse(relaunched.agentToolsEnabled)
        XCTAssertFalse(relaunched.currentSession === app.currentSession)
    }
}