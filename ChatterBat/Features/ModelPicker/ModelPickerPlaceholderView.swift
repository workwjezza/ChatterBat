import SwiftUI

/// Placeholder sheet standing in for the Stage 2 unified model picker.
///
/// Confirms that the ⌘K shortcut and sheet presentation flow work end to
/// end. Real catalog search, favorites, and service filters are
/// implemented in Stage 2 against live/cached provider data — never demo
/// fixtures in production.
struct ModelPickerPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Picker")
                .font(.title3.bold())
            Text(
                "The unified Venice/OpenRouter model picker is implemented in " +
                "Stage 2. This placeholder only verifies that the sheet and " +
                "keyboard shortcut are wired correctly."
            )
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    ModelPickerPlaceholderView()
}
