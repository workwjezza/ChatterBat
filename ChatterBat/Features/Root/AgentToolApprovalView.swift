import SwiftUI

/// Conversation-local permission card: shown for every single agent-tool
/// invocation before it runs, never auto-approved.
///
/// Deliberately shows exactly three pieces of information and nothing
/// else: which tool, the model's own stated reason for wanting it,
/// and an explicit statement that approving will open a native picker
/// the user controls — there is no path through this view that lets a
/// tool run without that picker actually being shown and interacted
/// with.
struct AgentToolApprovalView: View {
    let invocation: ToolInvocationRecord
    let onApprove: () -> Void
    let onDeny: () -> Void

    /// Disables both buttons after the first tap so a slow panel
    /// dismissal (waiting on the user to pick something) can't be
    /// raced by a second tap sending a second, conflicting decision.
    @State private var hasDecided = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tool Request", systemImage: "wrench.and.screwdriver")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(invocation.tool.displayName)
                    .font(.body.bold())
                Text(invocation.tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("The model's stated reason:")
                    .font(.caption.bold())
                Text(invocation.modelStatedReason)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Text("Approving opens a native file/folder picker — ChatterBat only reads the exact item you choose there, never anything the model names on its own.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Deny") {
                    hasDecided = true
                    onDeny()
                }
                Button("Approve…") {
                    hasDecided = true
                    onApprove()
                }
            }
            .disabled(hasDecided)
        }
        .padding(20)
        .frame(width: 380)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Agent Tool Approval — Read File") {
    AgentToolApprovalView(
        invocation: ToolInvocationRecord(
            tool: .readFile,
            toolCallID: "call_1",
            modelStatedReason: "I need to see the contents of the file you mentioned to answer accurately."
        ),
        onApprove: {},
        onDeny: {}
    )
}
