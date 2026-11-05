# Troubleshooting

### Voice not working
1. Check `stt.enabled: true` in config.yaml
2. Verify provider: `pip install faster-whisper` or set API key
3. In gateway: `/restart`. In CLI: exit and relaunch.

### Tool not available
1. `hermes tools` — check if toolset is enabled for your platform
2. Some tools need env vars (check `.env`)
3. `/reset` after enabling tools

### Model/provider issues
1. `hermes doctor` — check config and dependencies
2. `hermes auth` — re-authenticate OAuth providers (or `hermes auth add <provider>`)
3. Check `.env` has the right API key
4. **Copilot 403**: `gh auth login` tokens do NOT work for Copilot API. You must use the Copilot-specific OAuth device code flow via `hermes model` → GitHub Copilot.

### Nous Portal: "not connected" / "model switch failed" / revoked OAuth
Symptoms: `Nous Portal is not connected: no API key or login was found for it`, model switches to nous-hosted models fail, gateway log repeats `Primary auth failed (No access token found for Nous Portal login.), falling back to ...`.
1. Diagnose before re-authing: `hermes auth status nous`, then inspect `~/.hermes/auth.json` — `providers.nous.last_auth_error` (code, reason, when), `credential_pool.nous` (empty = nothing usable), `active_provider`. Also grep `~/.hermes/config.yaml` for `nous` (`model.provider`, `model.default`, `image_gen.provider`, `fallback_providers`) to see what still routes there.
2. `invalid_grant` / "refresh-token reuse" in `last_auth_error` = Portal revoked the session deliberately; the ONLY fix is re-login — do not hand-edit tokens into auth.json.
3. Re-login without a display: run `hermes auth add nous --no-browser` in a background PTY with output redirected to a log file, read the `user_code` + verification URL from the log, `open` the URL for the user, then poll the log for `Saved nous OAuth device-code credentials`. Present the code to the user immediately — device codes expire in minutes, so batch: start login → read code → open browser → tell user, in one turn.
4. The CLI's device-code poll loop aborts on transient network errors (`httpx.ConnectTimeout`/`ReadTimeout` on portal or inference API) instead of retrying — before starting, probe the endpoint a few times; if flaky, wait for it to stabilize and re-run the whole command (a crashed login needs a fresh device code).
5. Verify after login: `hermes auth status nous` → `logged in`, then a real call (`hermes chat -q ...`).
6. Stale default-model trap: a previously saved `model.default` may have been removed from the Portal catalog — the chat "works" only via fallback (`HTTP 404: Model ... not found`, then fallback to the next provider). List live models (`GET https://inference-api.nousresearch.com/v1/models` with the nous access token from auth.json) and fix with `hermes config set model.default <valid-id>`; never hand-edit config.yaml.

### Changes not taking effect
- **Tools/skills:** `/reset` starts a new session with updated toolset
- **Config changes:** In gateway: `/restart`. In CLI: exit and relaunch.
- **Code changes:** Restart the CLI or gateway process

