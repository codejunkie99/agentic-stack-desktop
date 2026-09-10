import AppKit
import SwiftUI

/// The canvas stays mounted while its scene is hidden, preserving orbit and selection.
struct GraphWorkView: View {
    @Bindable var model: AppModel
    private var graphVisible: Bool { model.section == .graph }

    var body: some View {
        GeometryReader { area in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ZStack {
                            KnowledgeGraphView(model: model, mainCanvas: true, isActive: graphVisible)
                                .opacity(graphVisible ? 1 : 0).allowsHitTesting(graphVisible).accessibilityHidden(!graphVisible)
                            if !graphVisible {
                                ConversationView(model: model, presentation: .messages)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if !model.graphFullPage {
                            Divider()
                            ConversationView(model: model, presentation: .composer)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.contextInspectorVisible && !model.graphFullPage && area.size.width >= 900 {
                        Divider()
                        WorkContextInspector(model: model).frame(width: min(320, area.size.width * 0.29))
                    }
                }
            }
            .sheet(isPresented: Binding(get: {
                model.contextInspectorVisible && !model.graphFullPage && area.size.width < 900
            }, set: { model.contextInspectorVisible = $0 })) {
                WorkContextInspector(model: model)
                    .frame(width: DesktopSizing.sheetWidth(420), height: DesktopSizing.sheetHeight(620))
                    .onExitCommand { model.contextInspectorVisible = false }
            }
            .onAppear { if area.size.width < 900 { model.contextInspectorVisible = false } }
            .onChange(of: area.size.width < 900) { _, compact in
                if compact { model.contextInspectorVisible = false }
            }
        }
    }
}

struct ContextOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Retrieval", selection: $model.contextOptions.mode) {
                Text("Local search").tag("local")
                Text("Retrieval agent").tag("agent")
                Text("Off").tag("off")
            }
            if model.contextOptions.mode != "off" {
                Picker("Context budget", selection: $model.contextOptions.tokenBudget) {
                    Text("1,000 tokens").tag(1000)
                    Text("2,500 tokens").tag(2500)
                    Text("5,000 tokens").tag(5000)
                    Text("8,000 tokens").tag(8000)
                }
                if model.contextOptions.mode == "agent" {
                    Picker("Retrieval agent", selection: $model.contextOptions.agent) {
                        Text("Codex").tag("codex")
                        Text("Claude Code").tag("claude-code")
                    }
                    HStack {
                        TextField(model.contextOptions.agent == "codex" ? "Model ID · GPT-5.6 Luna if blank" : "Model ID · Haiku if blank", text: $model.contextOptions.model).textFieldStyle(.roundedBorder)
                        Menu {
                            Button(model.contextOptions.agent == "codex" ? "GPT-5.6 Luna (default)" : "Haiku (default)") { model.contextOptions.model = "" }
                            ForEach(model.availableModels.filter { $0.runner == model.contextOptions.agent }) { choice in
                                Button(choice.name) { model.contextOptions.model = choice.id }
                            }
                        } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton).fixedSize().help("Choose a retrieval model")
                    }
                    Text("Uses your connected agent to select sources. Choose a fast model to reduce latency and usage. Falls back to local search if unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Finds relevant evidence on this host within your budget. Original sources remain attached.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Automatic memory retrieval is off. Explicit attachments and reviewed project references remain included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.font(.callout).disabled(model.busy || model.preparingContext)
    }
}

