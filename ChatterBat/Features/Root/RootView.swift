import SwiftUI

/// Top-level split-view shell.
///
/// Sidebar shows the (currently in-memory/demo) conversation list; the
/// detail pane shows a placeholder conversation surface. Real streaming
/// chat arrives in Stage 3. As of Stage 2, the model picker (⌘K) is real:
/// it fetches live/cached Venice and OpenRouter catalogs and lets the
/// user choose a model for the next message.
struct RootView: View {
    let dependencies: AppDependencies
    @State private var viewModel = AppViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            if let conversation = viewModel.selectedConversation {
                ConversationDetailView(conversation: conversation, viewModel: viewModel)
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
    RootView(
        dependencies: AppDependencies(
            credentialStore: PreviewOnlyStore(),
            veniceChecker: PreviewOnlyChecker(service: .venice),
            openRouterChecker: PreviewOnlyChecker(service: .openRouter),
            veniceCatalogFetcher: PreviewOnlyFetcher(service: .venice),
            openRouterCatalogFetcher: PreviewOnlyFetcher(service: .openRouter),
            modelPreferencesStore: PreviewOnlyPreferences()
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
