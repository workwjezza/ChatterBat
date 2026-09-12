import SwiftUI

#if canImport(AppKit)
import AppKit

/// A focused native integration: text input goes through AppKit's input
/// manager, while unmarked Return is reserved for sending a chat message.
struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let canSend: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let editor = ComposerInputTextView(frame: .zero)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.setAccessibilityLabel("Message")
        editor.setAccessibilityIdentifier("chatComposer")
        editor.setAccessibilityHelp("Return sends. Shift+Return inserts a new line. Command+Return also sends.")
        editor.delegate = context.coordinator
        scrollView.documentView = editor
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scrollView.documentView as? ComposerInputTextView else { return }
        editor.isEditable = isEditable
        editor.canSend = canSend
        editor.onSend = onSend
        // Do not replace the backing string on every SwiftUI update: that
        // would discard selection, undo state, and in-progress marked text.
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let editor = nsView.documentView as? NSTextView,
              let container = editor.textContainer,
              let layout = editor.layoutManager,
              let font = editor.font else { return nil }
        let width = max(1, proposal.width ?? 300)
        // Reserve the legacy scrollbar width as well; this also works when
        // macOS uses overlay scrollers and avoids clipping a wrapped line.
        let contentWidth = max(1, width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
        container.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lineHeight = layout.defaultLineHeight(for: font)
        let usedHeight = max(layout.usedRect(for: container).height, layout.extraLineFragmentRect.maxY)
        let height = min(max(lineHeight, usedHeight), lineHeight * 6) + editor.textContainerInset.height * 2
        return CGSize(width: width, height: ceil(height))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor

        init(_ parent: ComposerTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

/// Handles only chat-specific Return shortcuts. All ordinary editing and
/// input-method composition remains with NSTextView rather than a global
/// event monitor. Command+Return is handled here, not by a SwiftUI button
/// shortcut which could bypass the marked-text check.
final class ComposerInputTextView: NSTextView {
    var canSend = false
    var onSend: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        guard isReturn(event) else {
            super.keyDown(with: event)
            return
        }
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        let modifiers = editingModifiers(event)
        if modifiers == .shift {
            if isEditable { insertNewlineIgnoringFieldEditor(self) }
        } else if modifiers.isEmpty || modifiers == .command {
            sendIfAllowed(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, isReturn(event), editingModifiers(event) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        // Consume this shortcut during composition without submitting an
        // unfinished candidate or letting a window/menu shortcut send it.
        if !hasMarkedText() { sendIfAllowed(event) }
        return true
    }

    private func sendIfAllowed(_ event: NSEvent) {
        guard isEditable, canSend, !event.isARepeat,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSend()
    }

    private func isReturn(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.keyCode == 76 // Return and numeric-pad Enter.
    }

    private func editingModifiers(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.shift, .command, .option, .control])
    }
}
#else

/// iOS composer implementation. `TextEditor` keeps native keyboard,
/// dictation, selection, and input-method behavior without requiring UIKit
/// bridging code in the shared chat feature.
struct ComposerTextEditor: View {
    @Binding var text: String
    let isEditable: Bool
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        TextEditor(text: $text)
            .disabled(!isEditable)
            .frame(minHeight: 38, maxHeight: 140)
            .accessibilityLabel("Message")
            .onSubmit {
                guard canSend else { return }
                onSend()
            }
    }
}
#endif