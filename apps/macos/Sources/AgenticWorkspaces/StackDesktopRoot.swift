import SwiftUI

struct StackDesktopRoot: View {
    @Bindable var model: AppModel
    let updater: AppUpdater
    var compact = false
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(Palette.accent)
                    Text("Agentic Stack").font(.system(size: 15, weight: .semibold))
                }.padding(16)
                Menu {
                    ForEach(model.snapshot.workspaces) { project in
                        Button(project.name) { model.selectedID = project.id }
                    }
                    Divider()
                    Button("Set up a project…") { model.showingOnboarding = true }
                    Button("Open project…") { model.openProjectPicker() }
                    Button("New project…") { model.showingNewWorkspace = true }
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text(model.selected?.name ?? "Select a project").lineLimit(1)
                        Spacer()
                    }.padding(8)
                }.menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.bottom, 8)
                Button { model.newConversation() } label: {
                    Label("New work", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderedProminent).padding(.horizontal, 12).padding(.bottom, 12)
                    .disabled(model.selected == nil).help("New work · ⌘N")
                Button { model.spotlightCategory = "All"; model.spotlightTopic = ""; model.spotlightQuery = ""; model.showingCommandPalette = true } label: {
                    HStack { Label("Search", systemImage: "magnifyingglass"); Spacer(); Text("⌘K").foregroundStyle(.secondary) }
                        .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered).padding(.horizontal, 12).padding(.bottom, 10)
                List(selection: sidebarSelection) {
                    Section {
                        Label("Work", systemImage: "square.stack.3d.up").tag("section:" + DesktopSection.graph.rawValue)
                        Label("Memory", systemImage: "brain").tag("section:" + DesktopSection.memory.rawValue)
                        Label("Connections", systemImage: "point.3.connected.trianglepath.dotted").tag("section:" + DesktopSection.integrations.rawValue)
                    }
                    Section("Explore") {
                        Label("Skills", systemImage: "sparkles").tag("section:" + DesktopSection.skills.rawValue)
                    }
                    Section {
                        ForEach(model.workItems.prefix(12)) { item in
                            Label(item.title, systemImage: item.status == "completed" ? "checkmark.circle" : "circle.dotted")
                                .lineLimit(1).tag("work:" + item.id)
                        }
                        ForEach(model.conversations.filter { $0.workId == nil }.prefix(12)) { conversation in
                            Label(conversation.title, systemImage: "bubble.left").lineLimit(1).tag("conversation:" + conversation.id)
                        }
                        ForEach(model.runs.filter { $0.workId == nil && $0.conversationId == nil }.prefix(8)) { run in
                            Label(run.task, systemImage: run.isActive ? "circle.dotted" : "play.circle").lineLimit(1).tag("run:" + run.id)
                        }
                        if model.workItems.isEmpty && model.conversations.isEmpty && model.runs.isEmpty {
                            Text("Your work will appear here.").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Recent work") }
                }.listStyle(.sidebar).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 28)
                Divider().padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: model.isRemote ? "server.rack" : "laptopcomputer")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isRemote ? "Connected server" : "This Mac").font(.caption.weight(.medium))
                        Text(model.isRemote ? model.serverURL : "Local Agentic Stack").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.section = .settings } label: { Image(systemName: "gearshape") }.buttonStyle(.plain)
                }.padding(12)
            }.frame(width: compact ? 190 : 210).frame(maxHeight: .infinity).background(.bar)
            Divider()
            }
            VStack(spacing: 0) {
                if let error = model.error ?? model.connectionError ?? model.accountError {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button { model.error = nil; model.connectionError = nil; model.accountError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.font(.callout).padding(14).background(Palette.accent.opacity(0.1))
                }
                workspaceHeader
                Divider()
                if model.section == .settings {
                    SettingsView(model: model, updater: updater)
                } else if model.section == .integrations {
                    IntegrationsView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
                } else if model.section == .hosting {
                    HostingView(model: model)
                } else if model.loading {
                    ProgressView("Opening Agentic Stack…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.selected != nil {
                    GeometryReader { area in
                        content
                            .frame(width: area.size.width, height: area.size.height, alignment: .topLeading)
                            .clipped()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        QuietEmpty(symbol: "folder.badge.gearshape", title: "Your stack, on your desktop.",
                                   detail: "Open a project to manage its agents, skills, memory and protocols. Use the same stack with Claude Code, Codex and the other supported harnesses.")
                        HStack {
                            Button("Guided setup", systemImage: "wand.and.stars") { model.showingOnboarding = true }.buttonStyle(.borderedProminent)
                            Button("Open project…", systemImage: "folder") { model.openProjectPicker() }.buttonStyle(.borderedProminent)
                            Button("Create new project") { model.showingNewWorkspace = true }
                        }
                        Button("Connect a hosted stack", systemImage: "server.rack") { model.section = .hosting }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    }.padding(44).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.canvas)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Toggle sidebar", systemImage: "sidebar.left") { sidebarVisible.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
            ToolbarItem { Button("Search", systemImage: "magnifyingglass") { model.spotlightCategory = "All"; model.spotlightTopic = ""; model.spotlightQuery = ""; model.showingCommandPalette = true } }
            ToolbarItem { Button("Open project", systemImage: "folder.badge.plus") { model.openProjectPicker() } }
        }
        .task(id: model.terminalHost) { await model.loadModels() }
        .sheet(isPresented: $model.showingAgentEditor) { AgentEditorView(model: model, profile: model.editingProfile) }
        .sheet(isPresented: $model.showingOnboarding) { OnboardingView(model: model) }
        .overlay {
            if let request = model.conversationAttachmentRequest {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { model.dismissConversationAttachment() }
                    ConversationSpotlightView(model: model, initialQuery: request.query, initialAgent: request.agent,
                        context: request.context, onSelect: { model.selectConversationAttachment($0, requestID: request.id) },
                        onDismiss: { model.dismissConversationAttachment() })
                        .id(request.id).padding(24)
                }.transition(.opacity)
            } else if model.showingCommandPalette {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { model.showingCommandPalette = false }
                    CommandPaletteView(model: model)
                        .padding(24)
                        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
                }.transition(.opacity)
            } else if let request = model.knowledgeFilterRequest {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { model.knowledgeFilterRequest = nil }
                    KnowledgeFilterSpotlight(model: model, request: request).id(request.id).padding(24)
                }.transition(.opacity)
            }
        }
        .onChange(of: model.conversationDraftKey) { _, key in
            if let request = model.conversationAttachmentRequest, request.draftKey != key { model.dismissConversationAttachment() }
        }
        .onChange(of: model.showingCommandPalette) { _, showing in
            if showing { model.dismissConversationAttachment() }
        }
        .onChange(of: model.section) { _, section in
            model.knowledgeFilterRequest = nil
            if section != .graph { model.graphFullPage = false }
            if ![DesktopSection.graph, .chat].contains(section) { model.dismissConversationAttachment() }
        }
        .onChange(of: model.handoverPreviewKey) { _, key in
            if model.knowledgeFilterRequest?.targetKey != key { model.knowledgeFilterRequest = nil }
        }
        .onChange(of: model.loading) { _, loading in
            if !loading && model.connectionError == nil && !model.snapshot.dataPath.isEmpty && model.snapshot.workspaces.isEmpty {
                model.showingOnboarding = true
            }
        }
        .sheet(isPresented: $model.showingNewWorkspace) { NewWorkspaceSheet(model: model) }
        .sheet(isPresented: $model.showingSource) { AddSourceSheet(model: model) }
        .sheet(isPresented: $model.showingRun) { NewRunSheet(model: model) }
        .sheet(isPresented: $model.showingRemoteProject) { RemoteProjectSheet(model: model) }
        .onChange(of: model.tab) { _, tab in
            switch tab {
            case .runs: model.section = .runs
            case .knowledge: model.section = .references
            case .handover: model.section = .handover
            default: break
            }
        }
    }

    private var sidebarSelection: Binding<String> {
        Binding(get: {
            if let item = model.currentWork, [.chat, .runs].contains(model.section) { return "work:" + item.id }
            if model.section == .chat, let conversation = model.conversation { return "conversation:" + conversation.id }
            if model.section == .runs, let id = model.focusedRunID { return "run:" + id }
            return "section:" + model.section.workspace.rawValue
        }, set: { value in
            if value.hasPrefix("work:"), let item = model.workItems.first(where: { $0.id == String(value.dropFirst(5)) }) {
                model.openWork(item)
            } else if value.hasPrefix("conversation:"), let conversation = model.conversations.first(where: { $0.id == String(value.dropFirst(13)) }) {
                model.openConversation(conversation)
            } else if value.hasPrefix("run:") {
                model.openStandaloneRun(String(value.dropFirst(4)))
            } else if value.hasPrefix("section:"), let section = DesktopSection(rawValue: String(value.dropFirst(8))) {
                model.section = section == .memory ? .memoryBrowse : section
            }
        })
    }

    private var workspaceHeader: some View {
        HStack(spacing: compact ? 10 : 16) {
            sectionTitle
                .frame(minWidth: compact ? 96 : 130, maxWidth: compact ? 130 : 210, alignment: .leading)
                .layoutPriority(0)
            if !model.section.siblings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.section.siblings) { page in
                            Button { model.section = page } label: {
                                Text(page.pageTitle)
                                    .font(.system(size: 11, weight: model.section == page ? .semibold : .regular))
                                    .foregroundStyle(model.section == page ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(model.section == page ? Palette.accent.opacity(0.14) : .clear, in: Capsule())
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.section == page ? .isSelected : [])
                            .disabled(model.selected == nil && ![DesktopSection.settings, .hosting, .integrations].contains(page))
                        }
                    }
                }
                .accessibilityLabel(model.section.workspaceTitle + " sections")
                .layoutPriority(2)
            }
            Spacer(minLength: 0)
            if [DesktopSection.graph, .chat].contains(model.section) {
                Button { model.contextInspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.plain)
                    .help("Toggle context inspector")
                    .accessibilityLabel("Toggle context inspector")
            }
            if canRun { runButton }
        }
        .padding(.horizontal, compact ? 18 : 24)
        .frame(height: 58)
    }

    private var canRun: Bool {
        model.selected != nil && model.section == .runs
    }

    private var sectionTitle: some View {
        HStack(spacing: 12) {
            Text(model.section.workspaceTitle).font(.system(size: 18, weight: .semibold)).lineLimit(1)
            if !compact {
                Divider().frame(height: 16)
                Text(model.selected?.name ?? "Agentic Stack").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runButton: some View {
        Button("New task", systemImage: "play.fill") { model.showingRun = true }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(model.busy || model.runs.contains(where: \.isActive))
    }

    @ViewBuilder private var content: some View {
        switch model.section {
        case .chat, .graph: GraphWorkView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        case .overview, .insights: ProjectDashboardView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        case .terminal: TerminalWorkspaceView(model: model)
        case .references: KnowledgeView(model: model)
        case .handover: HandoverView(model: model)
        case .runs: RunsView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        case .loops: LoopManagementView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        case .memory: MemoryManagementView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        case .memoryBrowse: KnowledgeGraphView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        case .personal: PersonalMemoryView(model: model).id(model.terminalHost + (model.selectedID ?? ""))
        default: StackManagementView(model: model, section: model.section.rawValue).id(model.terminalHost + (model.selectedID ?? "") + model.section.rawValue)
        }
    }
}

struct RemoteProjectSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = "/data/projects/"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Open a server project").font(.title2.weight(.semibold))
            Text("Enter the repository's absolute path on the connected server.").foregroundStyle(.secondary)
            TextField("/data/projects/my-project", text: $path).textFieldStyle(.roundedBorder)
            if let error = model.error { Text(error).font(.callout).foregroundStyle(Palette.accent) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open project") { Task { if await model.openProject(path: path) { dismiss() } } }
                    .buttonStyle(.borderedProminent).disabled(model.busy || path.isEmpty)
            }
        }.padding(28).frame(width: 500)
    }
}
