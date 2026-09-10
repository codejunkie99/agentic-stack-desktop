# Workspace (live task state)

> Replace this template on your first real task. The dream cycle auto-archives
> this file after 2 days of inactivity — don't keep long-lived notes here.

## Current task
Simplify and harden the native macOS product: keep workspace navigation stable in every layout, route every visible action to the correct destination, improve the model router/picker, expose personal memory, and make multimodal context explicit and inspectable.

## Open files
- `harness_manager/context_mcp.py`
- `harness_manager/assets/agentic-stack-context/SKILL.md`
- `apps/macos/Sources/AgenticWorkspaces/SpotlightSearchView.swift`
- `apps/macos/Sources/AgenticWorkspaces/IntegrationsView.swift`
- `apps/macos/Sources/AgenticWorkspaces/GraphWorkView.swift`
- `apps/macos/Sources/AgenticWorkspaces/StackDesktopRoot.swift`
- `apps/macos/Sources/AgenticWorkspaces/DesktopNavigation.swift`
- `apps/macos/Sources/AgenticWorkspaces/AgentEditorView.swift`
- `harness_manager/workspaces/model_router.py`
- `harness_manager/workspaces/personal_memory.py`
- `apps/macos/Sources/AgenticWorkspaces/LoopManagementView.swift`
- `apps/macos/Sources/AgenticWorkspaces/ProjectAccess.swift`
- `harness_manager/workspaces/memory_control.py`

## Active hypotheses
- A single read-only MCP call can make cross-tool recall feel native while retaining exact source provenance.
- The desktop should browse, filter, connect, and audit context; agents should answer from the retrieved evidence.
- Completed work should propose useful memory automatically, while acceptance remains an explicit owner decision.
- Workspace tabs should live in one persistent root header so Graph full-page mode cannot hide sibling routes.
- Auto routing should explain the selected model for the current message while fixed model selection stays searchable and direct.

## Checkpoints
- [x] Trace the live conversation, subagent, graph-memory, personal-memory, and MCP paths.
- [x] Add one-call contextual recall with exact bounded evidence and provenance.
- [x] Add native tool, model, role, and project-scope filtering.
- [x] Polish the context-source and search surfaces.
- [x] Keep every Work subtab visible and horizontally reachable at narrow widths.
- [x] Stage provenance-bearing learning candidates from explicit completed-run findings.
- [x] Audit every visible workspace route and all 60 native RPC actions.
- [x] Bound loop filesystem reads and persist access to user-selected project folders.
- [x] Limit desktop integrations and project adapters to Claude Code, Codex, OpenCode, and Cursor.
- [x] Publish and verify desktop preview 9.
- [x] Consolidate workspace headers and remove duplicate navigation behavior.
- [x] Verify every visible route in the running app at compact and wide sizes.
- [x] Ship the redesigned model picker and personal memory workspace.
- [x] Verify multimodal attachment manifests reach the selected agent with provenance.
- [x] Publish and independently verify desktop preview 10.

## Next step
Use real conversations to tune the transparent model-routing signals and personal-memory ranking.
