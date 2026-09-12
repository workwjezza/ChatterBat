import SwiftUI

/// Sidebar listing conversations with search, new-chat, rename, and delete.
///
/// Backed by `AppViewModel`, which writes through to the SwiftData
/// repository (Stage 4) when one is attached. Distinguishes a genuinely
/// empty conversation list from a search with no matches (Stage 5),
/// since those are different situations for the user.
struct SidebarView: View {
    var viewModel: AppViewModel
    var coordinator: ChatCoordinator? = nil
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var exportingConversation: Conversation?
    @State private var isImportPresented = false
    @State private var isErrorAlertPresented = false

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedConversationID },
            set: { viewModel.selectedConversationID = $0 }
        )) {
            if let coordinator {
                Section("Execution") {
                    Picker("Concurrent chats", selection: Binding(
                        get: { coordinator.maxConcurrentTurns },
                        set: { coordinator.setConcurrencyLimit($0) }
                    )) {
                        ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Text("\(coordinator.activeTurnCount) active · \(coordinator.queuedConversationIDs.count)/\(coordinator.maxQueuedTurns) queued")
                        .font(.caption)
                    Button("Stop all", role: .destructive) { coordinator.stopAllGenerations() }
                        .disabled(coordinator.busyConversationIDs.isEmpty)
                        .help("Cancel active and queued chats without starting tool follow-ups. Upstream billing may still continue.")
                }
            }
            if viewModel.filteredConversations.isEmpty {
                if viewModel.searchText.isEmpty {
                    // Genuinely no conversations yet, as opposed to a
                    // search that matched nothing — these are different
                    // states and should read differently to the user.
                    ContentUnavailableView(
                        "No Conversations Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a new chat with ⌘N.")
                    )
                } else {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            } else {
                ForEach(viewModel.filteredConversations) { conversation in
                    ConversationRow(conversation: conversation,
                                    activity: coordinator.map { executionLabel($0, for: conversation.id) })
                        .tag(conversation.id)
                        .contextMenu {
                            Button("Rename…") {
                                renamingConversation = conversation
                                renameText = conversation.title
                            }
                            Button("Export…") {
                                exportingConversation = conversation
                            }
                            if let coordinator, coordinator.isBusy(conversation.id) {
                                Button("Stop this chat") { coordinator.stopGeneration(in: conversation.id) }
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.delete(conversation)
                            }
                            .disabled(!viewModel.canDelete(conversation))
                        }
                }
            }
        }
        .searchable(text: Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        ), placement: .sidebar, prompt: "Search conversations")
        .navigationTitle("ChatterBat")
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.startNewConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Chat (⌘N)")
                .accessibilityLabel("New Chat")
                .accessibilityHint("Starts a new conversation")
            }
            ToolbarItem {
                Button {
                    isImportPresented = true
                } label: {
                    Label("Import Conversation…", systemImage: "square.and.arrow.down")
                }
                .help("Import a conversation exported from ChatterBat")
                .accessibilityLabel("Import Conversation")
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
            if case .failure = result {
                isErrorAlertPresented = true
            }
            exportingConversation = nil
        }
        .fileImporter(
            isPresented: $isImportPresented,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                guard let data = try? Data(contentsOf: url) else {
                    isErrorAlertPresented = true
                    return
                }
                if !viewModel.importConversation(from: data) {
                    isErrorAlertPresented = true
                }
            case .failure:
                isErrorAlertPresented = true
            }
        }
        .alert(
            "Import Failed",
            isPresented: $isErrorAlertPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.lastExportImportError?.userMessage ?? "Something went wrong with this file.")
        }
        .alert("Rename Conversation", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renamingConversation = nil }
            Button("Rename") {
                if let conversation = renamingConversation {
                    viewModel.rename(conversation, to: renameText)
                }
                renamingConversation = nil
            }
        }
    }

    private func executionLabel(_ coordinator: ChatCoordinator, for id: UUID) -> String {
        if let position = coordinator.queuePosition(for: id) { return "Queued · position \(position)" }
        return coordinator.state(for: id) == .idle ? "" : coordinator.state(for: id).title
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    var activity: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title)
                .font(.body)
                .lineLimit(1)
            Text(conversation.lastMessagePreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let activity, !activity.isEmpty {
                Text(activity).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            conversation.lastMessagePreview.isEmpty
                ? conversation.title
                : "\(conversation.title). \(conversation.lastMessagePreview)"
        )
        .accessibilityValue(activity ?? "")
    }
}

#Preview("Sidebar — Demo Data") {
    SidebarView(viewModel: AppViewModel(conversations: DemoFixtures.conversations))
        .frame(width: 260)
}

#Preview("Sidebar — Empty") {
    SidebarView(viewModel: AppViewModel(conversations: []))
        .frame(width: 260)
}

#Preview("Sidebar — Search No Matches") {
    let viewModel = AppViewModel(conversations: DemoFixtures.conversations)
    viewModel.searchText = "nonexistent query"
    return SidebarView(viewModel: viewModel)
        .frame(width: 260)
}
