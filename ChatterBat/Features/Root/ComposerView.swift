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
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .disabled(isGenerating)
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
            } else {
                Button(action: onSend) {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                }
                .labelStyle(.iconOnly)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (Return, or ⌘Return) — Shift+Return for a new line")
            }
        }
        .padding()
    }
}

#Preview("Composer — Idle") {
    ComposerView(text: .constant(""), isGenerating: false, canSend: false, onSend: {}, onStop: {})
}

#Preview("Composer — Generating") {
    ComposerView(text: .constant("In progress"), isGenerating: true, canSend: false, onSend: {}, onStop: {})
}
