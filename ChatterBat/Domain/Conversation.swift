import Foundation

/// A single sidebar conversation entry.
///
/// This is a Stage 0 in-memory value type only. It has no persistence and no
/// relationship to any provider API. Stage 4 introduces a SwiftData-backed
/// model with the same conceptual shape (title, ordered messages, per-response
/// service/model attribution); this type exists purely to let the Stage 0
/// shell render a realistic split-view layout.
struct Conversation: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var preview: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        preview: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
    }
}