struct WorkContextInspector: View {
    @Bindable var model: AppModel
    @State private var reviewNote: GraphNote?
    @State private var checkpointWork: WorkItem?
    @State private var showingOptions = false
    private var work: WorkItem? { model.currentWork }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.focusedContextReference != nil ? "Conversation source" : model.focusedMemory == nil ? "Context" : "Memory details").font(.callout.weight(.semibold))
                Spacer()
                if model.focusedMemory != nil || model.focusedContextReference != nil {
                    Button("Back to context") { model.focusedMemory = nil; model.focusedContextReference = nil }.labelStyle(.iconOnly).font(.caption)
                }
                Button { model.contextInspectorVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close inspector").accessibilityLabel("Close inspector")
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let ref = model.focusedContextReference { frozenConversation(ref) }
                    else if let note = model.focusedMemory { memoryDetails(note) }
                    else {
                        if let work { workDetails(work) }
                        contextDetails
                        if work == nil { ongoingWork }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(Palette.surface.opacity(0.45))
            .sheet(item: $reviewNote) { note in MemoryReviewSheet(model: model, note: note) }
            .sheet(item: $checkpointWork) { work in WorkCheckpointSheet(model: model, work: work) }
    }

    private var contextDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.validContextPreview != nil || model.displayedContextPack == nil ? "NEXT MESSAGE" : "LAST MESSAGE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showingOptions.toggle() } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("Retrieval options")
                    .popover(isPresented: $showingOptions) { ContextOptionsView(model: model).padding(20).frame(width: 340) }
            }
            if model.preparingContext {
                ProgressView("Finding relevant context…").controlSize(.small)
            } else if let pack = model.displayedContextPack {
                Text("\(pack.refs.count) sources · ~\(pack.estimatedTokens) tokens").font(.callout.weight(.medium))
                Text("\(pack.mode == "agent" ? "Retrieval agent" : "Local retrieval") · \(pack.elapsedMs) ms\(pack.cacheHit ? " · Cached" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
                if !pack.warning.isEmpty { Text(pack.warning).font(.caption).foregroundStyle(.secondary) }
                if pack.refs.isEmpty { Text("No relevant memories were selected.").font(.caption).foregroundStyle(.secondary) }
                ForEach(pack.refs) { ref in contextReference(ref) }
                if pack.refs.contains(where: { $0.kind == "memory" }) {
                    Button("View context in graph", systemImage: "point.3.connected.trianglepath.dotted") {
                        model.section = .graph; model.focusedMemory = nil
                    }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.accent)
                }
            } else {
                Text("Bring the right knowledge into this work.").font(.callout.weight(.medium))
                Text("Write a request below. Relevant memories will be selected when you send it, or you can preview them first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let options = model.contextOptions
            if !options.pinnedIds.isEmpty || !options.excludeIds.isEmpty {
                HStack {
                    Text("Next message: \(options.pinnedIds.count) pinned · \(options.excludeIds.count) excluded").font(.caption2).foregroundStyle(.secondary)
                    Button("Reset") {
                        var value = model.contextOptions; value.pinnedIds = []; value.excludeIds = []; model.contextOptions = value
                    }.buttonStyle(.plain).font(.caption2)
                }
            }
            Button("Preview next context", systemImage: "magnifyingglass") { Task { await model.prepareContext() } }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(model.preparingContext || model.busy || (model.conversationDrafts[model.conversationDraftKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !model.selectedConversationReferences.isEmpty {
                Divider()
                Text("Explicit attachments").font(.caption.weight(.semibold))
                ForEach(model.selectedConversationReferences) { ref in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ref.title).font(.caption)
                        Text(ref.agentName + " · " + userFacingPath(ref.origin)).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func contextReference(_ ref: ContextReference) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                if ref.kind == "memory" { Task { await model.inspectMemory(ref.id) } }
                else { model.focusedMemory = nil; model.focusedContextReference = ref }
            } label: {
                Text(ref.title).font(.callout.weight(.medium)).multilineTextAlignment(.leading)
            }.buttonStyle(.plain)
            Text(ref.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            Text(ref.reason).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Text(ref.kind == "conversation" ? "Conversation" : ref.status.capitalized).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { model.pinContext(ref.id) } label: {
                    Image(systemName: model.contextOptions.pinnedIds.contains(ref.id) ? "pin.fill" : "pin")
                }.help("Pin for subsequent messages").accessibilityLabel("Pin " + ref.title)
                Button { model.excludeContext(ref.id) } label: {
                    Image(systemName: model.contextOptions.excludeIds.contains(ref.id) ? "eye.slash.fill" : "eye.slash")
                }.help("Exclude from subsequent messages").accessibilityLabel("Exclude " + ref.title)
            }.buttonStyle(.borderless)
            DisclosureGroup("Sources") {
                ForEach(Array(ref.origins.enumerated()), id: \.offset) { _, origin in
                    Text("\(userFacingPath(origin.path)):\(origin.line)").font(.caption2).textSelection(.enabled)
                }
                Text("Digest: " + ref.digest).font(.system(size: 9, design: .monospaced)).textSelection(.enabled)
            }.font(.caption2).foregroundStyle(.secondary)
            Divider()
        }
    }

    private func frozenConversation(_ ref: ContextReference) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ref.title).font(.title3.weight(.semibold)).textSelection(.enabled)
            Text("Exact excerpt selected for this context pack.").font(.caption).foregroundStyle(.secondary)
            Text(ref.excerpt).font(.callout).textSelection(.enabled)
            Text(ref.reason).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(model.contextOptions.pinnedIds.contains(ref.id) ? "Unpin context" : "Pin to context", systemImage: "pin") { model.pinContext(ref.id) }
                Button(model.contextOptions.excludeIds.contains(ref.id) ? "Include next time" : "Exclude next time", systemImage: "eye.slash") { model.excludeContext(ref.id) }
            }.buttonStyle(.bordered).controlSize(.small)
            if ref.id.hasPrefix("native:"), let conversation = model.conversations.first(where: { "native:" + $0.id == ref.id }) {
                Button("Open conversation", systemImage: "bubble.left") { model.openConversation(conversation) }.buttonStyle(.plain).font(.caption)
            }
            Divider()
            Text("Original sources").font(.caption.weight(.semibold))
            ForEach(Array(ref.origins.enumerated()), id: \.offset) { _, origin in
                Text("\(userFacingPath(origin.path)):\(origin.line)").font(.caption2).textSelection(.enabled)
            }
            DisclosureGroup("Evidence digest") {
                Text(ref.digest).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }.font(.caption)
        }
    }

    private func memoryDetails(_ note: GraphNote) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(note.displayTitle).font(.title3.weight(.semibold)).textSelection(.enabled)
            HStack {
                Text((note.status ?? "reference").capitalized).font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
                Spacer()
                Button("Review…") { reviewNote = note }.font(.caption)
            }
            Text(note.body).font(.callout).textSelection(.enabled)
            HStack {
                Button(model.contextOptions.pinnedIds.contains(note.id) ? "Unpin context" : "Pin to context", systemImage: "pin") { model.pinContext(note.id) }
                    .disabled(["superseded", "retracted"].contains(note.status ?? "reference"))
                Button("View in graph") { model.requestedGraphNoteID = note.id; model.section = .graph }
            }.buttonStyle(.bordered).controlSize(.small)
            if let review = note.review {
                if let reason = review.reason, !reason.isEmpty { Text("Review: " + reason).font(.caption).foregroundStyle(.secondary) }
                if let replacement = review.supersededBy, !replacement.isEmpty {
                    Button("View replacement") { Task { await model.inspectMemory(replacement, showGraph: true) } }.font(.caption)
                }
                if let history = review.history, !history.isEmpty {
                    DisclosureGroup("Review history") {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.status.capitalized + " · " + event.updatedAt).font(.caption2).foregroundStyle(.secondary)
                                Text(event.reason).font(.caption).textSelection(.enabled)
                            }.padding(.vertical, 5)
                        }
                    }.font(.caption)
                }
            }
            Divider()
            Text("Original sources").font(.caption.weight(.semibold))
            ForEach(Array(note.origins.enumerated()), id: \.offset) { _, origin in
                VStack(alignment: .leading, spacing: 4) {
                    Text(origin.provider).font(.caption.weight(.medium))
                    Text("\(userFacingPath(origin.path)):\(origin.line)").font(.caption2).textSelection(.enabled)
                }
            }
            DisclosureGroup("Record details") {
                Text(note.id).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                Text("Imported evidence. Review status does not grant an agent permission to act.").font(.caption2).foregroundStyle(.secondary)
                if !note.topics.isEmpty { Text(note.topics.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
            }.font(.caption)
        }
    }

    private func workDetails(_ work: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CURRENT WORK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(work.objective).font(.callout).textSelection(.enabled)
            if let checkpoint = work.checkpoint {
                if !checkpoint.summary.isEmpty { Text(checkpoint.summary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if !checkpoint.nextAction.isEmpty {
                    Text("Next action").font(.caption.weight(.semibold))
                    Text(checkpoint.nextAction).font(.caption).textSelection(.enabled)
                }
                if !checkpoint.runIds.isEmpty {
                    DisclosureGroup("\(checkpoint.runIds.count) supporting runs") {
                        ForEach(checkpoint.runIds, id: \.self) { id in
                            Button(model.runs.first { $0.id == id }?.task ?? "View run") { model.focusedRunID = id; model.section = .runs }.font(.caption2).lineLimit(2)
                        }
                    }.font(.caption)
                }
            }
            HStack {
                Menu("Continue with…") {
                    Button("Codex") { Task { await model.continueWork(work, agent: "codex") } }
                    Button("Claude Code") { Task { await model.continueWork(work, agent: "claude-code") } }
                }.menuStyle(.borderlessButton).fixedSize().disabled(model.busy || model.runs.contains(where: \.isActive))
                Spacer()
                Button("Edit checkpoint") { checkpointWork = work }.buttonStyle(.plain)
            }.font(.caption)
            Text("Continuation opens a fresh session with this checkpoint. Review source evidence as you go.").font(.caption2).foregroundStyle(.secondary)
            Divider()
        }
    }

    private var ongoingWork: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("ONGOING WORK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("See all") { model.section = .insights }.buttonStyle(.plain).font(.caption2)
            }
            if model.workItems.isEmpty && model.conversations.isEmpty {
                Text("Start with a request below. Your objective and progress stay connected across sessions.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.workItems.filter { $0.status != "completed" }.prefix(5)) { item in
                Button { model.openWork(item) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.callout).lineLimit(2)
                        Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            ForEach(model.conversations.filter { $0.workId == nil }.prefix(3)) { conversation in
                Button(conversation.title) { model.openConversation(conversation) }.buttonStyle(.plain).font(.callout).lineLimit(2)
            }
        }
    }
}

