---
name: kanban-orchestration
description: "Use when driving or demoing Hermes Kanban task boards."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [kanban, orchestration, multi-agent, background-systems, lifecycle, demo]
---

# Kanban Orchestration (Hermes)

Practical operating guide for Hermes Kanban — the durable SQLite-backed multi-agent task board. Complements the bundled `hermes-agent` skill's `references/background-systems.md` (authoritative for the full CLI surface); this skill carries the VERIFIED end-to-end recipe and observed behaviors not spelled out in the docs.

## When to use

- User asks how kanban works / how to use it (explain, then verify local state first)
- User wants a project run through the full lifecycle (triage → todo → ready → running → blocked → done → archived)
- Orchestrating multi-profile work: research pipelines, batch tasks, role pipelines with retries, human-in-the-loop queues

## Two interfaces (state this first when explaining)

| Who | Interface |
|---|---|
| Human | `hermes kanban <verb>`, `/kanban <verb>` in chat, `hermes dashboard` → Kanban tab |
| Agent worker | `kanban_*` tools injected by the dispatcher (`HERMES_KANBAN_TASK` env) — workers NEVER shell out to `hermes kanban` |

Both read/write the same board: `~/.hermes/kanban.db` (default board; multi-board under `~/.hermes/kanban/boards/<slug>/`). Task statuses: `triage | todo | ready | running | blocked | done | archived`.

## Prerequisites (verify before promising a demo)

```bash
hermes kanban boards list     # board exists?
hermes gateway status         # gateway must be running — dispatcher lives inside it (kanban.dispatch_in_gateway: true, tick default 60s)
```

Without a running gateway, ready tasks sit until gateway starts (create warns about this).

## Verified full-lifecycle demo recipe

Ran end-to-end successfully (2026-08). Each step maps to a lifecycle state.

1. **triage** — park a rough idea:
   ```bash
   hermes kanban create "标题" --triage --body "粗略想法……"
   ```
2. **todo** — flesh it out with the aux LLM (works out of the box; no `auxiliary.kanban_decomposer` config needed):
   ```bash
   hermes kanban specify <id>    # rewrites title+body into Goal/Approach/Acceptance criteria, promotes triage→todo
   ```
3. **todo→ready via dependency chain** — create children under the parent:
   ```bash
   hermes kanban create "子任务1" --assignee <profile> --parent <parent_id> --max-runtime 5m
   hermes kanban create "子任务2" --assignee <profile> --parent <parent_id> --initial-status blocked
   hermes kanban complete <parent_id> --result "聚合节点完成"
   ```
   Completing the parent auto-promotes children to `ready` (see pitfalls #1).
4. **blocked → ready (human gate)**:
   ```bash
   hermes kanban block <id> "需要人工确认……"    # or create with --initial-status blocked
   hermes kanban unblock <id>
   ```
5. **ready → running** — don't wait for the 60s tick:
   ```bash
   hermes kanban dispatch        # single manual scan: reclaims stale claims, promotes, spawns workers
   ```
   Dispatcher spawns one independent full Hermes process per task (assignee profile) in a scratch workspace at `~/.hermes/kanban/workspaces/<id>/`.
6. **watch + verify completion**:
   ```bash
   hermes kanban watch           # live event stream — NEVER exits; background it and kill later
   hermes kanban runs <id>       # attempt history, one row per try (human gates show as rows too)
   hermes kanban show <id>       # status, Result, comments, events
   ```
7. **archived**:
   ```bash
   hermes kanban archive <id>... # hides from default list; `list --archived` still shows
   hermes kanban stats           # board-wide counts
   ```

Timing reference: simple terminal-only tasks ~17s; tasks that read cloud docs + write results ~3min (deepseek-v4-flash worker). Keep demo tasks small; use `--max-runtime` as a cap.

## Pitfalls & observed behaviors (not spelled out in the docs)

1. **Dependency promote pushes BLOCKED children to ready too.** Docs promise "todo → ready" when parents complete; observed: a child created with `--initial-status blocked` was ALSO auto-promoted on parent completion. If a child must stay blocked, (re)apply `block` AFTER the parent completes.
2. **specify auto-promotes further.** After `specify`, the task keeps going to `ready` (event `promoted`). Safe — ready tasks with no assignee are never dispatched.
3. **Workers inherit the full profile** — skills, tools, model, memory. In the demo a worker actually pulled WPS cloud-doc data mid-task. Always scope task bodies explicitly (Goal/Approach/Acceptance criteria — `specify` generates these), or the worker may do more than you expect.
4. **scratch workspaces are deleted on completion** (`tip_scratch_workspace` event warns on first scratch create). Deliver files via `kanban_complete(artifacts=...)` or use `--workspace worktree|dir:/abs/path` to keep output.
5. **`stats` labels the todo state "scheduled"** in its status counts (cosmetic divergence from `list`).
6. **`hermes kanban daemon` is deprecated** — use the gateway. Running both against the same db = unsupported claim races.
7. **`--parent` children land in `todo`**; only parent completion (or explicit promotion) moves them to `ready`.
8. **Multi-board isolation**: `HERMES_KANBAN_BOARD` is pinned in worker env; `--board <slug>` selects for CLI ops; slug is immutable (rename only changes display name).

## Verification

```bash
hermes kanban list --archived   # confirm archive worked (default list hides archived)
hermes kanban stats             # counts back to zero after archiving everything
hermes kanban runs <id>         # attempt history proves execution really happened
```

## Reference

- `references/lifecycle-demo.md` — full worked example from the first verified run: exact commands, observed events, the WPS cloud-doc worker example, archive/cleanup.
- Authoritative docs: bundled `hermes-agent` skill → `references/background-systems.md`; https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban
