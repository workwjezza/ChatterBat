import Foundation

/// Explicitly labeled demo/preview data.
///
/// STAGE 0 NOTICE: This fixture exists only to populate SwiftUI previews and
/// the Stage 0 shell so the split-view layout can be exercised before any
/// provider integration exists. It must never be wired into a production
/// networking or persistence path. Stage 2 replaces the model catalog with
/// live/cached provider data; Stage 4 replaces this conversation list with a
/// SwiftData-backed repository.
enum DemoFixtures {
    static var conversations: [Conversation] {
        [
            Conversation(
                title: "Welcome to ChatterBat",
                preview: "This is placeholder content for the Stage 0 shell.",
                updatedAt: .now
            ),
            Conversation(
                title: "Sample conversation",
                preview: "Streaming chat arrives in Stage 3.",
                updatedAt: .now.addingTimeInterval(-3_600)
            )
        ]
    }
}
