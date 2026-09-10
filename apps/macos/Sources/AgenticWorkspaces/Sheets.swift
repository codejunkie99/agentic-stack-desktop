import SwiftUI

struct NewWorkspaceSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var goal = ""
    @State private var provider = "local"
    @State private var ttl = 60
    @State private var inherit = false

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(text: "New project")
                Text("Create a project.").font(.title2.weight(.semibold))
                Text("Create a managed project folder, or open an existing repository from the sidebar.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.headline)
                TextField("My project", text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Description (optional)").font(.headline)
                TextField("Prepare releases with the right context and checks.", text: $goal, axis: .vertical)
                    .lineLimit(3...5).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Where agents run").font(.headline)
                Picker("Location", selection: $provider) {
                    Text(model.isRemote ? "Connected server" : "This Mac").tag("local")
                    Text("Box Cloud").tag("box")
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Location")
                Text(provider == "local" ? "Uses the agents installed on the selected host." : "Uses your Box account. Creating this workspace does not start billing; Start creates the machine.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if provider == "box" {
                    Stepper("Auto-stop after \(ttl) minutes", value: $ttl, in: 5...480, step: 5)
                    Toggle("Inherit my Box environment and agent credentials", isOn: $inherit)
                    Text("Enable only for your own trusted workspace. This passes the secrets configured in your Box environment to the machine.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(Palette.accent) }
        }.padding(24)
        }
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Create project") {
                    Task {
                        if await model.create(name: name, goal: goal.isEmpty ? "Manage this project’s Agentic Stack." : goal, provider: provider, ttl: ttl, inherit: inherit) { dismiss() }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: DesktopSizing.sheetWidth(560), height: DesktopSizing.sheetHeight(640)).interactiveDismissDisabled(model.busy)
            .onAppear { model.error = nil }
    }
}

struct AddSourceSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var content = ""

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add a source").font(.title2.weight(.semibold))
            Text("Paste a note, a runbook or a project brief. It will wait for your review.").foregroundStyle(.secondary)
            Text("Source name").font(.headline)
            TextField("Release checklist", text: $name).textFieldStyle(.roundedBorder)
            Text("Source text").font(.headline)
            TextEditor(text: $content).font(.system(.body, design: .monospaced)).frame(height: 240)
                .padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
            Text("Do not include passwords, tokens or private keys.").font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.callout).foregroundStyle(Palette.accent) }
        }.padding(24)
        }
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add source") {
                    Task {
                        guard let wid = model.selectedID else { return }
                        if await model.perform("source.add", ["workspaceId": wid, "name": name, "text": content]) {
                            model.section = .references; dismiss()
                        }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.isEmpty || content.isEmpty || model.busy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: DesktopSizing.sheetWidth(608), height: DesktopSizing.sheetHeight(660)).interactiveDismissDisabled(model.busy).onAppear { model.error = nil }
    }
}

