import SwiftUI

/// Native Settings scene.
///
/// General shows app version. Accounts (added in Stage 1) hosts
/// Keychain-backed Venice/OpenRouter key entry, verification, and
/// disconnect. No base-URL or other developer-facing fields are exposed
/// here, per the brief.
struct SettingsView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AccountsSettingsView(viewModel: dependencies.makeAccountSettingsViewModel())
                .tabItem {
                    Label("Accounts", systemImage: "person.badge.key")
                }
        }
        .frame(width: 480, height: 420)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersionString)
            }
            Section {
                Text("Connect your Venice and OpenRouter accounts in the Accounts tab.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(20)
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    // Uses in-memory fakes, not `.live()` — previews must never touch the
    // real Keychain or network.
    SettingsView(
        dependencies: AppDependencies(
            credentialStore: PreviewOnlyCredentialStore(),
            veniceChecker: PreviewOnlyConnectionChecker(service: .venice),
            openRouterChecker: PreviewOnlyConnectionChecker(service: .openRouter)
        )
    )
}

/// In-memory, no-op doubles used only by SwiftUI previews in this file.
/// Never referenced from `AppDependencies.live()` or any production path.
private struct PreviewOnlyCredentialStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}

private struct PreviewOnlyConnectionChecker: ConnectionChecking {
    let service: AIService
    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome {
        .valid(summary: "Connected (preview)")
    }
}
