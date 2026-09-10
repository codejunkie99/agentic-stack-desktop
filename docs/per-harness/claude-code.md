# Claude Code setup

## What the adapter installs
- `CLAUDE.md` at project root
- `.claude/settings.json` with `PostToolUse` and `Stop` hooks

## Install
```bash
./install.sh claude-code
```

## Hook behavior
- After every `Bash | Edit | Write` tool call: logs to episodic memory.
- On session end (`Stop`): runs the dream cycle.

## Customizing
Edit `.claude/settings.json` to add matchers or denies. The `permissions.deny`
list is the Claude-Code-level fence; `.agent/protocols/permissions.md` is
the content-level fence read by the model. Use both.

## Troubleshooting
- If hooks don't fire, check `claude settings` reports the merged config
  includes your entries.
- If the agent ignores `CLAUDE.md`, Claude Code may need a version that
  supports project-root memory.
