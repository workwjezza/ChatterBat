import SwiftUI

/// Plain-text transcript rendering for Stage 3.
///
/// Deliberately minimal: selectable plain text only, no Markdown/code
/// blocks (Stage 5) and no persistence-derived history (Stage 4) — this
/// renders exactly what `ChatCoordinator` holds in memory right now.
struct TranscriptView: View {
    let messages: [TranscriptMessage]

    var body: some View {
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
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let attribution = message.attribution {
                    Text("· \(attribution.modelID) · \(attribution.service.displayName)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                statusBadge
            }

            Text(message.content.isEmpty && message.status == .streaming ? "…" : message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let usage = message.usage {
                Text(usageText(usage))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch message.status {
        case .streaming:
            ProgressView().controlSize(.mini)
        case .completed, .interrupted:
            EmptyView()
        case .cancelled:
            Text("Stopped").font(.caption2).foregroundStyle(.orange)
        case .failed(let reason):
            Text(reason).font(.caption2).foregroundStyle(.red)
        }
    }

    /// Formats only fields the provider actually reported. Per the
    /// brief, a missing usage field must never be displayed as zero —
    /// this only ever shows fields that are non-nil.
    private func usageText(_ usage: ChatUsage) -> String {
        var parts: [String] = []
        if let prompt = usage.promptTokens { parts.append("\(prompt) prompt") }
        if let completion = usage.completionTokens { parts.append("\(completion) completion") }
        if let total = usage.totalTokens { parts.append("\(total) total") }
        return parts.isEmpty ? "Usage unknown" : parts.joined(separator: " · ") + " tokens"
    }
}

#Preview("Transcript — Mixed States") {
    TranscriptView(messages: [
        TranscriptMessage(role: .user, content: "Hello there", status: .completed),
        TranscriptMessage(
            role: .assistant,
            content: "Hi! How can I help?",
            status: .completed,
            attribution: ModelIdentity(service: .venice, modelID: "llama-3.2-3b"),
            usage: ChatUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20)
        ),
        TranscriptMessage(
            role: .assistant,
            content: "Partial response before stop...",
            status: .cancelled,
            attribution: ModelIdentity(service: .openRouter, modelID: "openai/gpt-4")
        )
    ])
}
