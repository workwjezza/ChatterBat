import SwiftUI

/// Transcript rendering: selectable, deliberate-subset Markdown (inline
/// styling + fenced code blocks via `MessageContentView`), per-message
/// service/model attribution, status badges, honest usage display, and
/// a copy-response action.
///
/// Auto-scroll behavior follows `AutoScrollPolicy`: new content scrolls
/// into view only while the user hasn't scrolled away from the bottom,
/// per the brief ("Scrolling up is respected during streaming" /
/// "Auto-scroll resumes only when appropriate"). The policy's decisions
/// are unit-tested (`AutoScrollPolicyTests`); the actual on-screen
/// scrolling behavior wired up here has not been visually confirmed —
/// see docs/STATUS.md.
struct TranscriptView: View {
    let messages: [TranscriptMessage]

    @State private var autoScrollPolicy = AutoScrollPolicy()

    private static let bottomAnchorID = "bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        ContentUnavailableView(
                            "No Messages Yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Select a model and send a message to get started.")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: BottomAnchorOffsetKey.self,
                                    value: geometry.frame(in: .named("transcriptScroll")).minY
                                )
                            }
                        )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "transcriptScroll")
            .onPreferenceChange(BottomAnchorOffsetKey.self) { minY in
                // A large positive minY means the bottom anchor is far
                // below the visible viewport (user scrolled up); a
                // small/near-zero value means it's near the visible
                // bottom edge. This threshold-based heuristic avoids
                // needing the exact viewport height.
                autoScrollPolicy.userDidScroll(atBottom: minY < 120)
            }
            .onChange(of: messages) { _, _ in
                guard autoScrollPolicy.shouldAutoScrollToNewContent else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: messages.map(\.id)) { _, _ in
                // A different set of message IDs means we likely
                // switched conversations — reset to "follow" so a
                // previous conversation's scrolled-up state doesn't
                // leak into this one.
                autoScrollPolicy.reset()
            }
        }
    }
}

/// SwiftUI `PreferenceKey` carrying the bottom anchor's vertical offset
/// within the scroll view's coordinate space, used to infer whether the
/// user is currently scrolled near the bottom.
private struct BottomAnchorOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
