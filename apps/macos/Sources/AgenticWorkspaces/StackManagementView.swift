import AppKit
import SwiftUI

struct StackManagementView: View {
    @Bindable var model: AppModel
    @State private var snapshot: StackSnapshot?
    let section: String
    @State private var editingPath: String?
    @State private var message = ""
    @State private var query = ""
    @State private var showingCatalog = false
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(snapshot.map { userFacingPath($0.path) } ?? "Loading project…").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(loading)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let snapshot {
                            if !snapshot.initialized {
                                QuietEmpty(symbol: "shippingbox", title: "Give this project its stack.", detail: "Initialize the portable memory layers, seed skills, protocols and tools. Existing files are preserved.")
                                Button("Set up this project") { model.showingOnboarding = true }.buttonStyle(.borderedProminent)
                            }
                            if section == "Agents" { harnesses(snapshot) }
                            if section == "Skills" { skills(snapshot) }
                            if section == "Protocols" {
                                Text("Project rules").font(.headline)
                                Text("Edit delegation, permissions and tool schemas used by this project's agents.").font(.callout).foregroundStyle(.secondary)
                                projectFiles(snapshot, prefix: ".agent/protocols/")
                                DisclosureGroup("Advanced permission details") {
                                    domains(snapshot, matching: ["/api/protocols/permissions"])
                                }

                            }
                            if section == "Maintenance" {
                                Text("Project maintenance").font(.title3.weight(.semibold))
                                VStack(alignment: .leading, spacing: 14) {
                                    Button("Run doctor") { Task { await command("doctor") } }
                                    Button("Rebuild skill manifest") { Task { await command("manifest") } }
                                    Button("Preview infrastructure upgrade") { Task { await command("upgrade-preview") } }
                                    Button("Apply infrastructure upgrade") { Task { await command("upgrade") } }
                                    Button("Check Brain connection") { Task { await command("brain-status") } }
                                    Button("Open project folder", systemImage: "folder") { NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.path)) }.disabled(model.isRemote)
                                }
                                DisclosureGroup("Advanced project diagnostics") {
                                    domains(snapshot, matching: ["/api/trust", "/api/settings", "/api/runs", "/api/ops/events", "/api/data-flywheel"])
                                }
                            }
                        } else if loading { ProgressView("Reading the project stack…") }
                        if !message.isEmpty {
                            Divider()
                            Text(message).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).disabled(model.busy)
                }.frame(minWidth: 400)
            }
        }
        .task(id: model.selectedID) { await reload() }
        .onChange(of: model.selected?.projectPath) { _, _ in Task { await reload() } }
        .onChange(of: model.showingOnboarding) { _, showing in if !showing { Task { await reload() } } }
        .sheet(isPresented: $showingCatalog, onDismiss: { Task { await reload() } }) { SkillCatalogView(model: model) }
        .sheet(isPresented: Binding(get: { editingPath != nil }, set: { if !$0 { editingPath = nil } }), onDismiss: { Task { await reload() } }) {
            if let path = editingPath { StackFileEditor(model: model, path: path) }
        }
    }

    private func harnesses(_ state: StackSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Adapters share this project’s instructions and skills with Claude Code, Codex, OpenCode, and Cursor. Account sign-in and migration are in Connections.").font(.callout).foregroundStyle(.secondary)
            TextField("Find a project adapter", text: $query).textFieldStyle(.roundedBorder)
            ForEach(supportedAdapters(state).filter { query.isEmpty || ($0.name + " " + $0.description).localizedCaseInsensitiveContains(query) }) { adapter in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(adapter.displayName).font(.headline)
                        Spacer()
                        if state.installed.contains(adapter.id) {
                            Label("Installed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Add adapter") { Task { await action("stack.adapter", ["adapter": adapter.id]) } }
                        }
                    }
                    DisclosureGroup("Adapter details") { Text(adapter.description).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Divider()
                }
            }
        }
    }

    private func supportedAdapters(_ state: StackSnapshot) -> [StackAdapter] {
        ["claude-code", "codex", "opencode", "cursor"].compactMap { id in
            state.adapters.first { $0.id == id }
        }
    }

    private func skills(_ state: StackSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(state.skills.count) project skills").font(.title3.weight(.semibold))
                Spacer()
                Button("Add skills…", systemImage: "plus") { showingCatalog = true }.buttonStyle(.borderedProminent)
            }
            if !state.skills.isEmpty {
                Button("Repair bundled skill compatibility") { Task { await action("skills.repair") } }
                    .font(.caption).help("Update unchanged bundled skills for Codex and Claude Code. Preserve customized files.")
            }
            TextField("Find an installed skill", text: $query).textFieldStyle(.roundedBorder)
            ForEach(state.skills.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { skill in
                HStack {
                    Image(systemName: "sparkle").foregroundStyle(Palette.accent)
                    Text(skill.name)
                    Spacer()
                    Button("Read / edit") { editingPath = ".agent/skills/\(skill.id)/SKILL.md" }
                }.padding(.vertical, 4)
            }
        }
    }

    private func domains(_ state: StackSnapshot, matching keys: [String]) -> some View {
        ForEach(state.domains.filter { keys.contains($0.id) }) { domain in
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text(domain.name).font(.headline); Spacer(); StatusLabel(title: domain.status.capitalized) }
                if !domain.summary.isEmpty { Text(domain.summary).font(.callout).foregroundStyle(.secondary) }
                ForEach(domain.items) { item in
                    DisclosureGroup {
                        Text(item.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.label).font(.callout.weight(.medium))
                            Text(item.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }
        }
    }

    private func projectFiles(_ state: StackSnapshot, prefix: String) -> some View {
        ForEach(state.files.filter { $0.path.hasPrefix(prefix) }) { file in
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.name).font(.callout.weight(.medium))
                    Text(file.path).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Read / edit") { editingPath = file.path }
            }
        }
    }

    private func reload() async {
        guard let wid = model.selectedID else { return }
        loading = true; snapshot = nil; message = ""
        defer { if model.selectedID == wid { loading = false } }
        do {
            let state = try await model.call("stack.snapshot", ["workspaceId": wid], as: StackSnapshot.self)
            if model.selectedID == wid { snapshot = state }
        } catch { if model.selectedID == wid { message = error.localizedDescription } }
    }

    private func action(_ method: String, _ parameters: [String: String] = [:]) async {
        guard let wid = model.selectedID, !model.busy else { return }
        model.busy = true
        defer { model.busy = false }
        var values: [String: Any] = parameters
        values["workspaceId"] = wid
        do {
            let result: TextResult = try await model.call(method, values, as: TextResult.self)
            await reload()
            message = result.text
        } catch { message = error.localizedDescription }
    }

    private func command(_ operation: String) async { await action("stack.command", ["operation": operation, "query": query]) }
}

