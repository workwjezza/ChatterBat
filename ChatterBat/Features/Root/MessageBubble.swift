import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// One message row: role/attribution/status header, rendered content
/// (`MessageContentView`), usage/cost footer, a copy-response action,
/// and (Stage 6) a "Start Context Here" action plus a visible marker
/// when this message is the conversation's current context boundary.
struct MessageBubble: View {
    let message: TranscriptMessage
    var isContextBoundary: Bool = false
    var onStartContextHere: () -> Void = {}

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isContextBoundary {
                Label("Context starts here", systemImage: "arrow.down.to.line")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
            }

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
                Spacer()
                if !message.content.isEmpty {
                    Button {
                        copyToClipboard(message.content)
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(didCopy ? "Response copied to clipboard" : "Copy response")
                }
            }

            if message.content.isEmpty && message.status == .streaming {
                Text("…")
                    .foregroundStyle(.secondary)
            } else {
                MessageContentView(content: message.content)
            }

            if let usage = message.usage {
                Text(usageText(usage))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Start Context Here") {
                onStartContextHere()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
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
    /// this only ever shows fields that are non-nil. Cost is always
    /// labeled with its actual unit ("USD" or "credits") — see
    /// `ChatUsage`'s doc comment for why these are never conflated.
    private func usageText(_ usage: ChatUsage) -> String {
        var parts: [String] = []
        if let prompt = usage.promptTokens { parts.append("\(prompt) prompt") }
        if let completion = usage.completionTokens { parts.append("\(completion) completion") }
        if let total = usage.totalTokens { parts.append("\(total) total") }
        var text = parts.isEmpty ? "Usage unknown" : parts.joined(separator: " · ") + " tokens"
        if let costUSD = usage.costUSD {
            text += " · \(formattedUSD(costUSD))"
        }
        if let costCredits = usage.costCredits {
            text += " · \(costCredits) credits"
        }
        return text
    }

    private func formattedUSD(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 5
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    private var accessibilityDescription: String {
        let speaker = message.role == .user ? "You" : "Assistant"
        var description = "\(speaker): \(message.content)"
        if case .failed(let reason) = message.status {
            description += ". Failed: \(reason)"
        } else if message.status == .cancelled {
            description += ". Stopped."
        }
        return description
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }
}

#Preview("Message Bubble — Mixed States") {
    VStack(alignment: .leading, spacing: 12) {
        MessageBubble(message: TranscriptMessage(role: .user, content: "Hello there", status: .completed))
        MessageBubble(message: TranscriptMessage(
            role: .assistant,
            content: "Hi! Here's **bold** text and:\n```swift\nlet x = 1\n```",
            status: .completed,
            attribution: ModelIdentity(service: .venice, modelID: "llama-3.2-3b"),
            usage: ChatUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20)
        ))
        MessageBubble(message: TranscriptMessage(
            role: .assistant,
            content: "Partial response before stop...",
            status: .cancelled,
            attribution: ModelIdentity(service: .openRouter, modelID: "openai/gpt-4")
        ))
    }
    .padding()
    .frame(width: 480)
}
