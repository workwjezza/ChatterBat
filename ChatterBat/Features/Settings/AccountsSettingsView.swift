import SwiftUI

/// Settings pane for connecting Venice and OpenRouter accounts.
///
/// Each service gets its own card: key entry, Save & Verify, connection
/// status, a link to the provider's key-management page, and Disconnect
/// once a key is stored. No base-URL field is shown — per the brief,
/// ordinary users should never need to configure endpoints.
struct AccountsSettingsView: View {
    var viewModel: AccountSettingsViewModel

    var body: some View {
        Form {
            ForEach(AIService.allCases) { service in
                Section(service.displayName) {
                    AccountCard(service: service, viewModel: viewModel)
                }
            }
        }
        .padding(20)
        .onAppear {
            viewModel.refreshStoredKeyPresence()
        }
    }
}

private struct AccountCard: View {
    let service: AIService
    var viewModel: AccountSettingsViewModel
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow

            SecureField(
                "API key",
                text: Binding(
                    get: { viewModel.draftKeys[service] ?? "" },
                    set: { viewModel.draftKeys[service] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("\(service.displayName) API key")

            HStack {
                Button("Save & Verify") {
                    Task {
                        isVerifying = true
                        await viewModel.saveAndVerify(service)
                        isVerifying = false
                    }
                }
                .disabled(isVerifying || (viewModel.draftKeys[service] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)

                if isConfigured {
                    Button("Re-verify") {
                        Task {
                            isVerifying = true
                            await viewModel.verifyConnection(service)
                            isVerifying = false
                        }
                    }
                    .disabled(isVerifying)

                    Button("Disconnect", role: .destructive) {
                        viewModel.disconnect(service)
                    }
                }

                Spacer()

                Link("Get an API key", destination: service.keyManagementURL)
                    .font(.caption)
            }

            Text(
                "Keys are stored only in the macOS Keychain. This does not " +
                "give ChatterBat its own account with \(service.displayName) " +
                "— you're connecting your existing \(service.displayName) API key."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var isConfigured: Bool {
        switch viewModel.state(for: service) {
        case .notConfigured: return false
        default: return true
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch viewModel.state(for: service) {
        case .notConfigured:
            Label("Not connected", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verifying…")
            }
            .foregroundStyle(.secondary)
        case .connected(let summary):
            Label(summary, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalidCredential:
            Label("Invalid or revoked key", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    AccountsSettingsView(
        viewModel: AccountSettingsViewModel(
            credentialStore: PreviewCredentialStore(),
            checkers: [:]
        )
    )
}

/// In-memory credential store used only by the Xcode preview above. Never
/// referenced by production code paths (see `AppDependencies`).
private struct PreviewCredentialStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}
