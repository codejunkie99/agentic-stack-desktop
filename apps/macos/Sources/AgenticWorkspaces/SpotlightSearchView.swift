import SwiftUI

private enum SpotlightCategory: String, CaseIterable, Identifiable {
    case all = "All", work = "Work", memory = "Memory", conversations = "Conversations", skills = "Skills", actions = "Actions"
    var id: String { rawValue }
}

private struct SpotlightResult: Identifiable {
    enum Destination {
        case work(WorkItem), conversation(AgentConversation), memory(GraphNote), reference(ConversationReference)
        case skill(InstalledSkill), action(StackAction), project(Workspace), newWork, newProject, openProject
    }
    let id: String
    let group: String
    let title: String
    let detail: String
    let source: String
    let symbol: String
    let score: Int
    let destination: Destination
}

struct SpotlightSearchView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var category = SpotlightCategory.all
    @State private var allConversations = false
    @State private var conversationTool = ""
    @State private var conversationRole = ""
    @State private var conversationModel = ""
    @State private var conversationModels: [String] = []
    @State private var selectedID: String?
    @State private var notes: [GraphNote] = []
    @State private var references: [ConversationReference] = []
    @State private var skills: [InstalledSkill] = []
    @State private var memoryKey = ""
    @State private var referencesKey = ""
    @State private var skillsKey = ""
    @State private var searchingMemory = false
    @State private var searchingConversations = false
    @State private var memoryError = ""
    @State private var referencesError = ""
    @State private var skillsError = ""
    @State private var previewSkill: InstalledSkill?
    @State private var previewReference: ConversationReference?
    @State private var previewContent = ""
    @State private var previewError = ""
    @State private var focusRequest = 0

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var projectKey: String { model.terminalHost + ":" + (model.selectedID ?? "") }
    private var searchKey: String {
        [projectKey, category.rawValue, trimmedQuery, model.spotlightTopic, String(allConversations),
         conversationTool, conversationRole, conversationModel].joined(separator: ":")
    }
    private var limit: Int { category == .all ? 5 : 40 }
    private var searching: Bool { searchingMemory || searchingConversations }
    private var results: [SpotlightResult] {
        var rows: [SpotlightResult] = []
        func add(_ id: String, _ group: String, _ title: String, _ detail: String, _ source: String, _ symbol: String, _ destination: SpotlightResult.Destination) {
            guard let score = SpotlightSearchRules.score(trimmedQuery, title: title, detail: detail + " " + source) else { return }
            rows.append(.init(id: id, group: group, title: title, detail: detail, source: source, symbol: symbol, score: score, destination: destination))
        }
        if category == .all || category == .work {
            for item in model.workItems {
                let nextAction = item.checkpoint?.nextAction ?? ""
                add("work:" + item.id, "Work", item.title, nextAction.isEmpty ? item.objective : nextAction,
                    item.status.replacingOccurrences(of: "_", with: " ").capitalized, "square.stack", .work(item))
            }
        }
        if (category == .all || category == .conversations) {
            for chat in model.conversations where
                (conversationTool.isEmpty || chat.agent == conversationTool) &&
                (conversationModel.isEmpty || chat.model.localizedCaseInsensitiveContains(conversationModel)) &&
                (conversationRole.isEmpty || conversationRole == "agent") {
                add("conversation:" + chat.id, "Conversations", chat.title, chat.agentName ?? chat.agent,
                    chat.model.isEmpty ? "Agentic Stack" : chat.model, "bubble.left.and.bubble.right", .conversation(chat))
            }
            if referencesKey == searchKey {
                let nativeIDs = Set(model.conversations.map { "native:" + $0.id })
                for ref in references where !nativeIDs.contains(ref.id) {
                    let provenance = [ref.agentName, ref.roleName, ref.model, ref.workspaceName].compactMap { value in
                        value.flatMap { $0.isEmpty ? nil : $0 }
                    }.joined(separator: " · ")
                    rows.append(.init(id: "reference:" + ref.id, group: "Conversations", title: ref.title, detail: ref.excerpt,
                                      source: provenance, symbol: "bubble.left.and.text.bubble.right",
                                      score: ref.score ?? 0, destination: .reference(ref)))
                }
            }
        }
        if (category == .all || category == .memory), memoryKey == searchKey {
            for (index, note) in notes.enumerated() {
                rows.append(.init(id: "memory:" + note.id, group: "Memory", title: note.displayTitle, detail: note.body,
                                  source: (note.origins.first?.provider ?? "Memory") + (note.status.map { " · " + $0.capitalized } ?? ""),
                                  symbol: "brain", score: notes.count - index, destination: .memory(note)))
            }
        }
        if (category == .all && !trimmedQuery.isEmpty || category == .skills), skillsKey == projectKey {
            for skill in skills {
                add("skill:" + skill.id, "Skills", skill.name, "Read this project’s skill instructions", "Installed in project", "sparkles", .skill(skill))
            }
        }
        if category == .all || category == .actions {
            if model.selectedID != nil { add("new-work", "Actions", "New work", "Start a new objective", "⌘N", "square.and.pencil", .newWork) }
            add("open-project", "Actions", "Open project…", "Choose a project folder", "⌘O", "folder", .openProject)
            add("new-project", "Actions", "New project…", "Create a project", "⌥⌘N", "folder.badge.plus", .newProject)
            let available = StackAction.all.filter { model.selectedID != nil || $0.section != nil || ["setup", "create-agent"].contains($0.id) }
            for action in available where !trimmedQuery.isEmpty || category == .actions || ["section-Knowledge graph", "section-Skills"].contains(action.id) {
                add("action:" + action.id, "Actions", action.title, action.detail, "Action", action.symbol, .action(action))
            }
            for project in model.snapshot.workspaces where !trimmedQuery.isEmpty && project.id != model.selectedID {
                add("project:" + project.id, "Projects", project.name, project.goal, "Switch project", "folder", .project(project))
            }
        }
        // Keep familiar groups stable while each group ranks by relevance, then recency.
        return ["Work", "Memory", "Conversations", "Skills", "Projects", "Actions"].flatMap { group in
            rows.enumerated().filter { $0.element.group == group }.sorted {
                $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score
            }.prefix(limit).map(\.element)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let skill = previewSkill { skillPreview(skill) }
            else if let reference = previewReference { referencePreview(reference) }
            else {
                searchHeader
                filters
                Divider()
                resultList
                footer
            }
        }
        .frame(maxWidth: 740, maxHeight: 610)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(
                LinearGradient(colors: [Palette.accent.opacity(0.42), .primary.opacity(0.08), .purple.opacity(0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Palette.accent.opacity(0.10), radius: 48, y: 16)
        .shadow(color: .black.opacity(0.22), radius: 32, y: 16)
        .onAppear {
            category = SpotlightCategory(rawValue: model.spotlightCategory) ?? .all
            query = String(model.spotlightQuery.prefix(300))
        }
        .onExitCommand {
            if previewSkill != nil || previewReference != nil { previewSkill = nil; previewReference = nil; focusRequest += 1 }
            else { dismiss() }
        }
        .onChange(of: query) { _, value in
            if value.count > 300 { query = String(value.prefix(300)) }
        }
        .onChange(of: results.map(\.id), initial: true) { _, ids in
            if !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
        .onChange(of: projectKey) { _, _ in
            previewSkill = nil; previewReference = nil; previewContent = ""; notes = []; references = []; skills = []
            conversationModels = []; conversationModel = ""
        }
        .task(id: searchKey) { await search() }
        .task(id: projectKey) { await loadSkills() }
        .task(id: previewSkill?.id) { await loadSkillPreview() }
        .accessibilityIdentifier("spotlight-search")
    }

    private var searchHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: [Palette.accent, .purple.opacity(0.78)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: Palette.accent.opacity(0.28), radius: 12, y: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("ASK YOUR CONTEXT").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(Palette.accent)
                NativeSpotlightField(text: $query, placeholder: "What did that subagent find? Where did we decide this?",
                    accessibilityName: "Ask Agentic Stack context", focusRequest: focusRequest,
                    onSubmit: { if let result = results.first(where: { $0.id == selectedID }) { activate(result) } },
                    onMove: { move($0) }, onEscape: { dismiss() },
                    canFocus: { model.showingCommandPalette && model.conversationAttachmentRequest == nil && model.knowledgeFilterRequest == nil })
                    .frame(height: 28)
            }
            if searching { ProgressView().controlSize(.small) }
            Button { dismiss() } label: { Text("esc").font(.caption.monospaced()).foregroundStyle(.secondary).padding(5).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5)) }
                .buttonStyle(.plain).accessibilityLabel("Close search")
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 18)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(SpotlightCategory.allCases) { item in
                    Button {
                        category = item; model.spotlightCategory = item.rawValue
                        if item != .memory { model.spotlightTopic = "" }
                        focusRequest += 1
                    } label: {
                        Text(item.rawValue).font(.system(size: 12, weight: category == item ? .semibold : .regular))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(category == item ? Palette.accent.opacity(0.15) : .clear, in: Capsule())
                            .foregroundStyle(category == item ? Palette.accent : .secondary)
                    }.buttonStyle(.plain).accessibilityAddTraits(category == item ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Label(model.selected?.name ?? "Choose a project to search its knowledge", systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle)
                if !model.spotlightTopic.isEmpty {
                    Button { model.spotlightTopic = ""; focusRequest += 1 } label: {
                        Label(model.spotlightTopic, systemImage: "xmark.circle.fill")
                    }.buttonStyle(.plain).help("Clear topic filter")
                }
                Spacer(minLength: 8)
                if category == .all || category == .conversations {
                    Menu {
                        Button("This project") { allConversations = false }
                        Button("All conversations") { allConversations = true }
                    } label: { Text(allConversations ? "All conversations" : "Project conversations") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Conversation search scope")
                }
            }.font(.caption).foregroundStyle(.secondary)
            if category == .all || category == .conversations {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Menu {
                            Button("All tools") { conversationTool = ""; focusRequest += 1 }
                            Divider()
                            ForEach(["claude-code", "codex", "opencode", "cursor"], id: \.self) { tool in
                                Button(conversationToolName(tool)) { conversationTool = tool; focusRequest += 1 }
                            }
                        } label: { Label(conversationToolName(conversationTool), systemImage: "terminal") }
                        .menuStyle(.borderlessButton).fixedSize()
                        Menu {
                            Button("All roles") { conversationRole = ""; focusRequest += 1 }
                            Divider()
                            Button("Agents") { conversationRole = "agent"; focusRequest += 1 }
                            Button("Subagents") { conversationRole = "subagent"; focusRequest += 1 }
                            Button("Automations") { conversationRole = "automation"; focusRequest += 1 }
                            Button("Reviews") { conversationRole = "review"; focusRequest += 1 }
                        } label: { Label(conversationRoleName, systemImage: "person.2") }
                        .menuStyle(.borderlessButton).fixedSize()
                        if !conversationModels.isEmpty {
                            Menu {
                                Button("Any model") { conversationModel = ""; focusRequest += 1 }
                                Divider()
                                ForEach(conversationModels, id: \.self) { item in
                                    Button(item) { conversationModel = item; focusRequest += 1 }
                                }
                            } label: { Label(conversationModel.isEmpty ? "Any model" : conversationModel, systemImage: "cpu") }
                            .menuStyle(.borderlessButton).fixedSize()
                        }
                        if !conversationTool.isEmpty || !conversationRole.isEmpty || !conversationModel.isEmpty {
                            Button {
                                conversationTool = ""; conversationRole = ""; conversationModel = ""; focusRequest += 1
                            } label: { Label("Clear", systemImage: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 14)
    }

    private var resultList: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if trimmedQuery.isEmpty && category == .all {
                        Text("PICK UP WHERE YOU LEFT OFF").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 12)
                    }
                    let rows = results
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, result in
                        if index == 0 || rows[index - 1].group != result.group {
                            Text(result.group.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 3)
                        }
                        resultRow(result).id(result.id)
                    }
                    if rows.isEmpty && !searching {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 28, weight: .light))
                            Text(trimmedQuery.isEmpty ? "Nothing here yet" : "No results for “\(trimmedQuery)”").font(.callout.weight(.medium)).lineLimit(2)
                            Text("Try another term or choose a different category.").font(.caption)
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 55)
                    }
                    let errors = [memoryError, referencesError, skillsError].filter { !$0.isEmpty }
                    if !errors.isEmpty {
                        Text(errors.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(12)
                    }
                }.padding(.horizontal, 10).padding(.bottom, 10)
            }.onChange(of: selectedID) { _, id in if let id { scroll.scrollTo(id, anchor: .center) } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ result: SpotlightResult) -> some View {
        Button { activate(result) } label: {
            HStack(spacing: 12) {
                Image(systemName: result.symbol).font(.system(size: 18)).foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36).background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(SpotlightSearchRules.excerpt(result.detail, query: trimmedQuery)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(result.source).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 145, alignment: .trailing)
                if selectedID == result.id { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .background(selectedID == result.id ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selectedID == result.id ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Text("↑ ↓  Navigate"); Text("↵  Open"); Text("esc  Close")
                Spacer()
                Text("⌘K").font(.caption.monospaced())
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 13)
        }
    }

    private func skillPreview(_ skill: InstalledSkill) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { previewSkill = nil; focusRequest += 1 } label: { Label("Search", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Button("Open Skills") { dismiss(); model.section = .skills }
            }.font(.callout).padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(skill.name).font(.title2.weight(.semibold))
                    Text(".agent/skills/\(skill.id)/SKILL.md").font(.caption).foregroundStyle(.secondary)
                    if !previewError.isEmpty { Text(previewError).foregroundStyle(.secondary) }
                    else if previewContent.isEmpty { ProgressView("Reading skill…") }
                    else { Text(previewContent).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        }
    }

    private func referencePreview(_ reference: ConversationReference) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { previewReference = nil; focusRequest += 1 } label: { Label("Search", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Button("Attach to next message") {
                    model.attachConversationReference(reference)
                    dismiss(); model.graphFullPage = false; model.section = .chat
                }.buttonStyle(.borderedProminent)
                    .disabled(model.selectedConversationReferences.count >= 5 || model.selectedConversationReferences.contains(where: { $0.id == reference.id }))
            }.font(.callout).padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(reference.title).font(.title2.weight(.semibold))
                    Text(reference.agentName + (reference.model.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
                    Text("Search excerpt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(reference.excerpt.isEmpty ? "No excerpt is available for this conversation." : reference.excerpt).font(.callout).textSelection(.enabled)
                    Divider()
                    Text("Source").font(.caption.weight(.semibold))
                    Text(userFacingPath(reference.origin)).font(.caption).textSelection(.enabled)
                    ForEach(Array((reference.origins ?? []).enumerated()), id: \.offset) { _, origin in
                        Text("\(userFacingPath(origin.path)):\(origin.line)").font(.caption2).textSelection(.enabled)
                    }
                    Text("Attach this conversation as context for your next message. You can review or remove it before sending.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.selectedConversationReferences.count >= 5 {
                        Text("Five conversations are already attached. Remove one from the composer to add this source.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        }
    }

    private func move(_ direction: Int) { selectedID = SpotlightSearchRules.moving(selectedID, in: results.map(\.id), by: direction) }
    private func dismiss() { model.showingCommandPalette = false }

    private func conversationToolName(_ value: String) -> String {
        ["claude-code": "Claude Code", "codex": "Codex", "opencode": "OpenCode", "cursor": "Cursor"][value] ?? "All tools"
    }

    private var conversationRoleName: String {
        ["agent": "Agents", "subagent": "Subagents", "automation": "Automations", "review": "Reviews"][conversationRole] ?? "All roles"
    }

    private func activate(_ result: SpotlightResult) {
        switch result.destination {
        case .skill(let skill): previewSkill = skill
        case .work(let item): dismiss(); model.openWork(item)
        case .conversation(let chat): dismiss(); model.openConversation(chat)
        case .memory(let note):
            dismiss(); model.section = .graph; model.graphFullPage = false
            Task { await model.inspectMemory(note.id, showGraph: true) }
        case .reference(let reference):
            let nativeID = reference.id.replacingOccurrences(of: "global-native:", with: "").replacingOccurrences(of: "native:", with: "")
            if reference.kind == "native", let chat = model.snapshot.conversations?.first(where: { $0.id == nativeID }) {
                dismiss(); model.selectedID = chat.workspaceId; model.openConversation(chat)
            } else {
                previewReference = reference
            }
        case .action(let action): dismiss(); action.perform(model)
        case .project(let project): dismiss(); model.selectedID = project.id
        case .newWork: dismiss(); model.newConversation()
        case .newProject: dismiss(); model.showingNewWorkspace = true
        case .openProject: dismiss(); model.openProjectPicker()
        }
    }

    private func search() async {
        let key = searchKey, host = model.terminalHost
        memoryError = ""; referencesError = ""
        searchingMemory = false; searchingConversations = false
        guard let wid = model.selectedID else { return }
        let query = trimmedQuery, topic = model.spotlightTopic
        let needMemory = category == .memory || category == .all && !query.isEmpty
        let needConversations = category == .conversations || category == .all && !query.isEmpty
        guard needMemory || needConversations else { return }
        do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
        guard key == searchKey else { return }
        async let memory: Void = searchMemory(enabled: needMemory, query: query, topic: topic, wid: wid, host: host, key: key)
        async let conversations: Void = searchConversations(enabled: needConversations, query: query, wid: wid, host: host, key: key)
        _ = await (memory, conversations)
    }

    private func searchMemory(enabled: Bool, query: String, topic: String, wid: String, host: String, key: String) async {
        guard enabled else { return }
        searchingMemory = true
        defer { if key == searchKey { searchingMemory = false } }
        do {
            let state = try await model.terminalCall("knowledge.query", ["workspaceId": wid, "query": query, "topic": topic], host: host, as: GraphSnapshot.self)
            guard !Task.isCancelled, key == searchKey else { return }
            notes = state.notes; memoryKey = key
        } catch { if !Task.isCancelled, key == searchKey { memoryError = "Memory search: " + error.localizedDescription } }
    }

    private func searchConversations(enabled: Bool, query: String, wid: String, host: String, key: String) async {
        guard enabled else { return }
        searchingConversations = true
        defer { if key == searchKey { searchingConversations = false } }
        do {
            let result = try await model.terminalCall("conversation.references", ["workspaceId": wid, "query": query,
                "scope": allConversations ? "all" : "project", "agent": conversationTool, "role": conversationRole,
                "model": conversationModel, "limit": 40], host: host, as: ConversationReferenceResult.self)
            guard !Task.isCancelled, key == searchKey else { return }
            references = result.references; referencesKey = key; conversationModels = result.models ?? []
        } catch { if !Task.isCancelled, key == searchKey { referencesError = "Conversation search: " + error.localizedDescription } }
    }

    private func loadSkills() async {
        let key = projectKey, host = model.terminalHost
        skillsError = ""
        guard let wid = model.selectedID else { return }
        do {
            let result = try await model.terminalCall("stack.snapshot", ["workspaceId": wid], host: host, as: StackSnapshot.self)
            guard !Task.isCancelled, key == projectKey else { return }
            skills = result.skills; skillsKey = key
        } catch { if !Task.isCancelled, key == projectKey { skillsError = "Skills: " + error.localizedDescription } }
    }

    private func loadSkillPreview() async {
        previewContent = ""; previewError = ""
        guard let skill = previewSkill, let wid = model.selectedID else { return }
        let key = projectKey, host = model.terminalHost
        do {
            let result = try await model.terminalCall("stack.file", ["workspaceId": wid, "path": ".agent/skills/\(skill.id)/SKILL.md"], host: host, as: ProjectFile.self)
            guard !Task.isCancelled, key == projectKey, previewSkill?.id == skill.id else { return }
            previewContent = result.text.isEmpty ? "This skill file is empty." : result.text
        } catch { if !Task.isCancelled, key == projectKey { previewError = error.localizedDescription } }
    }
}
