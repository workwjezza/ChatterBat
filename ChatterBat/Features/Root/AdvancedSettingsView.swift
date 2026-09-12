import SwiftUI

/// Popover content for Stage 6's advanced, capability-aware chat
/// controls: reasoning effort, Venice-only thinking controls,
/// OpenRouter-only routing preferences, and a context-usage readout
/// with an explicit "reset context" action.
///
/// Every section only appears when it actually applies to the
/// currently-selected model — per the brief, advanced controls must
/// stay hidden by default and must never be shown for a model that
/// can't use them. `model == nil` (no model selected yet) shows
/// nothing but the usage/context section, since there's nothing else
/// to configure yet.
struct AdvancedSettingsView: View {
    @Binding var settings: AdvancedChatSettings
    let model: ModelInfo?
    let contextUsage: ContextUsageEstimate?
    /// Whether a context boundary is currently set — see
    /// `ChatCoordinator.setContextBoundary`. The boundary is *set* from
    /// a message's own context menu (`MessageBubble`'s "Start Context
    /// Here" action), not from this popover; this popover only shows
    /// the current usage estimate and offers to clear an existing
    /// boundary.
    let hasContextBoundary: Bool
    let onClearContextBoundary: () -> Void
    /// Stage 7: the "Agent Tools (Beta)" toggle — deliberately placed
    /// in this same advanced-settings surface (rather than somewhere
    /// more prominent) per the brief's requirement that the agent
    /// beta stay "explicitly separate, optional" from the chat-first
    /// product, not front-and-center.
    @Binding var agentToolsEnabled: Bool

    var body: some View {
        Form {
            if let model {
                if model.service == .venice {
                    Section("Venice Prompt") {
                        Toggle("Include Venice’s system instructions", isOn: $settings.venice.includeSystemPrompt)
                        Text("Off reduces provider-added prompt overhead. Saved chats and conversation context are unchanged. Turning this on may change the assistant’s style.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.supportsReasoning == .supported {
                    Section("Reasoning") {
                        Picker("Effort", selection: $settings.reasoningEffort) {
                            Text("Default").tag(ReasoningEffort?.none)
                            ForEach(ReasoningEffort.allCases) { effort in
                                Text(effort.displayName).tag(ReasoningEffort?.some(effort))
                            }
                        }
                        if model.service == .venice {
                            Toggle("Disable thinking", isOn: $settings.venice.disableThinking)
                            Toggle("Hide thinking from response", isOn: $settings.venice.stripThinkingResponse)
                            Text("Hiding thinking does not prevent reasoning-token charges.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if model.supportsReasoning == .unknown {
                    Section {
                        Text("Reasoning support for this model is unknown, so reasoning controls are hidden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.service == .openRouter {
                    Section("OpenRouter Routing") {
                        Toggle("Allow fallback providers", isOn: $settings.openRouterRouting.allowFallbacks)
                        Picker("Data collection", selection: $settings.openRouterRouting.dataCollection) {
                            ForEach(DataCollectionPreference.allCases) { preference in
                                Text(preference.displayName).tag(preference)
                            }
                        }
                        Toggle("Zero Data Retention only", isOn: $settings.openRouterRouting.zdr)
                    }
                }
            } else {
                Section {
                    Text("Select a model to see its available advanced settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let model {
                Section("Agent Tools (Beta)") {
                    if model.supportsTools == .supported {
                        Toggle("Enable read-only tools for the next message", isOn: $agentToolsEnabled)
                        Text("Every tool request still requires your explicit approval, one at a time, before it runs.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if model.supportsTools == .unknown {
                        Text("Tool support for this model is unknown, so tools are hidden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This model doesn't support tools.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Context") {
                Text("Estimate includes the draft and eligible message text, not provider instructions or tool definitions. Actual billed usage is reported after the response.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let contextUsage {
                    contextUsageRow(contextUsage)
                }
                if hasContextBoundary {
                    Text("A context boundary is set — only messages from that point onward are sent as context.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Clear Context Boundary") {
                        onClearContextBoundary()
                    }
                } else {
                    Text("Use \"Start Context Here\" on a message to send only that message and later ones as context.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func contextUsageRow(_ usage: ContextUsageEstimate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(usage.messageCount) message\(usage.messageCount == 1 ? "" : "s") · ~\(usage.estimatedTokens) estimated tokens")
                .font(.caption)
            if let percent = usage.percentOfContextWindow {
                Text("~\(Int(percent))% of this model's context window (estimate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Context window size unknown for this model.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Advanced Settings — Venice Reasoning Model") {
    AdvancedSettingsView(
        settings: .constant(AdvancedChatSettings()),
        model: ModelInfo(
            identity: ModelIdentity(service: .venice, modelID: "deepseek-r1"),
            displayName: "DeepSeek R1",
            contextLength: 32000,
            maxOutputTokens: nil,
            pricing: .unknown,
            supportsTools: .unknown,
            supportsReasoning: .supported,
            supportsVision: .unknown,
            privacyDescription: "private"
        ),
        contextUsage: ContextUsageEstimate(messageCount: 4, characterCount: 800, estimatedTokens: 200, percentOfContextWindow: 0.6),
        hasContextBoundary: false,
        onClearContextBoundary: {},
        agentToolsEnabled: .constant(false)
    )
}

#Preview("Advanced Settings — No Model Selected") {
    AdvancedSettingsView(
        settings: .constant(AdvancedChatSettings()),
        model: nil,
        contextUsage: nil,
        hasContextBoundary: false,
        onClearContextBoundary: {},
        agentToolsEnabled: .constant(false)
    )
}