struct SkillCatalogView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var skills: [CatalogSkill] = []
    @State private var search = ""
    @State private var selected: String?
    @State private var content = ""
    @State private var message = ""
    private var visible: [CatalogSkill] { skills.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bring your skills with you.").font(.title2.weight(.semibold))
            TextField("Find a skill", text: $search).textFieldStyle(.roundedBorder)
            HSplitView {
                List(visible, selection: $selected) { skill in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name).font(.callout.weight(.medium))
                        Text(userFacingPath(skill.origin) + (skill.installed == true ? " · Installed" : "")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(skill.id)
                }.frame(minWidth: 200, maxWidth: 260)
                ScrollView {
                    Text(content.isEmpty ? "Select a skill to read its instructions." : content)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }.frame(height: DesktopSizing.sheetHeight(660) - 230)
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(Palette.accent) }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(skills.first(where: { $0.id == selected })?.installed == true ? "Installed" : "Add to project") {
                    Task {
                        guard let wid = model.selectedID, let selected else { return }
                        if await model.perform("skills.add", ["workspaceId": wid, "id": selected]) {
                            message = "Skill added. It will be included in future runs."
                            if let index = skills.firstIndex(where: { $0.id == selected }) { skills[index].installed = true }
                        }
                        else { message = model.error ?? "The skill could not be added."; model.error = nil }
                    }
                }.buttonStyle(.borderedProminent).disabled(selected == nil || content.isEmpty || model.busy || skills.first(where: { $0.id == selected })?.installed == true)
            }
        }.padding(28).frame(width: DesktopSizing.sheetWidth(820))
        .task {
            do { let result: CatalogResult = try await model.call("skills.catalog", ["workspaceId": model.selectedID ?? ""], as: CatalogResult.self); skills = result.skills }
            catch { message = error.localizedDescription }
        }
        .task(id: selected) {
            content = ""; message = ""
            guard let selected else { return }
            do { let result: TextResult = try await model.call("skills.read", ["id": selected], as: TextResult.self); content = result.text }
            catch { message = error.localizedDescription }
        }
    }
}
