import SwiftUI

struct DetectedIntegration: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let installed: Bool
    let detected: Bool
    let executable: String
    let application: String
    let locations: [String]
    let migration: String
    let agentId: String
}
struct IntegrationDiscovery: Decodable, Sendable { let tools: [DetectedIntegration] }

private struct MigrationRequest: Identifiable {
    let id = UUID()
    var providers: Set<String>?
}

struct IntegrationsView: View {
    @Bindable var model: AppModel
    @AppStorage("autoDetectTools") private var autoDetect = true
    @State private var tools: [DetectedIntegration] = []
    @State private var scanning = false
    @State private var message = ""
    @State private var search = ""
    @State private var showAll = false
    @State private var migrationRequest: MigrationRequest?
    @State private var scannedAt: Date?
    private var detectedCount: Int { tools.filter(\.detected).count }
    private var visible: [DetectedIntegration] {
        tools.filter { (showAll || $0.detected) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Context sources").font(.title2.weight(.semibold))
                    Text(model.isRemote ? "One memory layer for agents on the connected server." : "One local memory layer for every coding agent on this Mac.")
                        .foregroundStyle(.secondary)
                    if let scannedAt { Text("Last checked \(scannedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Detect tools", systemImage: "arrow.clockwise") { Task { await detect() } }.disabled(scanning)
                Menu("Agent access", systemImage: "at") {
                    Button("Connect all four tools") { Task { await configureContext("context.install") } }
                    Button("Remove from all four tools") { Task { await configureContext("context.remove") } }
                }.disabled(scanning)
                Menu("Import knowledge…", systemImage: "square.and.arrow.down") {
                    Button("Detected tool memory…") { migrationRequest = MigrationRequest(providers: nil) }
                    Button("Folder or conversation export…") { migrationRequest = MigrationRequest(providers: []) }
                }.disabled(model.selectedID == nil)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)
            contextOverview.padding(.horizontal, 24).padding(.bottom, 18)
            HStack {
                TextField("Find a coding tool", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Show all four tools", isOn: $showAll).toggleStyle(.checkbox)
                if scanning { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !message.isEmpty { Text(message).foregroundStyle(Palette.accent).textSelection(.enabled) }
                    if tools.isEmpty && !scanning {
                        Text("Detect tools to find installed agents and portable knowledge files.").foregroundStyle(.secondary)
                    } else if visible.isEmpty && !scanning {
                        Text("No matching tools found. Show all four tools, or choose an export folder.").foregroundStyle(.secondary)
                    }
                    ForEach(visible) { tool in
                        integration(tool)
                    }
                    DisclosureGroup("Custom agents") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.profiles) { profile in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(profile.name).font(.callout.weight(.medium))
                                        Text(profile.role).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Edit") { model.editAgent(profile) }
                                    Menu {
                                        Button("Start new work") {
                                            model.selectedAgent = profile.runner; model.selectedProfileID = profile.id; model.newConversation()
                                        }
                                        Button("Archive agent") { Task { _ = await model.perform("agentProfiles.archive", ["id": profile.id, "archived": true]) } }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                }
                            }
                            HStack {
                                Button("Create custom agent…") { model.editAgent() }
                                let archived = (model.snapshot.agentProfiles ?? []).filter(\.archived)
                                if !archived.isEmpty {
                                    Menu("Restore archived agent") {
                                        ForEach(archived) { profile in
                                            Button(profile.name) { Task { _ = await model.perform("agentProfiles.archive", ["id": profile.id, "archived": false]) } }
                                        }
                                    }
                                }
                            }
                        }.padding(.vertical, 12)
                    }
                    Text("Import knowledge from Claude Code, Codex, OpenCode, and Cursor. Skills and project diagnostics are in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.selectedID == nil { Text("Open a project to migrate knowledge or add skills and adapters.").font(.callout).foregroundStyle(.secondary) }
                }.padding(18)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            if autoDetect { await detect() }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if autoDetect { await detect() }
            }
        }
        .sheet(item: $migrationRequest) { request in
            MemoryImportSheet(model: model, initialProviders: request.providers)
        }
    }

    private var contextOverview: some View {
        HStack(spacing: 0) {
            contextMetric(value: tools.isEmpty ? "—" : "\(detectedCount)/4", label: "Tools detected", symbol: "terminal")
            Divider().frame(height: 38)
            contextMetric(value: "\(model.snapshot.sources.count)", label: "Indexed sources", symbol: "point.3.connected.trianglepath.dotted")
            Divider().frame(height: 38)
            contextMetric(value: model.isRemote ? "Server" : "On-device", label: "Context stays local", symbol: "lock.shield")
        }
        .padding(.vertical, 15)
        .background(LinearGradient(colors: [Palette.accent.opacity(0.11), .purple.opacity(0.055), .primary.opacity(0.025)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.accent.opacity(0.18)) }
    }

    private func contextMetric(value: String, label: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 14, weight: .semibold))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }.frame(maxWidth: .infinity).padding(.horizontal, 16)
    }

    private func integration(_ tool: DetectedIntegration) -> some View {
        let account = model.accounts.first { $0.id == tool.agentId }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: tool.agentId.isEmpty ? "app.dashed" : "terminal").font(.title3).foregroundStyle(Palette.accent)
                Text(tool.name).font(.headline)
                Spacer()
                StatusLabel(title: account?.status ?? (tool.installed ? "Installed" : tool.detected ? "Files found" : "Not detected"), active: account?.signedIn == true)
                if let account, account.installed && !account.signedIn {
                    Button("Sign in…") { Task { await model.signIn(account) } }.disabled(model.isRemote)
                }
                Button("Import knowledge…") { migrationRequest = MigrationRequest(providers: migrationProviders(tool.id)) }.disabled(model.selectedID == nil)
            }
            HStack(spacing: 14) {
                Label("History and memory", systemImage: "books.vertical")
                if ["codex", "claude-code"].contains(tool.agentId) { Label("Run agents", systemImage: "play.circle") }
                else { Label("Context source", systemImage: "doc.text.magnifyingglass") }
            }.font(.caption).foregroundStyle(.secondary)
            Text(tool.migration)
                .font(.callout).foregroundStyle(.secondary)
            if !tool.locations.isEmpty {
                DisclosureGroup("\(tool.locations.count) knowledge locations") {
                    ForEach(tool.locations, id: \.self) { Text(userFacingPath($0)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }.font(.caption)
            }
            if !tool.executable.isEmpty { Text(userFacingPath(tool.executable)).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(.vertical, 12).padding(.horizontal, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func detect() async {
        guard !scanning else { return }
        scanning = true; message = ""
        defer { scanning = false }
        do {
            var params: [String: Any] = [:]
            if let wid = model.selectedID { params["workspaceId"] = wid }
            let result = try await model.call("integrations.discover", params, as: IntegrationDiscovery.self)
            guard !Task.isCancelled else { return }
            tools = result.tools; scannedAt = Date()
            await model.refreshAccounts()
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }

    private func configureContext(_ method: String) async {
        guard !scanning else { return }
        scanning = true; message = ""
        defer { scanning = false }
        do {
            let result = try await model.call(method, as: TextResult.self)
            message = result.text + "\nRestart open tool windows to load the updated MCP connection."
        } catch { message = error.localizedDescription }
    }

    private func migrationProviders(_ tool: String) -> Set<String> {
        let session = ["claude": "claude-session", "codex": "codex-session",
                       "opencode": "opencode-session", "cursor": "cursor-session"][tool]
        return Set([tool] + (session.map { [$0] } ?? []))
    }
}
