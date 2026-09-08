import Foundation

/// One segment of a parsed assistant/user message: either plain text
/// (rendered with inline Markdown styling) or a fenced code block
/// (rendered monospaced, horizontally scrollable, with a copy action).
enum MessageContentBlock: Equatable, Sendable {
    case text(String)
    case code(language: String?, content: String)
}

/// Splits raw message content into `MessageContentBlock`s by scanning
/// for fenced code blocks (lines starting with three backticks).
///
/// Deliberately supports only this one block-level construct — per the
/// brief, "Do not assume SwiftUI Text provides a complete block-Markdown
/// renderer. Keep the initial supported subset deliberate and tested."
/// Everything outside a fence is treated as one plain-text block and
/// rendered with *inline* Markdown only (bold/italic/code
/// span/links) by `MessageContentView` — no headings, lists, block
/// quotes, or tables.
///
/// Handles unterminated fences (a message still streaming in, whose
/// content ends mid-code-block) by treating the remainder as code
/// rather than crashing or losing content — per the brief's requirement
/// to handle unfinished Markdown/code fences during streaming safely.
enum MessageContentParser {
    static func parse(_ content: String) -> [MessageContentBlock] {
        guard !content.isEmpty else { return [] }

        var blocks: [MessageContentBlock] = []
        var currentLines: [Substring] = []
        var inCodeBlock = false
        var currentLanguage: String?

        // `flushingCodeBlock` distinguishes "about to close a fence, so
        // emit a .code block even if it's empty" from the normal
        // end-of-plain-text flush, which should still skip empty/
        // whitespace-only text (that's not a meaningful block).
        func flush(flushingCodeBlock: Bool = false) {
            let text = currentLines.joined(separator: "\n")
            if inCodeBlock {
                if flushingCodeBlock || !currentLines.isEmpty {
                    blocks.append(.code(language: currentLanguage, content: text))
                }
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(text))
            }
            currentLines = []
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush(flushingCodeBlock: inCodeBlock)
                if inCodeBlock {
                    // Closing fence.
                    inCodeBlock = false
                    currentLanguage = nil
                } else {
                    // Opening fence; anything after the backticks on the
                    // same line is the language tag.
                    inCodeBlock = true
                    let tag = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    currentLanguage = tag.isEmpty ? nil : tag
                }
                continue
            }
            currentLines.append(line)
        }
        flush()

        return blocks
    }
}
