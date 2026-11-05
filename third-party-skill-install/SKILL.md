---
name: third-party-skill-install
description: "Install skills.sh / npx third-party skills into Hermes."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, skills, install, skills.sh, npx, agents-dir]
    related_skills: [hermes-agent]
---

# Installing Third-Party Skills into Hermes

## When to Use

Use when a third-party skill must be installed into Hermes — `npx skills` / skills.sh output, a GitHub skill repo, or any skill that landed in a `.agents/skills/` directory. Also use when an installed skill does not appear in `hermes skills list` or is missing from the available-skills index.

Not for skills authored inside Hermes — those go through `skill_manage(action='create')`.

## The two layouts

| Install path | Lands in | Hermes reads it? |
|---|---|---|
| `npx skills add <owner>/<repo> --skill=<name>` | `<project>/.agents/skills/<name>/` | Only if that project is **trusted** |
| `hermes skills install <owner>/<repo>/<skill>` | `$HERMES_HOME/skills/` | Yes |
| Manual copy | `$HERMES_HOME/skills/<category>/<name>/` | Yes |

Hermes loads skills from `$HERMES_HOME/skills/` — either `<category>/<name>/SKILL.md` or a flat `<name>.md`.
It also supports project-local `./.hermes/skills` and `./.agents/skills`, **but only for trusted projects** (`hermes skills trust`), and trust requires the directory to be a **git checkout**.

Always resolve the real home from `$HERMES_HOME` — never hardcode `~/.hermes` (profiles use `~/.hermes/profiles/<name>/`).

## Procedure

### 1. Install

```bash
npx skills@latest add <owner>/<repo> --skill=<name> --yes
```

- Always pass `--yes`. Without a detected agent the CLI goes interactive and hangs.
- **Verify what actually landed** with `ls .agents/skills/` — do not trust `--skill=`. It is honoured on some versions and silently ignored on others (one run installed the entire 37-skill suite despite `--skill` naming a single skill).
- Transient `curl 28 ... github.com port 443` failures are common on proxied networks. Retry the clone before concluding the install failed.

### 2. Decide the bridge

```bash
git -C <project-root> rev-parse --show-toplevel
```

- **Is a git repo** → `hermes skills trust <project-root>`. Done; the `.agents/skills` skills now load. No copying needed.
- **Not a git repo** → trust cannot apply (`Not inside a git checkout`). Copy the skill into Hermes's own skill directory instead.

### 3. Copy into a dedicated category — never flat

Before copying, list what is already there:

```bash
hermes skills list
ls $HERMES_HOME/skills/
```

Copy to `$HERMES_HOME/skills/<suite>/<name>/`, i.e. a category folder named after the suite.

**Why not flat:** a flat `$HERMES_HOME/skills/<name>/` can collide with an *existing category directory* of the same name. A skill named `research` copied flat lands on top of an existing `research/` category that already holds other skills, mixing them together. A dedicated category isolates the whole suite and makes it removable as one unit.

Preserve the full skill directory — sibling files (templates the SKILL.md links, `agents/`, `references/`) are part of the skill and are lost if only `SKILL.md` is copied.

### 4. Verify

```bash
hermes skills list | grep -i <category>
```

Every skill should report `local | local | enabled`. Also re-check that any pre-existing same-named category is intact.

### 5. Activation

Hermes has **no mid-session skill reload** — a newly installed skill enters the index on the **next** session. In the current session, load it explicitly with `skill_view(name=...)`.

## Pitfalls

- **`disable-model-invocation: true` is ignored by Hermes.** Claude-style frontmatter does not suppress the skill; it still appears in the available-skills list. User-invoked-only skills from other ecosystems get advertised anyway.
- **Budgets add up.** Every registered skill's name + description is injected into every session's system prompt. A 37-skill suite costs roughly 5.3k characters (~1.3k tokens) per session. Install whole suites deliberately, and prefer one removable category over scattered flat copies.
- **`--skill` filtering is unreliable** (see step 1) — always verify the install directory afterwards.
- **Symlinking is more fragile than copying** here; a real copy is simpler to verify and reason about.
