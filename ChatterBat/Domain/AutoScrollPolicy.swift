import Foundation

/// Pure decision logic for whether a transcript should auto-scroll to
/// the newest message.
///
/// Extracted as a plain, unit-testable type (rather than embedded
/// directly in a SwiftUI view's `onChange`/`ScrollViewReader` glue)
/// specifically because this environment has no interactive display to
/// visually confirm scroll behavior — the *decision* of whether to
/// scroll is verified by tests; wiring it to an actual `ScrollViewReader`
/// still requires manual visual confirmation (see docs/STATUS.md).
///
/// Per the brief: "Scrolling up is respected during streaming" and
/// "Auto-scroll resumes only when appropriate" — the rule implemented
/// here is: auto-scroll follows new content by default, but once the
/// user scrolls away from the bottom, it stops following until they
/// return to the bottom themselves (or switch to a different
/// conversation, which resets to following).
struct AutoScrollPolicy {
    private var isPinnedToBottom = true

    /// Call whenever the scroll position changes because of direct user
    /// interaction (not because new content pushed the view). `atBottom`
    /// reflects whether the visible scroll offset is at (or very near)
    /// the bottom edge after that interaction.
    mutating func userDidScroll(atBottom: Bool) {
        isPinnedToBottom = atBottom
    }

    /// Whether new content should trigger an auto-scroll-to-bottom right
    /// now.
    var shouldAutoScrollToNewContent: Bool {
        isPinnedToBottom
    }

    /// Resets to the default "follow new content" state — call when
    /// switching to a different conversation, so a previous
    /// conversation's scrolled-up state doesn't leak into the next one.
    mutating func reset() {
        isPinnedToBottom = true
    }
}