struct MemoryReviewSheet: View {
    @Bindable var model: AppModel
    let note: GraphNote
    @Environment(\.dismiss) private var dismiss
    @State private var status = "accepted"
    @State private var reason = ""
    @State private var replacement = ""
    @State private var saving = false
    @State private var error: String?
    @State private var workspaceID = ""
    @State private var host = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review memory").font(.title2.weight(.semibold))
            Text(note.displayTitle).font(.callout).lineLimit(2)
            Picker("Status", selection: $status) {
                Text("Accepted").tag("accepted")
                Text("Reference").tag("reference")
                Text("Superseded").tag("superseded")
                Text("Retracted").tag("retracted")
            }
            TextField("Reason for this review", text: $reason, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...5)
            if status == "superseded" { TextField("Replacement memory ID", text: $replacement).textFieldStyle(.roundedBorder) }
            Text("Superseded and retracted memories remain available as evidence and are excluded from automatic retrieval.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save review") { Task { await save() } }.buttonStyle(.borderedProminent)
                    .disabled(saving || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (status == "superseded" && replacement.isEmpty))
            }
        }.padding(26).frame(width: 480)
            .onAppear { status = note.status ?? "reference"; workspaceID = model.selectedID ?? ""; host = model.terminalHost }
    }
    private func save() async {
        guard !workspaceID.isEmpty else { return }
        let wid = workspaceID
        saving = true; defer { saving = false }
        do {
            var params: [String: Any] = ["workspaceId": wid, "noteId": note.id, "status": status, "reason": reason]
            if status == "superseded" { params["supersededBy"] = replacement.trimmingCharacters(in: .whitespacesAndNewlines) }
            let result = try await model.terminalCall("knowledge.review", params, host: host, as: GraphNote.self)
            if model.selectedID == wid && model.terminalHost == host {
                model.focusedMemory = result; model.contextPreview = nil
                if ["superseded", "retracted"].contains(status) {
                    var options = model.contextOptions; options.pinnedIds.removeAll { $0 == note.id }; model.contextOptions = options
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct WorkCheckpointSheet: View {
    @Bindable var model: AppModel
    let work: WorkItem
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var objective = ""
    @State private var status = "active"
    @State private var summary = ""
    @State private var nextAction = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Work checkpoint").font(.title2.weight(.semibold))
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            TextField("Objective", text: $objective, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            Picker("Status", selection: $status) {
                Text("Active").tag("active"); Text("Needs review").tag("needs_review")
                Text("Paused").tag("paused"); Text("Completed").tag("completed")
            }
            Text("Progress and decisions").font(.caption.weight(.medium))
            TextEditor(text: $summary).font(.callout).frame(height: 130).border(Palette.line)
            TextField("Next action", text: $nextAction, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            Text("Keep verified progress distinct from plans. Supporting run links are preserved.").font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save checkpoint") {
                    Task {
                        if await model.perform("work.update", ["id": work.id, "title": title, "objective": objective, "status": status,
                            "checkpoint": ["summary": summary, "nextAction": nextAction, "runIds": work.checkpoint?.runIds ?? []]]) { dismiss() }
                    }
                }.buttonStyle(.borderedProminent).disabled(model.busy || title.isEmpty || objective.isEmpty)
            }
        }.padding(26).frame(width: 540)
            .onAppear { title = work.title; objective = work.objective; status = work.status; summary = work.checkpoint?.summary ?? ""; nextAction = work.checkpoint?.nextAction ?? "" }
    }
}
