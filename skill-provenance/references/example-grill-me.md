# Worked example: tracing `grill-me`

Local state:
- `~/.hermes/skills/grill-me/` — `SKILL.md` is 7 lines, plus `agents/openai.yaml`.
- No `author`/`license` field in either file.
- `git log`: not a git repository.
- Created: 2026-08-30 00:57:09 (SAME second as `grilling/` sibling).

Smoking gun in `~/.hermes/logs/agent.log`:
```
... conversation turn: ... msg='npx skills@latest add mattpocock/skills --skill=grill-me'
```

Upstream resolution:
- Repo: `mattpocock/skills` (MIT license, "Skills for Real Engineers").
- Real path: `skills/productivity/grill-me/SKILL.md` (NOT repo root — repo-root `tree/main/grill-me` 404s).
- Engine `grilling`: `skills/productivity/grilling/SKILL.md`.

Verification:
- Local `grill-me/SKILL.md` == upstream raw `SKILL.md` (verified identical).
- Thin shell by design: frontmatter + `Call the Skill tool with "grilling".` Delegates to `grilling`, the actual interview engine.

Conclusion delivered to user: author is Matt Pocock; local install is complete, not truncated.
