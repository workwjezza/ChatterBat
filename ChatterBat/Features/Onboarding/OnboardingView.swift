import SwiftUI

/// First-run welcome screen.
///
/// Per the brief's first-run flow: explains bring-your-own-key billing,
/// links to Settings → Accounts for connecting a service (rather than
/// duplicating account-connection UI here), and never asks for a base
/// URL. This is intentionally a single, honest screen — not a
/// multi-step wizard that re-implements the model picker or account
/// forms, both of which already exist as their own real, reachable UI.
struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to ChatterBat")
                .font(.title.bold())

            Text(
                "ChatterBat is a native Mac client for the Venice and OpenRouter " +
                "APIs. You bring your own API key for either service (or both) " +
                "and pay that service directly — ChatterBat has no account or " +
                "subscription of its own."
            )
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bulletPoint("Connect Venice and/or OpenRouter in Settings → Accounts (⌘,).")
                bulletPoint("Keys are stored only in the macOS Keychain — never in this app's own storage.")
                bulletPoint("Pick a model for any conversation with ⌘K, any time.")
                bulletPoint("Conversation history is kept locally on this Mac.")
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Not Now") { onDismiss() }
                Button("Open Account Settings") {
                    onOpenSettings()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 340)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    OnboardingView(onOpenSettings: {}, onDismiss: {})
}
