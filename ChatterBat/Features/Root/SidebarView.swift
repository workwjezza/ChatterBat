import SwiftUI

/// Sidebar listing conversations with search, new-chat, rename, and delete.
///
/// Backed by `AppViewModel`'s in-memory demo data in Stage 0. Stage 4 swaps
/// the data source for a SwiftData repository without changing this view's
/// structure.
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
                ContentUnavailableView.search(text: viewModel.searchText)
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
    }
}

#Preview("Sidebar — Demo Data") {
    SidebarView(viewModel: AppViewModel())
        .frame(width: 260)
}

#Preview("Sidebar — Empty") {
    SidebarView(viewModel: AppViewModel(conversations: []))
        .frame(width: 260)
}
