import AppKit
import SwiftUI
import XCTest
@testable import ChatterBat

@MainActor
final class ComposerTextEditorTests: XCTestCase {
    private func event(modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 36, repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                        timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                        charactersIgnoringModifiers: "\r", isARepeat: repeatKey, keyCode: keyCode)!
    }

    private func editor() -> ComposerInputTextView {
        let editor = ComposerInputTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        editor.isRichText = false
        editor.string = "Hello"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.canSend = true
        return editor
    }

    func testReturnSendsOnceWithoutInsertingNewline() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.keyDown(with: event())
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(editor.string, "Hello")
    }

    func testShiftReturnInsertsNewlineAtSelectionWithoutSending() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.setSelectedRange(NSRange(location: 2, length: 2))
        editor.keyDown(with: event(modifiers: .shift))
        XCTAssertEqual(editor.string, "He\no")
        XCTAssertEqual(sends, 0)
    }

    func testCommandReturnIsConsumedAndSendsOnce() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        XCTAssertTrue(editor.performKeyEquivalent(with: event(modifiers: .command)))
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(editor.string, "Hello")
    }

    func testCommandReturnKeyDownAlsoSends() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.keyDown(with: event(modifiers: .command))
        XCTAssertEqual(sends, 1)
    }

    func testNumericPadEnterAndCapsLockReturnSend() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.keyDown(with: event(modifiers: .numericPad, keyCode: 76))
        editor.keyDown(with: event(modifiers: .capsLock))
        XCTAssertEqual(sends, 2)
    }

    func testCannotSendConsumesReturnWithoutChangingDraft() {
        let editor = editor()
        editor.canSend = false
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.keyDown(with: event())
        XCTAssertTrue(editor.performKeyEquivalent(with: event(modifiers: .command)))
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(editor.string, "Hello")
    }

    func testNoneditableInputDoesNotSendOrInsertShiftReturn() {
        let editor = editor()
        editor.isEditable = false
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.keyDown(with: event())
        editor.keyDown(with: event(modifiers: .shift))
        XCTAssertTrue(editor.performKeyEquivalent(with: event(modifiers: .command)))
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(editor.string, "Hello")
    }

    func testWhitespaceAndRepeatedReturnNeverSend() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.keyDown(with: event(repeatKey: true))
        editor.string = " \n\t"
        editor.keyDown(with: event())
        XCTAssertEqual(sends, 0)
    }

    func testCommandReturnDuringMarkedTextDoesNotSendOrDiscardComposition() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        let draft = editor.string
        XCTAssertTrue(editor.performKeyEquivalent(with: event(modifiers: .command)))
        XCTAssertEqual(sends, 0)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, draft)
    }

    func testReturnDuringMarkedTextNeverSubmitsChat() {
        let editor = editor()
        var sends = 0
        editor.onSend = { sends += 1 }
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        editor.keyDown(with: event())
        XCTAssertEqual(sends, 0)
    }

    func testMultilineInsertionUpdatesBindingWithoutSending() {
        var draft = ""
        var sends = 0
        let parent = ComposerTextEditor(text: Binding(get: { draft }, set: { draft = $0 }),
                                        isEditable: true, canSend: true, onSend: { sends += 1 })
        let coordinator = parent.makeCoordinator()
        let editor = editor()
        editor.delegate = coordinator
        editor.insertText("\nsecond line\nthird line", replacementRange: editor.selectedRange())
        XCTAssertEqual(draft, "Hello\nsecond line\nthird line")
        XCTAssertEqual(sends, 0)
    }

    func testNativeEditorHostedInSwiftUIHasBoundedGrowingHeightAndAccessibility() throws {
        var draft = "Hello"
        let binding = Binding(get: { draft }, set: { draft = $0 })
        let host = NSHostingView(rootView: ComposerTextEditor(text: binding, isEditable: true, canSend: true, onSend: {}))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        host.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(findEditor(in: host))
        XCTAssertEqual(editor.string, "Hello")
        XCTAssertEqual(editor.accessibilityLabel(), "Message")
        XCTAssertTrue(editor.allowsUndo)
        XCTAssertFalse(editor.isRichText)
        let singleLineHeight = host.fittingSize.height
        XCTAssertGreaterThan(singleLineHeight, 0)

        draft = Array(repeating: "Line", count: 20).joined(separator: "\n")
        host.rootView = ComposerTextEditor(text: binding, isEditable: true, canSend: true, onSend: {})
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(editor.string, draft)
        let multilineHeight = host.fittingSize.height
        XCTAssertGreaterThan(multilineHeight, singleLineHeight)
        XCTAssertLessThanOrEqual(multilineHeight, singleLineHeight * 6)

        host.rootView = ComposerTextEditor(text: binding, isEditable: false, canSend: false, onSend: {})
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(editor.isEditable)
        XCTAssertFalse(editor.canSend)
    }

    private func findEditor(in view: NSView) -> ComposerInputTextView? {
        if let editor = view as? ComposerInputTextView { return editor }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }
}