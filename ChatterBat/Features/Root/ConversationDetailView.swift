import SwiftUI

/// Placeholder conversation surface: a real toolbar model selector (as of
/// Stage 2), an explanatory transcript area, and a disabled composer.
///
/// No message rendering, no streaming, and no chat network calls exist
/// yet — those arrive in Stage 3. The toolbar button opens the real
/// model picker and reflects the current selection's display name and
/// service.
struct ConversationDetailView: View {
    let conversation: Conversation
    var viewModel: AppViewModel
    @State private var draftText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(conversation.title)
                        .font(.title2.bold())
                    Text(conversation.preview)
                        .foregroundStyle(.secondary)
                    Divider()
                    Text(
                        "Streaming chat, model catalogs, and account connection are not " +
                        "implemented yet. This is the Stage 0 shell only."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            ComposerView(text: $draftText)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    viewModel.isModelPickerPresented = true
                } label: {
                    Label(modelButtonTitle, systemImage: "cpu")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Choose a model (⌘K)")
            }
        }
    }

    private var modelButtonTitle: String {
        guard let model = viewModel.selectedModel else { return "Select Model" }
        return "\(model.displayName) · \(model.service.displayName)"
    }
}

/// Bottom composer: multiline input plus Send/Stop.
///
/// Send is disabled in Stage 0 because there is no chat coordinator to send
/// to yet. Shift+Return inserts a newline via the native multiline text
/// field behavior; Return alone is reserved for Send once implemented.
private struct ComposerView: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message (chat not yet implemented)", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .disabled(true)

            Button {
                // Intentionally no-op in Stage 0.
            } label: {
                Label("Send", systemImage: "arrow.up.circle.fill")
            }
            .labelStyle(.iconOnly)
            .disabled(true)
            .help("Sending arrives in Stage 3")
        }
        .padding()
    }
}

#Preview("Conversation Detail") {
    ConversationDetailView(
        conversation: DemoFixtures.conversations[0],
        viewModel: AppViewModel()
    )
}
