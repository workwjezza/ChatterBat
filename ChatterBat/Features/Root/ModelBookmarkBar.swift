import SwiftUI

/// Favorites are bookmarks; the pin is the durable default for new chats.
/// Actions apply to the current chat and future defaults, not other chats.
struct ModelBookmarkBar: View {
    var viewModel: AppViewModel
    var catalog: ModelPickerViewModel
    let isBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Text("New-chat default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.useAutoDefault(isBusy: isBusy)
                    } label: {
                        Label("Auto", systemImage: viewModel.modelDefaults.pinnedModel == nil ? "checkmark.circle.fill" : "circle")
                    }
                    .help("Use the saved Auto policy for new chats. No policy means setup is required.")
                    ForEach(bookmarks, id: \.self) { identity in
                        let pinned = viewModel.modelDefaults.pinnedModel == identity
                        let model = catalog.displayModel(identity)
                        let available = catalog.currentModel(identity) != nil
                        Button {
                            viewModel.togglePinnedDefault(identity, isBusy: isBusy)
                        } label: {
                            Label("\(model?.displayName ?? identity.modelID) · \(identity.service.displayName)\(available ? "" : " · unavailable")",
                                  systemImage: pinned ? "pin.fill" : "star")
                        }
                        .disabled(!available && !pinned)
                        .help(pinned ? "Click again to unpin and return the default to Auto." : "Pin for new chats and select now. Refresh models if unavailable.")
                        .accessibilityValue(pinned ? "Pinned default" : "Not pinned")
                    }
                    Button("Models…") { viewModel.isModelPickerPresented = true }
                    Button("Refresh") {
                        Task { await catalog.loadAllConfiguredCatalogs() }
                    }
                    .help("Load current catalogs to resolve saved bookmarks. No inference request.")
                }
                .buttonStyle(.bordered)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Save Auto policy from current model") {
                    viewModel.saveAutoPolicyFromCurrentModel(isBusy: isBusy)
                }
                .disabled(viewModel.selectedModel == nil)
                .help("Save this model's service, privacy label, listed input/output ceilings and OpenRouter privacy settings, then use Auto. This replaces the previous Auto policy.")
                Text("Applies here and to new chats; other chats keep their settings.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            if let policy = viewModel.currentSession.autoPolicy {
                Text("This chat's Auto: \(policy.anchor.modelID) · \(policy.anchor.service.displayName) · \(policy.privacyDescription ?? "privacy unspecified") · input ≤ $\(policy.maxInputUSDPerMillion.description)/M · output ≤ $\(policy.maxOutputUSDPerMillion.description)/M" +
                     (policy.anchor.service == .openRouter ? " · data collection: \(policy.denyDataCollection ? "deny" : "allow") · ZDR: \(policy.zeroDataRetention ? "on" : "off") · provider fallbacks: \(policy.allowProviderFallbacks ? "on" : "off") (stricter current settings retained)" : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let notice = viewModel.selectionNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .disabled(isBusy)
        .background(.bar)
    }

    private var bookmarks: [ModelIdentity] {
        let favorites = catalog.bookmarkedIdentities
        guard let pin = viewModel.modelDefaults.pinnedModel, !favorites.contains(pin) else { return favorites }
        return [pin] + favorites // Removing a star never silently changes the default.
    }
}