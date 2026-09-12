import AppKit
import SwiftUI

struct WorkspacePreviewView: View {
    @Bindable var model: WorkspacePreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace — local read-only preview").font(.headline)
            Text("Nothing here is sent to a model or saved in chat history. Folder access and previews last until disconnect or app quit. This is not the coding host.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Experimental: some sandbox-granted or symlinked folders may be rejected. Local folders only; filesystem operations have no hard timeout.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Choose folder…", action: chooseFolder).disabled(model.isBusy)
                Text(model.workspaceName ?? "No folder")
                Spacer()
                Button("Disconnect") { model.disconnect() }
                    .disabled(!model.isConnected && !model.isBusy)
            }
            Text(model.phase.rawValue).font(.caption)
            TextField("Workspace-relative path (use . for root listing)", text: $model.relativePath)
                .disabled(model.isBusy || model.pendingProposal != nil)
            HStack {
                Button("List directory") { model.proposeRead(listDirectory: true) }
                    .disabled(!model.isConnected || model.isBusy || model.pendingProposal != nil)
                Button("Read text file") { model.proposeRead(listDirectory: false) }
                    .disabled(!model.isConnected || model.isBusy || model.pendingProposal != nil)
                Spacer()
                if model.isBusy { Button("Stop") { model.stop() } }
            }
            if let proposal = model.pendingProposal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Approve this local operation?").bold()
                    Text(actionDescription(proposal.action)).textSelection(.enabled)
                    Text("Read limit: 200 KB. Listings may omit protected entries. Approval expires after two minutes.")
                        .font(.caption)
                    HStack {
                        Button("Deny") { model.decide(approve: false) }
                        Button("Approve local read") { model.decide(approve: true) }
                    }
                }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            ScrollView {
                Text(resultText).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 160)
            DisclosureGroup("Local operation events (not persisted)") {
                Text(model.events.joined(separator: "\n")).font(.caption.monospaced())
            }
        }
        .padding()
        .frame(width: 600, height: 620)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Use for local preview"
        panel.message = "Select an accessible local folder. Symlink paths are rejected; nothing is uploaded."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.connect(to: url)
        }
    }

    private func actionDescription(_ action: WorkspaceProposedAction) -> String {
        switch action {
        case .readFile(let path): return "Read text: \(path)"
        case .listDirectory(let path): return "List directory: \(path)"
        default: return "Unsupported operation"
        }
    }

    private var resultText: String {
        switch model.result {
        case .text(let path, let content): return "\(path)\n\n\(content)"
        case .directory(let path, let entries, let omitted):
            return "\(path)\n\n" + (entries.isEmpty ? "No visible entries." : entries.joined(separator: "\n"))
                + (omitted ? "\n\n[Protected or excess entries omitted.]" : "")
        case nil: return "No local preview yet."
        }
    }
}