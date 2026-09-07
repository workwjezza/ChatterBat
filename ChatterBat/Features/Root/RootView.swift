import SwiftUI

/// Top-level split-view shell.
///
/// Sidebar shows the (currently in-memory/demo) conversation list; the
/// detail pane shows a placeholder conversation surface. Real streaming
/// chat arrives in Stage 3; this view only proves out navigation, keyboard
/// shortcuts, and the model-picker sheet presentation.
struct RootView: View {
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
            ModelPickerPlaceholderView()
        }
        .navigationTitle(viewModel.selectedConversation?.title ?? "ChatterBat")
    }
}

#Preview("Root — Demo Data") {
    RootView()
}
