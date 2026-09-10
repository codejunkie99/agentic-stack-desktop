# Hermes Agent setup

[Hermes Agent](https://github.com/nousresearch/hermes-agent) (Nous
Research) is an open-source AI agent with persistent memory and a
closed learning loop. Our adapter layers the portable `.agent/` brain
on top so you keep one knowledge base across harnesses.

## What the adapter installs
- `AGENTS.md` at project root (Hermes reads this natively)

## Install
```bash
./install.sh hermes
```

## How it works
- Hermes reads `AGENTS.md` as workspace-level project context.
- Skills under `.agent/skills/` follow frontmatter-plus-body that is
  compatible with the agentskills.io standard Hermes uses. Browse via
  `/skills` in the Hermes CLI.
- Hermes's own `MEMORY.md` / `USER.md` / `SOUL.md` are complementary —
  treat `.agent/memory/` as the source of truth and mirror selectively.

## Troubleshooting
- If `AGENTS.md` isn't picked up, run `hermes setup` — the wizard can
  re-register workspace-level context files.
- Hermes supports multiple models via its gateway. The portable brain
  doesn't care which one you use.
