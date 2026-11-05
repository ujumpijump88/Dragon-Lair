---
name: hermes-kanban-workflows
description: "Use when driving Hermes Kanban boards (create/dispatch)."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [kanban, hermes, multi-agent, orchestration, lifecycle, dispatcher]
---

# Hermes Kanban Workflows

Hands-on companion to the bundled `hermes-agent` skill (its `references/background-systems.md` + docs page `user-guide/features/kanban` cover the API; this skill carries **verified hands-on quirks** discovered by actually running the full lifecycle). Read the docs for reference depth; this for what actually happens on this machine.

## When to use

- User asks how to use kanban / wants a demo of the lifecycle / wants to offload work to profile workers that survive restarts.
- Multi-agent tasks: 投想法 → 细化 → 拆子任务 → 并行执行, with human checkpoints.

## Human vs agent interface

| Who | Interface |
|---|---|
| Human | `hermes kanban <verb>`, `/kanban <verb>` in chat, `hermes dashboard` → Kanban tab |
| Worker (agent) | `kanban_*` tools injected when dispatcher spawns it (`HERMES_KANBAN_TASK` env). Workers NEVER shell `hermes kanban`. |

Workers are **full OS processes of the assigned profile** and inherit ALL that profile's skills/tools — in testing a worker actually read WPS cloud docs and real data from the user's business folders.

## Verified end-to-end lifecycle recipe (this session)

```bash
# 0. Preflight — gateway must run the embedded dispatcher
hermes gateway status          # "Gateway is running" required
hermes kanban boards list      # 'default' board exists

# 1. Park a rough idea in triage
hermes kanban create "想法标题" --triage --body "粗略想法..."

# 2. Flesh it out → todo (auxiliary LLM rewrites title+body with Goal/Approach/Acceptance criteria)
hermes kanban specify <id>

# 3. Decompose into children (dependency chain)
hermes kanban create "子任务A" --assignee <profile> --parent <parent_id> --max-runtime 5m
hermes kanban create "子任务B" --assignee <profile> --parent <parent_id> --initial-status blocked

# 4. Parent done → children auto-promote todo→ready
hermes kanban complete <parent_id> --result "聚合节点完成，触发子任务"

# 5. Dispatch NOW (skip the 60s tick) → workers spawn → running → done
hermes kanban dispatch         # read Reclaimed/Crashed/Spawned counts

# 6. Human checkpoint: block, then unblock
hermes kanban block <id> "需要人工确认方向"
hermes kanban unblock <id>

# 7. Review + archive
hermes kanban show <id>; hermes kanban runs <id>
hermes kanban archive <id>...  # hides from default list; list --archived to see
hermes kanban stats            # board zeroed after archiving everything
```

Live event stream: `hermes kanban watch` (never exits — run backgrounded, tail the log).

## Quirks & pitfalls (verified, do not re-discover)

1. **Parent completion promotes ALL children — including `blocked` ones.** Docs say todo→ready; in practice a child created with `--initial-status blocked` also flipped to ready when the parent completed. Re-`block` it if the human checkpoint must hold.
2. **`specify` auto-promotes to `ready`** (events: created→specified→promoted) even with no assignee. Safe: unassigned ready tasks are never dispatched, but don't be surprised by the state.
3. **Worker result summaries are self-reports — verify file-level claims.** A worker reported a project README "corrupted/garbled"; byte-level checks (`file`, python decode) proved it perfectly intact (the worker had been misled by `read_file` judging the emoji-headed file binary). Verify before acting on a worker's defect claims.
4. **`stats` labels the `todo` state as `scheduled`** — same state, different display word. Not a bug.
5. **scratch workspace is deleted on completion** (`~/.hermes/kanban/workspaces/<id>`; `tip_scratch_workspace` event warns). Preserve output with `kanban_complete(artifacts=[...])`, or create with `--workspace worktree|dir:/abs/path`.
6. **`dispatch` output sanity check**: `Reclaimed / Crashed / Timed out / Stale / Auto-blocked / Promoted / Spawned` — read `Spawned` to confirm workers actually launched.
7. Runs history shows every attempt incl. the initial `blocked` one — useful audit trail for "who touched this".
8. Auxiliary-LLM ops (`specify`/`decompose`) need an auxiliary client; if it's missing they fail with `ok=false` — check `auxiliary.*` in config.yaml rather than assuming.
9. **auto-decomposer inherits the parent's workspace_kind** — a parent created with `--workspace worktree` yields worktree children even when `create` defaults to scratch. If the board's default_workdir is not a git repo, every spawn fails (`workspace_kind=worktree but ... default_workdir ... is not inside a git repo`), hits `failure_limit`, and the task auto-flips to `blocked` — looks like a content problem, is purely a workspace/git mismatch. Fix: `sqlite3 ~/.hermes/kanban.db "UPDATE tasks SET workspace_kind='scratch', workspace_path=NULL, branch_name=NULL WHERE id IN (...)"` (back up the db first), then `hermes kanban unblock <id>` + `dispatch`. Verify with `Spawned: N` and task → running. Rule of thumb: only use `--workspace worktree` when the task's working dir is a real git repo.

## Useful create flags

`--triage`, `--initial-status blocked|running`, `--parent <id>` (repeatable), `--assignee <profile>`, `--workspace scratch|worktree|worktree:<path>|dir:<abs>`, `--max-runtime 30m`, `--max-retries N`, `--skill <name>` (repeatable), `--idempotency-key KEY`, `--priority N`.

## Sleep & power: keep long-running workers alive

macOS auto-sleep (`pmset -g` → `sleep 1` + `displaysleep 5`) freezes worker processes AND the embedded dispatcher mid-run: API connections drop, the worker dies, `consecutive_failures` accumulates and a long task can trip the circuit breaker into `blocked`. Progress is not resumed — the rerun starts over. Long task chains MUST be guarded against sleep. `caffeinate` does NOT stop lid-close sleep (physical limit — needs clamshell/external display).

Verified pattern (deployed 2026-08): `scripts/kanban-nosleep-guard-adaptive.sh`
1. Copy to `~/.hermes/scripts/`, `chmod +x`, run once — with tasks active it starts `caffeinate -dims` and records its pid in `.kanban-caffeinate.pid` (pid-file ownership ⇒ never kills a caffeinate it didn't start; stale-pid self-cleanup).
2. Register cron: `cronjob(action='create', no_agent=true, script='kanban-nosleep-guard-adaptive.sh', schedule='every 5m', name='kanban-防休眠看护')`. no_agent + silent-output script = zero-noise watchdog (only status changes emit output).
3. Verify: `pmset -g assertions | grep caffeinate` shows PreventSystemSleep / PreventUserIdleSystemSleep / PreventUserIdleDisplaySleep / PreventDiskIdle. Re-run the script while caffeinate is alive → must stay silent (idempotent, no duplicate). Manual `cronjob action='run'` → ok + silent.
4. Caveats: lid-close still sleeps; `-s` system-sleep prevention is most reliable on AC — plug in for long runs; task chain reaching terminal states (done/blocked) auto-releases the guard.

## Reference docs

- Docs: https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban (+ kanban-tutorial)
- Bundled skill: `hermes-agent` → `references/background-systems.md` (kanban section)
