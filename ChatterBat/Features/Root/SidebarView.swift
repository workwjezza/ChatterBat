import SwiftUI

/// Sidebar listing conversations with search, new-chat, rename, and delete.
///
/// Backed by `AppViewModel`, which writes through to the SwiftData
/// repository (Stage 4) when one is attached. Distinguishes a genuinely
/// empty conversation list from a search with no matches (Stage 5),
/// since those are different situations for the user.
struct SidebarView: View {
    var viewModel: AppViewModel
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedConversationID },
            set: { viewModel.selectedConversationID = $0 }
        )) {
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
                    ConversationRow(conversation: conversation)
                        .tag(conversation.id)
                        .contextMenu {
                            Button("Rename…") {
                                renamingConversation = conversation
                                renameText = conversation.title
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.delete(conversation)
                            }
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
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title)
                .font(.body)
                .lineLimit(1)
            Text(conversation.lastMessagePreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            conversation.lastMessagePreview.isEmpty
                ? conversation.title
                : "\(conversation.title). \(conversation.lastMessagePreview)"
        )
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
