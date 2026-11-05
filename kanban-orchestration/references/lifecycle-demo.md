# Kanban lifecycle demo — first verified run (2026-08-09)

Session origin: user asked "[kanban]怎么使用？" then "triage 想法池在哪里？…这套流程可以跑个项目尝试下吗". Setup: default board already initialized, gateway already running (embedded dispatcher) → everything worked with zero additional config.

## Board state at start

```
hermes kanban boards list  → ● default (empty)
hermes gateway status      → ✓ Gateway is running (PID 36573)
```

## Commands run (in order) with observed output

1. `hermes kanban create "2025年食堂满意度测评分析与改进" --triage --body "粗略想法……"` → `Created t_087cb65a (triage, assignee=-)`
2. `hermes kanban specify t_087cb65a` → `Specified t_087cb65a → todo — retitled: '分析2025年食堂满意度测评并提出改进建议'`
   - Body rewritten into **Goal / Approach / Acceptance criteria / Out of scope** markdown (a real, useful spec).
   - Event log: `created` → `specified` → `promoted`; final status `ready` (unassigned, so never dispatched — safe).
   - Config had NO auxiliary kanban specifier entry (only `auxiliary.vision` / `skills_hub`); specify still worked.
3. Children:
   - `hermes kanban create "盘点 CanteenMenu 项目并输出结构摘要" --assignee default --parent t_087cb65a --max-runtime 5m` → `Created t_38a62799 (todo, assignee=default)`
   - `hermes kanban create "撰写满意度改进建议初稿" --assignee default --parent t_087cb65a --initial-status blocked` → `Created t_4376de5b (blocked, assignee=default)`
4. `hermes kanban complete t_087cb65a --result "聚合节点完成"` → **both** children auto-promoted to `ready` — including the blocked one (SKILL.md pitfall #1). Re-blocked manually: `hermes kanban block t_4376de5b "需要人工确认改进建议的方向后再执行（blocked 演示）"`.
5. `hermes kanban dispatch` → `Reclaimed: 0 / Crashed: 0 / Timed out: 0 / Stale: 0 / Auto-blocked: 0 / Promoted: 0 / Spawned: 1 - t_38a62799 -> default @ /Users/xiebojun/.hermes/kanban/workspaces/t_38a62799`; `list` shows `● running`.
6. Worker 1 finished in 17s (`runs` → `1 completed default 17s`). Result was a real inventory of ~/CanteenMenu (app.py 971 lines, meal_plan.py, nutrition.py, pricing.py, health_tags.py, export_plan.py, import_china_food.py, config/, data/ with canteen.db + weekly_plan CSV, cli/io_json.py, scripts/verify.sh + verify_ui.mjs, SPA templates/index.html + static/, ~2924 lines total) and flagged `README.md 疑为乱码/编码损坏`.
7. `hermes kanban unblock t_4376de5b` → `hermes kanban dispatch` → `● running` → completed in 3m. **Worker actually read the WPS cloud doc 「0综保部→食堂」**: 2025 满意度数据, 4 组打分群体共 2,695 票, 结论 食堂管理四季度全垫底 (平均 92.66) — hard proof that workers inherit the assignee profile's full skills/tools.
   - `hermes kanban runs t_4376de5b` showed two rows: `1 blocked ... → 需要人工确认……` then `2 completed ... 3m → 已基于 WPS 云文档……`.
8. `hermes kanban archive t_087cb65a t_38a62799 t_4376de5b` → `list` shows `(no matching tasks)`; `list --archived` shows all three with `—` marker; `stats` all zeros with status labels `triage/todo→"scheduled"/ready/running/blocked/done`.
9. `hermes kanban watch > /tmp/kanban-watch.log 2>&1` (backgrounded) captured live events, e.g. `[2026-08-09 17:16] t_38a62799 completed (@default) {'result_len': 464, ...}`. watch never exits → must be backgrounded and killed (process kill after demo).

## Notes

- Worker = full `hermes` process with the assignee profile (model deepseek-v4-flash in this run). `[run 3] claimed/spawned` events: run counter is global, not per-task.
- `tip_scratch_workspace` event fired on first scratch workspace creation: "scratch workspaces are ephemeral — they're deleted when the task completes. Use --workspace worktree: / dir:/abs/path to preserve worker output."
- The satisfaction-analysis result was valuable but lives only in board records (archived ≠ deleted) — offered to extract it into the CanteenMenu project as follow-up.
