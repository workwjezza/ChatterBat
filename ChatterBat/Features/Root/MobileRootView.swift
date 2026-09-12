import SwiftUI

/// Phone-first navigation shell for iOS.
///
/// The macOS client uses a persistent split view; on iPhone the conversation
/// list is the primary screen and a conversation is pushed onto a navigation
/// stack. This keeps every control reachable with one hand and avoids
/// presenting desktop-width panels inside an iPhone sheet.
struct MobileRootView: View {
    let dependencies: AppDependencies
    @State private var viewModel: AppViewModel
    @State private var modelCatalog: ModelPickerViewModel
    @State private var isOnboardingPresented: Bool
    @State private var isSettingsPresented = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let viewModel = AppViewModel(selectionDefaultsStore: dependencies.modelSelectionDefaultsStore)
        viewModel.busyConversationIDs = { dependencies.chatCoordinator.busyConversationIDs }
        let catalog = dependencies.makeModelPickerViewModel()
        viewModel.attachSelectionCatalog(catalog)
        viewModel.attachRepository(dependencies.conversationRepository, initialConversations: dependencies.initialConversations)
        _viewModel = State(initialValue: viewModel)
        _modelCatalog = State(initialValue: catalog)
        _isOnboardingPresented = State(initialValue: !dependencies.onboardingStateStore.hasCompletedOnboarding())
    }

    var body: some View {
        NavigationStack {
            MobileConversationListView(
                viewModel: viewModel,
                coordinator: dependencies.chatCoordinator,
                onSettings: { isSettingsPresented = true },
                destination: { conversation in
                    ConversationDetailView(
                        conversation: conversation,
                        viewModel: viewModel,
                        session: viewModel.session(for: conversation.id),
                        coordinator: dependencies.chatCoordinator,
                        modelCatalog: modelCatalog
                    )
                    .id(conversation.id)
                }
            )
            .navigationTitle("ChatterBat")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $isSettingsPresented) {
            MobileSettingsView(dependencies: dependencies)
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView(
                onOpenSettings: { isSettingsPresented = true },
                onDismiss: {
                    dependencies.onboardingStateStore.markOnboardingCompleted()
                    isOnboardingPresented = false
                }
            )
        }
        .onChange(of: modelCatalog.catalogStates) { _, _ in
            viewModel.resolveSavedSelection()
        }
        .onChange(of: dependencies.chatCoordinator.transcripts) { old, new in
            let changed = Set(new.keys.filter { old[$0] != new[$0] })
            viewModel.refreshConversationMetadata(conversationIDs: changed)
        }
    }
}

private struct MobileConversationListView<Destination: View>: View {
    var viewModel: AppViewModel
    var coordinator: ChatCoordinator
    let onSettings: () -> Void
    let destination: (Conversation) -> Destination
    @State private var isImportPresented = false
    @State private var exportingConversation: Conversation?
    @State private var isErrorPresented = false

    var body: some View {
        List {
            Section {
                Button {
                    viewModel.startNewConversation()
                } label: {
                    Label("New conversation", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .accessibilityHint("Starts a new chat")
            }

            if coordinator.activeTurnCount > 0 || !coordinator.queuedConversationIDs.isEmpty {
                Section("Activity") {
                    Label(
                        "\(coordinator.activeTurnCount) active · \(coordinator.queuedConversationIDs.count) queued",
                        systemImage: "bolt.horizontal.circle"
                    )
                    if !coordinator.busyConversationIDs.isEmpty {
                        Button("Stop all chats", role: .destructive) {
                            coordinator.stopAllGenerations()
                        }
                    }
                }
            }

            Section("Conversations") {
                if viewModel.filteredConversations.isEmpty {
                    ContentUnavailableView(
                        viewModel.searchText.isEmpty ? "No conversations yet" : "No matches",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(viewModel.searchText.isEmpty
                                          ? "Tap New conversation to start chatting."
                                          : "Try a different search.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.filteredConversations) { conversation in
                        NavigationLink {
                            destination(conversation)
                        } label: {
                            MobileConversationRow(
                                conversation: conversation,
                                activity: executionLabel(for: conversation.id)
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                viewModel.delete(conversation)
                            }
                            .disabled(!viewModel.canDelete(conversation))
                        }
                        .contextMenu {
                            Button("Export…") { exportingConversation = conversation }
                            Button("Delete", role: .destructive) { viewModel.delete(conversation) }
                                .disabled(!viewModel.canDelete(conversation))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        ), prompt: "Search conversations")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { onSettings() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import conversation…", systemImage: "square.and.arrow.down") {
                        isImportPresented = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More conversation actions")
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportingConversation != nil },
                set: { if !$0 { exportingConversation = nil } }
            ),
            document: exportingConversation.flatMap { viewModel.exportData(for: $0) }.map(ConversationExportDocument.init),
            contentType: .json,
            defaultFilename: exportingConversation.map { "\($0.title).chatterbat" }
        ) { result in
            if case .failure = result { isErrorPresented = true }
            exportingConversation = nil
        }
        .fileImporter(isPresented: $isImportPresented, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard let data = try? Data(contentsOf: url), viewModel.importConversation(from: data) else {
                    isErrorPresented = true
                    return
                }
            case .failure:
                isErrorPresented = true
            }
        }
        .alert("Import failed", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.lastExportImportError?.userMessage ?? "The selected file could not be imported.")
        }
    }

    private func executionLabel(for id: UUID) -> String? {
        if let position = coordinator.queuePosition(for: id) { return "Queued · \(position)" }
        let state = coordinator.state(for: id)
        return state == .idle ? nil : state.title
    }
}

private struct MobileConversationRow: View {
    let conversation: Conversation
    let activity: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(conversation.lastMessagePreview.isEmpty ? "No messages yet" : conversation.lastMessagePreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let activity {
                Label(activity, systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}