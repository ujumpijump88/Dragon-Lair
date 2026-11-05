---
name: skill-provenance
description: Trace who made a Hermes skill when its file lacks an author.
---

When a user points at a skill in `~/.hermes/skills/` and asks who made it or where it came from, the skill file will almost never tell you. Community skills (e.g. mattpocock/skills) ship a bare frontmatter with no author, license, or copyright header. Trace the origin with this forensic chain, in order:

## Workflow

1. **Read the file first.** `read_file` the `SKILL.md` frontmatter. Confirm there is genuinely no `author`/`license` field. Note `disable-model-invocation` / `policy.allow_implicit_invocation` flags and any `agents/openai.yaml` (Codex/Claude dual-harness metadata) as provenance hints, but they name no human.

2. **git check (usually a dead end, do it fast).** `cd <skill_dir> && git log` and check the parent `~/.hermes/skills/.git`. Skills copied or installed into `~/.hermes/skills` are almost never their own git repo, so this returns "not a git repository". Don't linger.

3. **Timestamp clustering.** `stat -f "%SB" <file>` (macOS) / `stat -c %w` (Linux). Skills installed by one command often share a creation second. Cross-check sibling skill dirs and `~/.hermes/cron/output/*` timestamps created within the same minute: a same-second cluster points to a single install event, not hand-authoring.

4. **Trace the install command in logs (the smoking gun).** grep the Hermes logs for the skill name:
   - `~/.hermes/logs/agent.log` records `conversation turn: ... msg='npx skills@latest add <author>/skills --skill=<name>'` or `hermes skills install <catalog>`. This names the source author/repo authoritatively.
   - Also grep `gateway.log`, `desktop.log` for the skill name to catch invocation context.
   The install command is more reliable than the file: it survives even when the file has no metadata.

5. **Resolve the real upstream path.** The local dir name may NOT match the repo path. `npx skills add mattpocock/skills --skill=grill-me` lands at `~/.hermes/skills/grill-me`, but upstream it lives at `skills/productivity/grill-me/SKILL.md` (not repo root). Fetch the repo tree via `https://api.github.com/repos/<author>/<repo>/git/trees/main?recursive=1` and grep for the skill name to find its true path. Do NOT assume `github.com/<author>/<repo>/tree/main/<name>` — that 404s.

6. **Confirm completeness.** `web_extract` the raw `SKILL.md` (`https://raw.githubusercontent.com/<author>/<repo>/main/<path>/SKILL.md`) and diff against local. A 7-line SKILL.md that "just calls another skill" is often intentional: a thin user-entry shell delegating to the real engine (e.g. `grill-me` → `grilling`), NOT a truncated/broken install. Verify before reporting "broken".

## Pitfalls
- Do not conclude "no author" from the file alone. The install command in `agent.log` is the authoritative source.
- Do not 404-panic on the repo-root path. Skills are nested under category folders (productivity, engineering, ...).
- `npx skills@latest` may pull a version newer/older than what is installed. For *provenance* that is fine; for *diffing to detect breakage* pin to the commit referenced in the log if present.
- A very short SKILL.md that delegates to a sibling skill is a design pattern, not corruption.

## See also
- `references/example-grill-me.md` — a concrete end-to-end trace of the `grill-me` skill back to mattpocock/skills.