struct NewRunSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var task = ""
    @State private var mode = "read-only"
    @State private var timeout = 10
    @State private var modelID = ""
    @State private var effort = ""
    @State private var agent = "codex"
    @State private var useKnowledgeGraph = true

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            SectionEyebrow(text: model.selected?.name ?? "Workspace")
            Text("Give the agent a clear task.").font(.title2.weight(.semibold))
            Text("\(model.approvedCount) reviewed source(s) will be included. \(model.selected?.provider == "box" ? "This sends the task and approved source text to your Box machine and its configured model provider." : "The selected agent runs in this project using its existing sign-in, skills and instructions.")")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Agent", selection: $agent) {
                Text("Codex").tag("codex")
                Text("Claude Code").tag("claude-code")
            }.pickerStyle(.segmented)
            TextEditor(text: $task).frame(height: 150).padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
            Toggle("Include relevant knowledge graph memory", isOn: $useKnowledgeGraph)
            Text("Includes up to five matching imported notes as historical reference. Their source paths and content are saved with this task and sent to the selected agent.")
                .font(.caption).foregroundStyle(.secondary)
            if model.selected?.provider == "box" {
                Text("Cloud access follows your Box agent configuration.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Access", selection: $mode) {
                    Text("Read only").tag("read-only")
                    Text("Edit project files").tag("workspace-write")
                }.pickerStyle(.segmented)
            }
            if model.selected?.provider == "box" {
                TextField("Model ID (use configured default)", text: $modelID).textFieldStyle(.roundedBorder)
            } else {
                AgentModelPicker(runner: agent, choices: model.availableModels, modelID: $modelID, effort: $effort)
            }
            Stepper("Time limit: \(timeout) min", value: $timeout, in: 1...60)
            if let error = model.error { Text(error).font(.callout).foregroundStyle(Palette.accent) }
        }.padding(24)
        }
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start task", systemImage: "play.fill") {
                    Task {
                        guard let wid = model.selectedID else { return }
                        do {
                            let key = model.selected?.provider == "box" ? try await Keychain.read("box") : ""
                            if await model.perform("run.start", ["workspaceId": wid, "task": task, "mode": mode,
                                "timeoutSeconds": timeout * 60, "model": modelID, "effort": effort, "credential": key, "agent": agent, "projectRun": true,
                                "useKnowledgeGraph": useKnowledgeGraph]) {
                                let draftKey = model.terminalHost + ":" + wid
                                if model.dashboardDrafts[draftKey] == task { model.dashboardDrafts[draftKey] = nil }
                                model.tab = .runs; model.section = .runs; dismiss()
                            }
                        } catch { model.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: DesktopSizing.sheetWidth(608), height: DesktopSizing.sheetHeight(700)).interactiveDismissDisabled(model.busy).onAppear { model.error = nil; task = model.runTemplate; model.runTemplate = ""; agent = model.accounts.first(where: { $0.installed })?.id ?? "codex" }
            .task { await model.loadModels() }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let updater: AppUpdater
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("autoDetectTools") private var autoDetect = true
    @AppStorage("graphIncludeActivity") private var includeActivity = false
    @State private var key = ""
    @State private var message = ""
    @State private var checking = false

    var body: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Automatically detect coding tools", isOn: $autoDetect)
                Text("Check installed agents on launch and when returning to the app. Tools refreshes every 30 seconds while open. Memory imports always begin with a preview.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Software updates") {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                }
                Text("Agentic Stack checks its signed GitHub release feed. Sparkle asks before enabling automatic checks and verifies every update archive before installation.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Memory") {
                Toggle("Show routine activity in the knowledge graph", isOn: $includeActivity)
                Text("Focused view hides successful tool bookkeeping and generated session context. Automatic task retrieval uses substantive notes. Originals and provenance are preserved.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Library location") { Text(userFacingPath(model.snapshot.dataPath)).font(.caption).textSelection(.enabled) }
            }
            Section {
                DisclosureGroup("Optional Box Cloud account") {
                SecureField("API key", text: $key)
                Text("Stored in this Mac’s Keychain. Your Box account pays for cloud compute.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Load saved key") {
                        Task {
                            do { key = try await Keychain.read("box"); message = key.isEmpty ? "No saved key." : "Saved key loaded into the secure field." }
                            catch { message = error.localizedDescription }
                        }
                    }
                    Button("Save key") {
                        Task {
                            do { try await Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: "box"); message = "Saved in Keychain." }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove key") {
                        Task {
                            do { try await Keychain.save("", account: "box"); key = ""; message = "Saved key removed." }
                            catch { message = error.localizedDescription }
                        }
                    }
                    Button("Test connection") {
                        checking = true
                        Task {
                            defer { checking = false }
                            do {
                                let _: EmptyResult = try await model.call("cloud.validate", ["credential": key], as: EmptyResult.self)
                                message = "Connected to Box."
                            } catch { message = error.localizedDescription }
                        }
                    }.disabled(key.isEmpty || checking)
                    if checking { ProgressView().controlSize(.small) }
                }
                if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
                Link("Open Box dashboard", destination: URL(string: "https://box.ascii.dev/dashboard")!)
            }
            }
            Section("About") {
                Text("Agentic Stack · \(model.snapshot.version)")
                Text("Native macOS workspace for your existing agents, skills and memory.").font(.caption).foregroundStyle(.secondary)
                Text("Made by Avidlive").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
