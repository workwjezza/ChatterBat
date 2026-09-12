import SwiftUI

/// Bottom composer: multiline input plus Send/Stop.
///
/// Return sends, Shift+Return inserts a newline, and Command+Return also
/// sends while the editor is focused. Native input-method composition is
/// handled by the editor before any send action is considered.
struct ComposerView: View {
    @Binding var text: String
    let isGenerating: Bool
    let canSend: Bool
    /// Whether a model has been selected — used only to choose a more
    /// helpful placeholder/hint; the actual Send-eligibility gate is
    /// still `canSend`, set by the caller.
    let hasSelectedModel: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    var willQueue = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ComposerTextEditor(text: $text, isEditable: !isGenerating, canSend: canSend, onSend: onSend)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

            if isGenerating {
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .labelStyle(.iconOnly)
                .help("Stop this chat or remove its queued turn (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: onSend) {
                    Label(willQueue ? "Queue" : "Send", systemImage: willQueue ? "clock.arrow.circlepath" : "arrow.up.circle.fill")
                }
                .labelStyle(.iconOnly)
                .disabled(!canSend)
                .help(willQueue ? "Queue this message to start when a slot is free. Stop removes it before dispatch."
                      : "Send (Return, or ⌘Return in the message editor) — Shift+Return for a new line")
                .accessibilityLabel(willQueue ? "Queue message" : "Send message")
            }
        }
        .padding()
    }

    private var placeholder: String {
        hasSelectedModel ? "Message" : "Select a model to start chatting"
    }
}

#Preview("Composer — Idle") {
    ComposerView(text: .constant(""), isGenerating: false, canSend: false, hasSelectedModel: true, onSend: {}, onStop: {})
}

#Preview("Composer — Generating") {
    ComposerView(text: .constant("In progress"), isGenerating: true, canSend: false, hasSelectedModel: true, onSend: {}, onStop: {})
}

#Preview("Composer — No Model Selected") {
    ComposerView(text: .constant(""), isGenerating: false, canSend: false, hasSelectedModel: false, onSend: {}, onStop: {})
}