### Skills not showing
1. `hermes skills list` — verify installed
2. `hermes skills config` — check platform enablement
3. Load explicitly: `hermes -s name` (or the skill's own `/<name>` slash command)

### Gateway issues
Check logs first:
```bash
grep -i "failed to send\|error" ~/.hermes/logs/gateway.log | tail -20
```

Common gateway problems:
- **Gateway dies on SSH logout**: Enable linger: `sudo loginctl enable-linger $USER`
- **Gateway dies on WSL2 close**: WSL2 requires `systemd=true` in `/etc/wsl.conf` for systemd services to work. Without it, gateway falls back to `nohup` (dies when session closes).
- **Gateway crash loop**: Reset the failed state: `systemctl --user reset-failed hermes-gateway`

### Platform-specific issues
- **Discord bot silent**: Must enable **Message Content Intent** in Bot → Privileged Gateway Intents.
- **Slack bot only works in DMs**: Must subscribe to `message.channels` event. Without it, the bot ignores public channels.
- **Windows-specific issues** (`Alt+Enter` newline, WinError 10106, UTF-8 BOM config, line endings): see `references/windows-quirks.md`.

### Auxiliary models not working
If `auxiliary` tasks (vision, compression, session_search) fail silently, the `auto` provider can't find a backend. Either set `OPENROUTER_API_KEY` or `GOOGLE_API_KEY`, or explicitly configure each auxiliary task's provider:
```bash
hermes config set auxiliary.vision.provider <your_provider>
hermes config set auxiliary.vision.model <model_name>
```

### `hermes update` issues
- **A command timeout is not a verdict either way** — check whether the updater is still alive before acting: `pgrep -fl "node-deps|electron/install|hermes update"` plus the log tail. Some stages hand off to a detached child that keeps running after the terminal call returns; others (notably `deps`) die with the foreground process and leave the run half-applied. Then read the receipt:
  `python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.hermes/logs/update_receipts/latest.json')));print(d['outcome'],d.get('stop_class'),d['pre_update']['short_sha'],'->',d['post_update']['short_sha'])"`
  Stages run plan → snapshot → apply → deps → build → restart. Never re-run blind while a child may still hold the venv.
- **`outcome: failed, stop_class: fetch_failed`**: the repo was unreachable — usually the host's proxy (Clash, 127.0.0.1:7897) is down. Start the proxy, then `git fetch origin main` in the source checkout; re-run only if `git rev-list --count HEAD..origin/main` > 0. `pre == post` means the failed attempt changed nothing (no damage to repair).
- **Probe per host before concluding "GitHub is blocked" or "no proxy needed"**: reachability is
  per-hostname, not per-service, and a user who can browse the project's website has proved nothing
  about git. Test the endpoint the updater actually uses: `nc -z -G 6 -w 6 github.com 443` (plus
  `:22` if an SSH path is on the table), then `curl -o /dev/null -w '%{http_code}' https://api.github.com/`.
  `api.github.com` / `codeload.github.com` / `raw.githubusercontent.com` answering while
  `github.com:443` refuses every edge IP is a normal combination — that fetch still needs the proxy
  even though every "is GitHub up?" check passes.
- **Answering "is there anything new?" with no proxy at all**:
  `https://api.github.com/repos/<owner>/<repo>/commits?sha=main&per_page=100&page=N`, walking pages
  until the local short sha appears (the `/compare/` endpoint returns a several-hundred-KB body that
  truncates mid-JSON across a large gap and will not parse). Treat any earlier `Already up to date` as
  a timestamped observation, not standing truth — check again with the API before telling the user
  there is nothing to update.
- **Never wire a third-party git mirror into `origin` on the strength of `ls-remote` alone**: a mirror
  can advertise a ref that byte-matches the official tip and still corrupt pack transfer
  (`bad band #69`, `early EOF`), and a protocol-v0 fallback that "succeeds" can hand back an EMPTY
  repository — which the updater's reset would apply straight over the working tree. Prove any
  candidate with a throwaway `git clone --depth=1 --no-checkout <mirror> /tmp/mirror-probe`, plus one
  more clone of a tiny public repo to separate a size problem from a broken pack path; a stale-but-honest
  mirror is equally useless because it cannot deliver the tip. Keep verified-broken mirrors out of the
  config entirely.
- **Leftover `hermes-update-autostash-*` entries** in `git stash list`: the updater autostashes local changes before pulling. Entries it flags as >7 days old are abandoned edits — inspect `git stash show -p stash@{N}`, then `git stash apply` (restore) or `git stash drop` (discard).
- `hermes --version` prints `upstream <sha>`; trust a fresh `git fetch` + `git rev-list --count HEAD..origin/main` over the version label when asked "am I on the latest?".
- **Never run it interactively from an agent session.** `hermes update` prompts (pre-update backup,
  config migration, stash restore, fork-upstream) and waits forever on a non-tty stdin — pass `-y`,
  and `--no-backup` only when the user has said snapshots are unnecessary. Probe first with
  `hermes update --check` (read-only: says `Already up to date` or flags an owed interrupted run).
- **Run it backgrounded with a log, never foreground.** A foreground terminal call hits its own
  timeout mid-`deps` and the process dies half-applied. Start it with stdout+stderr to
  `/tmp/hermes-update.log`, then poll that log for stage progress; the final `EXIT=` line is the
  verdict. Hand-edit nothing to repair a killed run.
- **"The previous update was interrupted before it finished (last stage: deps); this update
  completes the work it still owed"** is informational, not an error: re-run and it resumes. If
  Python code is already at the remote tip, the remaining work is deps/build/restart only, so a run
  ending `Already up to date! [main @ <sha>]` plus `EXIT=0` is a success, not a no-op to redo.
- **`deps` stage crawling in China**: the packaging step downloads the Electron release matching the
  desktop app (~120 MB) from GitHub release assets, and Node honours neither `git config http.proxy`
  nor the macOS system proxy. Export mirrors on the update command:
  `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ npm_config_registry=https://registry.npmmirror.com hermes update -y`
  — the tell for a stalled download is a partial `$TMPDIR/electron-download-*/electron-v*-*.zip`
  whose size stops moving while the process sits at ~0% CPU. git fetch itself is fast once the repo-level
  proxy is set, so a stall at `Preparing Node dependencies…` is almost always this download.
- **`/Applications/Hermes.app is running and was not refreshed`**: the run updated code and deps but
  skipped the app bundle. Verify with
  `ls -l /Applications/Hermes.app/Contents/Resources/app.asar` against
  `ls -lt ~/.hermes/hermes-agent/apps/desktop/dist` — a months-old `app.asar` next to fresh `dist`
  files means only the bundle is stale. Refreshing it requires quitting the app, which ends the
  current desktop session: confirm with the user first, then drive quit → update → relaunch from a
  **detached** process (`scripts/refresh-desktop-app.sh`). `launchctl submit`/`bootstrap` is refused
  inside a supervised gateway by design (restart-loop guard) — do not look for another launchctl verb;
  double-fork + `os.setsid()` and `execv` a bash script instead, which puts the job in its own
  session and out of the gateway's process group.

### "Reset permissions" / auto-approving everything
See `references/security-privacy.md` — wipe the "Always allow" stores, don't touch yolo mode.

