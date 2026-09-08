import SwiftUI

/// Renders one message's content as a sequence of plain-text (inline
/// Markdown) and fenced-code blocks, using `MessageContentParser`.
///
/// Per the brief, this deliberately does NOT attempt full block-level
/// Markdown (headings, lists, block quotes, tables) — only fenced code
/// blocks are treated specially; everything else renders through
/// SwiftUI's native inline Markdown support (bold/italic/inline
/// code/links) via `Text(markdown:)`, with safe fallback to plain text
/// if a segment isn't valid Markdown syntax (`Text` does this
/// automatically — invalid Markdown renders as literal text rather than
/// throwing).
struct MessageContentView: View {
    let content: String

    var body: some View {
        let blocks = MessageContentParser.parse(content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(inlineMarkdown(text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let code):
                    CodeBlockView(language: language, content: code)
                }
            }
        }
    }

    /// Attempts inline-only Markdown parsing; falls back to the raw
    /// string as plain text if parsing throws (defensive — in practice
    /// `.inlineOnlyPreservingWhitespace` accepts nearly any input, but
    /// per the brief a message must never fail to render).
    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

#Preview("Message Content — Mixed") {
    MessageContentView(content: """
    Here's a **bold** claim with `inline code`, then a block:

    ```swift
    let x = 1
    print(x)
    ```

    And more text after.
    """)
    .padding()
    .frame(width: 420)
}

#Preview("Message Content — Plain Only") {
    MessageContentView(content: "Just a plain sentence with no formatting.")
        .padding()
        .frame(width: 420)
}
