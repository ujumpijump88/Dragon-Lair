---
name: internal-tool-deploy
description: Harden Flask+SQLite LAN tools - RBAC, backup, zip updates.
---

Deploy a Python web tool for internal (non-public) use. The recurring shape: Flask + waitress + one SQLite file, served on the LAN, used by a handful of people. The naive version has zero auth and a `copy` of the live DB for backup — both are traps. This skill captures the verified hardening recipe.

## When to use
- Shipping a Flask/SQLite tool to a Windows server or any LAN-only host.
- The tool will be touched by more than one person (→ needs accounts, not a shared password).
- You need backup + update that won't corrupt or wipe on-site data.

## Decision tree (ask the user, don't assume)
1. **Exposure + auth**: bind `0.0.0.0` only if multiple people across the net need it; otherwise `127.0.0.1`. Either way, if >1 user → add multi-account RBAC, never a single shared password env.
2. **Shared DB topology**: one server runs waitress, everyone hits it in a browser. The SQLite file lives ONLY on that server's local disk. **Never** put the live `.db` on an SMB share (concurrent writes corrupt it). Backup *copies* on SMB are fine.
3. **Backup**: SQLite online hot backup (`BACKUP TO`), NOT `copy` of the live file. Rolling N-day retention.
4. **Update channel**: if the repo has no remote, ship a versioned zip (exclude `.venv`/`data`/`logs`/`.git`); `update.bat` preserves on-site `data/` and config. Keep the previous zip for rollback.
5. **Single point**: NSSM auto-start covers crash/reboot; record a human fallback owner + RTO for power/hardware failure.

## Gotchas (verified this session)
- **Gate auth to prod only.** If existing tests hit `/api/*` unauthenticated, make `_auth_enforced()` return False when `app.config["TESTING"]` is set or a `CANTEEN_NOAUTH=1` env is present or not `--prod`/`CANTEEN_PROD=1`. Otherwise a global `before_request` guard breaks every dev-mode test. (38 tests stayed green this way.)
- **`before_request` returns 401 for `/api/*` but `redirect("/login")` for pages** so the SPA degrades gracefully.
- **Password storage**: werkzeug `generate_password_hash` defaults to scrypt+salt — use it, never store plaintext. The stored string looks like `scrypt:32768:8:1$...`; assert on the `scrypt`/`pbkdf2` prefix, not a literal substring.
- **`importlib.util.spec_from_file_location` returns `ModuleSpec | None`** — guard with `assert spec is not None` before `module_from_spec` to satisfy the type checker (matches the pattern already in the snapshot routes).
- **Pricing PUT writes `config/pricing.json`** — tests must point `CANTEEN_PRICING_CONFIG` at a temp file or the real config gets mutated. Isolate it.
- **`schema_version` table + idempotent `ALTER` on startup** so a zip update that adds a column won't crash the old DB.

## Reference
See `references/flask_sqlite_rbac_recipe.md` for the concrete, copy-modify code: RBAC tables, `before_request` guard, three-role permission matrix, hot-backup `.bat`, and versioned-zip `update.bat`/packer.
