# Hermes Agent in Docker (official image)

Depth notes for hosting Hermes itself in a container on a NAS. Companion to `synology-docker-deployment`; the general Hermes CLI/config surface lives in the bundled `hermes-agent` skill.

## Data model

Official image `nousresearch/hermes-agent`. It is stateless; all user state lives in one mounted directory at `/opt/data` (`HERMES_HOME=/opt/data`). Mount the host data directory there and image upgrades never lose config, sessions, memory, or skills.

```yaml
volumes:
  - /volume1/docker/hermes:/opt/data
```

Set `HERMES_UID` / `HERMES_GID` to the owner of that host directory (get them with `id` over SSH) so files written by the container stay writable by the admin user.

## Ports and surfaces

| Surface | How to enable | Port |
|---|---|---|
| Gateway (messaging platforms) | default `command: gateway run` | outbound only — no inbound port needed |
| Web dashboard | `HERMES_DASHBOARD=1` | `0.0.0.0:9119` (override `HERMES_DASHBOARD_HOST/PORT`) |
| OpenAI-compatible API server | `API_SERVER_ENABLED=true` + `API_SERVER_HOST=0.0.0.0` + `API_SERVER_KEY` (>=8 chars) | `8642` |

Inside the official image the gateway is **supervised (s6-overlay)**: if it crashes it restarts in seconds and the container survives. The `gateway run` process itself is a heartbeat, so `docker stop` still shuts everything down cleanly.

Binding the dashboard to a non-loopback address **forces authentication** — configure basic auth (`HERMES_DASHBOARD_BASIC_AUTH_USERNAME` + `_PASSWORD`, optional `_SECRET` to persist login) or dashboard OAuth. `HERMES_DASHBOARD_INSECURE` is ignored. The desktop app connects to a remote gateway via **Settings -> Gateways -> Remote gateway -> Remote URL `http://<host>:9119`** using the same credentials, configurable per profile and overridable with `HERMES_DESKTOP_REMOTE_URL`. Reach it over a VPN (Tailscale) rather than port-forwarding — the dashboard is an admin surface.

Messaging adapters that matter for a NAT'd NAS:
- **QQ official bot**: persistent WebSocket outbound to the QQ gateway; no public webhook, no inbound port, no IP allow-list in Hermes.
- **WeChat iLink**: long-poll `getupdates` — no public endpoint required. Pairing prints a QR code in the terminal for the phone to scan (no GUI needed server-side); credentials land in `$HERMES_HOME/weixin/accounts/<account_id>.json` and can be copied instead of re-pairing. Practical limit: it is a bot identity, so group events are unreliable — DMs are the trustworthy channel.

## Migration from a workstation install

Copy into the mounted data directory:
`config.yaml`, `.env`, `auth.json`, `state.db`, `sessions/`, `skills/`, `memories/`, `cron/`, `profiles/`, platform credential files (e.g. `weixin/`).

Exclude:
- the installed source tree — **anchor the path** (`./hermes-agent`), never a bare name or a `*/hermes-agent` glob: `skills/<category>/hermes-agent/` is a legitimate skill directory of the same name and the glob drops it from the copy. (The image ships its own source, so a mounted tree would conflict anyway.)
- `node/`, `bin/`, `lsp/` (host tooling and caches), `logs/`, `backups/`, `*.bak` (multi-GB, regenerable)
- the live `state.db` plus its `-wal`/`-shm` siblings — these come over as a consistent snapshot instead (below)

**Verify the copy rather than trusting the transfer's exit code.** Exclude globs fail open and silently. Count files per top-level directory on both sides, then diff the sorted full file lists and group the misses:

```bash
find <src>/skills -type f | sed 's|.*/<src>/||' | sort > /tmp/src.txt
ssh nas "cd <dest>/skills && find . -type f | sed 's|^\./||' | sort" > /tmp/dst.txt
comm -23 /tmp/src.txt /tmp/dst.txt | awk -F/ '{print $1}' | sort | uniq -c
```

**Snapshot live databases from a still-running source install** with Python's built-in SQLite backup API — a consistent image without stopping the writer, and the only safe way when no app-level backup command is reachable:

```python
import sqlite3
s = sqlite3.connect(f'file:{src}?mode=ro', uri=True); d = sqlite3.connect(dst)
s.backup(d); d.close(); s.close()
```

Transfer each snapshot into the data directory under its original name, and let the exclude list keep the originals out.

Fix-ups that otherwise fail silently after the move:

