import SwiftUI

/// Top-level split-view shell.
///
/// Sidebar shows the (currently in-memory/demo) conversation list. The
/// detail pane hosts real streaming chat as of Stage 3, backed by the
/// shared `ChatCoordinator` in `dependencies`. The model picker (⌘K)
/// fetches live/cached Venice and OpenRouter catalogs and lets the user
/// choose a model for the next message.
struct RootView: View {
    let dependencies: AppDependencies
    @State private var viewModel = AppViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            if let conversation = viewModel.selectedConversation {
                ConversationDetailView(
                    conversation: conversation,
                    viewModel: viewModel,
                    coordinator: dependencies.chatCoordinator
                )
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Choose a conversation from the sidebar, or start a new one.")
                )
            }
        }
        .sheet(isPresented: $viewModel.isModelPickerPresented) {
            ModelPickerView(viewModel: dependencies.makeModelPickerViewModel()) { model in
                viewModel.selectedModel = model
            }
        }
        .navigationTitle(viewModel.selectedConversation?.title ?? "ChatterBat")
    }
}

#Preview("Root — Demo Data") {
    let store = PreviewOnlyStore()
    RootView(
        dependencies: AppDependencies(
            credentialStore: store,
            veniceChecker: PreviewOnlyChecker(service: .venice),
            openRouterChecker: PreviewOnlyChecker(service: .openRouter),
            veniceCatalogFetcher: PreviewOnlyFetcher(service: .venice),
            openRouterCatalogFetcher: PreviewOnlyFetcher(service: .openRouter),
            modelPreferencesStore: PreviewOnlyPreferences(),
            veniceChatClient: PreviewOnlyChatClient(service: .venice),
            openRouterChatClient: PreviewOnlyChatClient(service: .openRouter),
            chatCoordinator: ChatCoordinator(
                credentialStore: store,
                clients: [
                    .venice: PreviewOnlyChatClient(service: .venice),
                    .openRouter: PreviewOnlyChatClient(service: .openRouter)
                ]
            )
        )
    )
}

/// Preview-only doubles. Never referenced by `AppDependencies.live()` or
/// any production path — previews must not touch the real Keychain or
/// network.
private struct PreviewOnlyStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}

private struct PreviewOnlyChecker: ConnectionChecking {
    let service: AIService
    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome { .valid(summary: "preview") }
}

private struct PreviewOnlyFetcher: ModelCatalogFetching {
    let service: AIService
    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome { .success([]) }
}

private final class PreviewOnlyPreferences: ModelPreferencesStore {
    func favoriteIdentities() -> Set<ModelIdentity> { [] }
    func setFavorite(_ identity: ModelIdentity, isFavorite: Bool) {}
    func recentIdentities() -> [ModelIdentity] { [] }
    func recordUsed(_ identity: ModelIdentity) {}
}

private struct PreviewOnlyChatClient: ChatStreamingClient {
    let service: AIService
    func streamChatCompletion(
        apiKey: String,
        modelID: String,
        messages: [OutgoingChatMessage]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
