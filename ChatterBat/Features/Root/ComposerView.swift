import SwiftUI

/// Bottom composer: multiline input plus Send/Stop.
///
/// Intent per the brief: Return sends, Shift+Return inserts a newline.
/// CAVEAT (see `docs/STATUS.md`): SwiftUI's `TextField(axis: .vertical)`
/// is documented/known to treat plain Return as a newline insert rather
/// than firing `onSubmit`, which is the opposite of what's wanted here.
/// `.onSubmit` is still attached in case platform behavior differs by
/// OS version, but ⌘Return is also wired as a guaranteed way to send
/// while this is unverified, since this environment has no interactive
/// GUI access to confirm actual Return-key behavior. Input-method marked
/// text was not specifically tested for the same reason.
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .disabled(isGenerating)
                .accessibilityLabel("Message")
                .onSubmit {
                    if canSend { onSend() }
                }

            if isGenerating {
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .labelStyle(.iconOnly)
                .help("Stop generating (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: onSend) {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                }
                .labelStyle(.iconOnly)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (Return, or ⌘Return) — Shift+Return for a new line")
                .accessibilityLabel("Send message")
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
