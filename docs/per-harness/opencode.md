# OpenCode setup

## What the adapter installs
- `AGENTS.md` at project root (pointing at `.agent/`)
- `opencode.json` with instruction list and permission rules

## Install
```bash
./install.sh opencode
```

## How it works
OpenCode natively reads `AGENTS.md` and the `instructions` array in
`opencode.json`. The permission rules deny the most destructive commands
and ask before any push.

## Troubleshooting
- If `opencode.json` is rejected, check the schema URL at the top matches
  your OpenCode version.
- The permission syntax uses glob-style matching. Test denies with
  `opencode --dry-run` first.