1. **Timezone** — an empty `timezone` in config plus a UTC container shifts every schedule and timestamp. Set `TZ=Asia/Shanghai` (or the user's zone) in the container *and* write it explicitly in config; the container variable alone does not fix recorded timestamps.
2. **Host-specific cron jobs** — audit `hermes cron list` before migrating. Scripts that call OS-specific binaries (macOS `caffeinate` being the common one for "keep the machine awake" guards) cannot work on the NAS, and the NAS does not need them. Drop them instead of carrying a job that fails every run and floods the error log.
3. **Profiles sharing gateway credentials** — a bot token can only belong to one profile. If two profiles reference the same platform credentials, decide which profile owns them and strip them from the other, or gateway multiplexing refuses to migrate.
4. **Model/provider reachability** — test the configured provider from the NAS *and* wire a fallback (`hermes fallback add`) so a provider outage degrades instead of silently dropping replies. This is the difference between a degraded bot and a dead one.

## Start order

The container must not come up against a half-populated data directory: land the config, credentials, skills, memory, and the DB snapshots first, then pull, then start. Verify inside the container (`hermes doctor`, `hermes cron list`, an actual memory lookup) before touching the old host — a gateway that starts with missing state looks healthy and answers wrongly.

## Storage and concurrency invariants

- `state.db` is SQLite in **WAL** mode. Local volume bind mount only — NFS/SMB/FUSE mounts corrupt it (if such a mount is unavoidable, set `database.journal_mode: delete`).
- **Never run two gateways against the same data directory.** Stop the old host's gateway before starting the container, and keep it stopped.
- Back up by stopping the container or using the app's own backup command (`hermes backup`) — never by copying a live `state.db`.
- Unattended gateway sessions enable tool-loop hard stops by default (`tool_loop_guardrails.non_interactive_hard_stop_enabled`). Leave them on for a 24/7 deployment.

## Cutover mechanics: boot the container platform-inert

Copying the data directory is not enough to keep the old host alive. The new gateway reads the same bot credentials and connects, and a bot service keeps only one live session — so the running host gets dropped the moment the container starts. Disable every platform **on the copy, before the first `gateway run`**, using a one-off container that runs the CLI without starting a gateway:

```bash
docker run --rm -e HERMES_UID=<uid> -e HERMES_GID=<gid> -v /volume1/docker/hermes:/opt/data <image> \
  hermes config set platforms.qqbot.enabled false
```

Omitting `HERMES_UID`/`HERMES_GID` makes the one-off run rewrite the data directory as root, after which the real container cannot write it.

One container multiplexes **every profile's** gateway, so audit all of them, not just the default. A single per-profile platform block that fails validation aborts the whole multiplexer at startup — `Gateway multiplexer config error: Profile '<x>' enables <platform>: open policy without allow-all opt-in` followed by `Gateway exiting cleanly` — which presents as "the gateway never comes up" while the dashboard keeps serving normally. Either make each profile's policy valid (allow-all opt-in present, e.g. `QQ_ALLOW_ALL_USERS=true`) or remove that profile's platform block entirely. A profile that no longer owns a channel should be stripped of both its platform config and its copy of the credentials.

At switch time, enable a platform on the new host and disable it on the old one in the same change — never both live, not even briefly.

## Credentials that must not be shared between installs

`auth.json` is per-install, not per-account. OAuth refresh tokens are **single-use**: copy the file to a second machine and both refresh, the provider sees reuse and revokes the session — `refresh-token reuse and revoked this session` / `invalid_grant` — and the affected install silently degrades to its fallback chain mid-conversation.

- Never run two installs off one copied `auth.json`. Give the container its own login, or keep API-key providers (DeepSeek/Kimi/OpenRouter keys in `.env`) as the container's primary and leave OAuth to the workstation.
- The fix after revocation is a fresh login on one machine, not re-copying the file.
- Before switching a container's provider, check what the *workstation* actually runs on (`hermes auth list`): an install living on API keys is unaffected by an OAuth revocation, which is what makes the split-credential arrangement the safe one.

## Config precedence, and how to edit it

- Never hand-edit `config.yaml`; use the CLI (one-off container recipe above when the gateway must not be disturbed).
- **A key in the data directory's `.env` overrides the same key passed as a container environment variable.** Duplicating `API_SERVER_KEY` in both the compose `env_file` and `.env` makes the server validate against the `.env` value while you test with the compose one; every call fails `Invalid gateway API key` with no hint as to which copy won. Define each secret in exactly one place — keep `.env` as the single source and pass only non-secret knobs (TZ, HERMES_UID/GID, HERMES_DASHBOARD) as container environment.
- Full migration is the moment to normalise this: diff the copied `.env` for keys that now also exist in the environment, and unify before diagnosing anything else.

## Auth mechanisms as actually implemented

Two different mechanisms. Testing one against the other reads as "the credentials are broken":

| Surface | Mechanism | Probe |
|---|---|---|
| Gateway API server (8642; keep it bound to `127.0.0.1` inside the container and unpublised) | `Authorization: Bearer $API_SERVER_KEY` | `curl -sS http://127.0.0.1:8642/health` |
| Web dashboard (9119) | JSON login POST, then session cookies | below |

The dashboard has **no HTTP Basic**: `curl -u user:pass http://host:9119/` answers `302 -> /login` whether or not the credentials are correct, which looks exactly like a rejected password. The real flow is a JSON POST to `/auth/password-login` with body `{"provider":"basic","username":...,"password":...,"next":"/"}` — `provider` is the registered auth plugin name (`basic`), answered with `{"ok":true,...}` plus `hermes_session_*` cookies. A form-encoded post gets `422`; the wrong path (`/password-login`, no `/auth` prefix) is swallowed by the auth middleware and redirects back to `/login`. Confirm identity afterwards with `/api/auth/me`, and locate the truth in an unfamiliar build with `grep -rn 'password-login' /opt/hermes --include='*.py'`.

End-to-end proof of a working deployment is a real completion, not a process listing. `prompt_tokens` in the response also confirms the full system prompt, skills and memory loaded:

```bash
docker exec hermes curl -sS -H "Authorization: Bearer $API_SERVER_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"hermes","messages":[{"role":"user","content":"reply OK"}]}' \
  http://127.0.0.1:8642/v1/chat/completions
```

`scripts/verify-hermes-container.sh` runs this whole battery.

## Reading output from the s6 image

Startup and `docker exec` output is dominated by s6 supervision lines (`s6-rc:`, `cont-init:`, `preinit:`, `[stage2]`) and the bundled-skills sync banner, which bury the actual result — `| tail -3` on an unfiltered stream returns three lines of s6 noise and no answer:

```bash
docker exec hermes hermes status 2>&1 | grep -viE 's6-rc:|cont-init|preinit|\[stage2\]|Syncing bundled|^  ~|^Done:'
```
