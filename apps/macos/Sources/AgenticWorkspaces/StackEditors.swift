import SwiftUI

struct AgentConnectionRows: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(model.accounts) { account in
                HStack(spacing: 14) {
                    Image(systemName: "terminal").font(.title3).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(account.name).font(.headline)
                        Text(account.version.isEmpty ? account.status : account.version).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusLabel(title: account.status, active: account.signedIn)
                    if account.installed && !account.signedIn {
                        Button(model.isRemote ? "Sign-in instructions" : "Sign in…") { Task { await model.signIn(account) } }
                    }
                }
            }
            Button("Refresh agents", systemImage: "arrow.clockwise") { Task { await model.refreshAccounts() } }
                .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            Text(model.isRemote ? "These agents and their sign-ins are on the connected server." : "Uses your existing Claude Code and Codex sign-ins. Agent tokens stay with their official CLIs.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct StackFileEditor: View {
    @Bindable var model: AppModel
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var digest = ""
    @State private var message = ""
    @State private var saving = false
    @State private var workspaceID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(path.components(separatedBy: "/").suffix(2).joined(separator: "/")).font(.title2.weight(.semibold))
            Text("Changes are saved in the selected project. Its adapters continue using the same portable stack.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $content).font(.system(.body, design: .monospaced)).padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line)).frame(height: DesktopSizing.sheetHeight(660) - 210)
            if !message.isEmpty { Text(message).foregroundStyle(Palette.accent).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Reload") { Task { await load() } }.disabled(saving)
                Spacer()
                Button("Save changes") {
                    Task {
                        guard let wid = workspaceID else { return }
                        saving = true
                        defer { saving = false }
                        do {
                            let result: ProjectFile = try await model.call("stack.file", ["workspaceId": wid, "path": path, "content": content, "digest": digest], as: ProjectFile.self)
                            digest = result.digest; dismiss()
                        } catch { message = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(digest.isEmpty || saving)
            }
        }.padding(28).frame(width: DesktopSizing.sheetWidth(800)).interactiveDismissDisabled(saving)
            .task { workspaceID = model.selectedID; await load() }
    }
    private func load() async {
        guard let wid = workspaceID else { return }
        do {
            let result: ProjectFile = try await model.call("stack.file", ["workspaceId": wid, "path": path], as: ProjectFile.self)
            content = result.text; digest = result.digest; message = ""
        } catch { message = error.localizedDescription }
    }
}
