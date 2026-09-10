# Writing Skills

The skill is the unit of learned behavior. Good ones compound; bad ones
rot. Rules below keep you honest.

## Anatomy of a skill
```
skills/<name>/
├── SKILL.md         # instructions, YAML frontmatter + body
└── KNOWLEDGE.md     # (optional) accumulated local lessons
```

## Frontmatter
```yaml
---
name: deploy-checklist
version: 2026-01-01
triggers: ["deploy", "ship", "release"]
tools: [bash]
preconditions: ["all tests passing"]
constraints: ["requires human approval for production"]
---
```

Every field matters. The manifest generator reads them; the pre-call hook
enforces `constraints`.

## Destinations and fences, not driving directions

**Bad (micromanagement):**
> 1. Run `npm test`. 2. Grep for "passed". 3. Run `git add -A`. 4. ...

**Good (structure):**
> Verify tests pass before committing. Stage specific files (no `-A`).
> Write messages that explain the *why*, not the *what*.

Why: the first form rots when tooling changes. The second form stays true
across refactors.

## Every skill ends with a self-rewrite hook
```markdown
## Self-rewrite hook
After every 5 uses OR on any failure:
1. Read the last N skill-specific episodic entries.
2. If a new failure mode has appeared, append to `KNOWLEDGE.md`.
3. If a constraint was violated, escalate to `semantic/LESSONS.md`.
4. Commit: `skill-update: <name>, <one-line reason>`.
```

## Registering a new skill
1. Add an entry to `skills/_index.md` (human-readable).
2. Append a line to `skills/_manifest.jsonl` (machine-readable).
3. Log the decision in `memory/semantic/DECISIONS.md`.

## Anti-patterns
- Skills that duplicate each other's triggers (progressive disclosure breaks).
- Skills with procedural step-by-step commands (bitter lesson — the model
  gets better, your scripts don't).
- Skills that modify `protocols/permissions.md` (only humans edit that file).
