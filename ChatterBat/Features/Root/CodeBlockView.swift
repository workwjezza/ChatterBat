import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Renders one fenced code block: monospaced, horizontally scrollable,
/// with a copy button and (when known) a language label.
///
/// Per the brief: "Code blocks with horizontal scrolling and a copy
/// action" and "Long responses and code blocks must remain navigable" —
/// this uses a horizontal `ScrollView` rather than wrapping, so long
/// lines stay readable instead of being truncated or forced to wrap
/// awkwardly, and remains usable at narrow window widths since only the
/// code content scrolls, not the whole message.
struct CodeBlockView: View {
    let language: String?
    let content: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(didCopy ? "Code copied to clipboard" : "Copy code")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func copyToClipboard() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }
}

#Preview("Code Block — With Language") {
    CodeBlockView(language: "swift", content: "let greeting = \"Hello, world!\"\nprint(greeting)")
        .padding()
        .frame(width: 400)
}

#Preview("Code Block — No Language") {
    CodeBlockView(language: nil, content: "plain code without a language tag")
        .padding()
        .frame(width: 400)
}
