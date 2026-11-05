# Synology / NAS deployment pitfalls (with fixes)

Ordered roughly by how early they bite.

## 1. Docker Hub unreachable from the NAS
`auth.docker.io` / `registry-1.docker.io` time out (common on Chinese consumer ISPs).
**Fix:** pull via a mirror path — `docker.m.daocloud.io/nousresearch/hermes-agent:latest` — and
optionally `docker tag` it back. Avoids editing `dockerd.json` (which restarts every container
on the host). `registry.cn-hangzhou.aliyuncs.com`, `quay.io`, `ghcr.io` are usually reachable when
Docker Hub is not; `hub-mirror.c.163.com` often is not.

## 2. CPU quotas unsupported on Synology
`docker compose up` fails with `NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler`.
**Fix:** never set `cpus:` / `deploy.resources.limits.cpus` in the compose file. `mem_limit` works fine.

## 3. Gateway multiplexer crashes on a secondary profile
Log: `Gateway multiplexer config error: Profile '<x>' enables <platform>: open policy without allow-all opt-in`
— the whole gateway exits.
**Fix:** in that profile either set the platform's allow-all flag or remove the platform block
(`hermes -p <profile> config unset platforms.<platform>`). `enabled: false` alone is not enough
for the open-policy check in every version — unset it.

## 4. Nous Portal OAuth cannot be shared between two installs
Copying `auth.json` to a second machine triggers:
`detected refresh-token reuse and revoked this session` — refresh tokens are single-use and rotated.
**Fix:** each install needs its own login, or use a provider with an independent API key
(DeepSeek etc.) on one side. Check the old host's `hermes auth list` to be sure you did not break it.

## 5. `.env` beats container environment variables
An empty/old `API_SERVER_KEY` in the data dir's `.env` silently overrides the `-e`/`env_file` value →
`Invalid gateway API key`.
**Fix:** keep one source of truth. Secrets belong in `.env`; when you set them via `env_file`, make the
values identical or remove the duplicate.

## 6. Dashboard login is a JSON API, not a form or HTTP Basic
`curl -u user:pass` never authenticates. The real endpoint is `POST /auth/password-login` with
`{"provider": "basic", "username": …, "password": …, "next": "/"}`; a form-encoded body returns 422.
Success sets `hermes_session_*` cookies and returns `{"ok": true, "next": "/"}`.
Verify with `GET /api/auth/me`.

## 7. macOS `scp` uses SFTP — Synology often has it disabled
`scp` dies with `Connection closed`.
**Fix:** `ssh host 'cat > /path/file' < local` (or `scp -O` for the legacy protocol).

## 8. macOS ships openrsync, which ignores `~/.ssh/config`
Backup scripts using `rsync nas:/path` fall back to password auth and fail non-interactively
(`Permission denied, please try again`).
**Fix:** use a `tar` pipe over ssh, or pass `-e "ssh -i <key> -o IdentitiesOnly=yes"` explicitly.

## 9. `timeout(1)` does not exist on macOS
Scripts calling `timeout 60 …` fail with `command not found`.
**Fix:** use the agent terminal's own timeout, `perl -e 'alarm …'`, or background the job.

## 10. `ssh -t` does not give sudo a TTY in a non-terminal panel
`sudo: a terminal is required to read the password` when commands run inside an agent's terminal pane.
**Fix:** do privileged setup in a real terminal app (Terminal.app), or route it through DSM's
Task Scheduler running as root.

## 11. Tailscale assigns accounts by email domain
Signing up with a company-domain or public-provider address (e.g. `@21cn.com`) drops the user into a
pre-existing org tailnet — often full and unpaid: "Your account is unpaid… reached the maximum number of users".
**Fix:** register with a recognised personal identity (Google / Apple / GitHub / Microsoft).
Also: if the browser still holds the old session, the app's sign-in link silently re-enters the wrong
tailnet — log out at `login.tailscale.com/logout` or use a private window.

## 12. macOS Tailscale: the GUI owns the connection, but the CLI can still log in
`tailscale up` is the unsupported verb on macOS. `login` works from the bundled binary:
`/Applications/Tailscale.app/Contents/MacOS/Tailscale login --hostname=<name>` prints an auth URL and
completes after the user authorises it in a browser — useful when the menu-bar sign-in keeps
reopening the wrong account. On Linux/DSM the CLI is unrestricted:
`tailscale --socket=<sock> up --authkey=tskey-…` (Synology package socket:
`/volume1/@appdata/Tailscale/tailscaled.sock`; `tailscale set --operator=<user>` removes the need for root).

## 13. WeChat (iLink) cannot push until the user speaks first
`[Weixin] send failed … session not ready … the user must send the bot a message first (or re-pair)`.
**Fix:** after pairing, have the user send the first message; treat it as part of acceptance testing.

## 14. WeChat pairing writes credentials to two places
`qr_login` → `weixin/accounts/<account_id>.json` (auto), but the adapter resolves
`WEIXIN_TOKEN` / `WEIXIN_ACCOUNT_ID` from `.env` first.
**Fix:** after pairing, rewrite both `WEIXIN_ACCOUNT_ID` and `WEIXIN_TOKEN` in `.env` (and
`WEIXIN_BASE_URL` if it changed), then restart the gateway. Pairing runs as root inside the
container, so `chown -R <uid>:<gid>` the `weixin/` tree afterwards.
The QR itself can be rendered to a PNG and shown in chat for the user to scan: monkeypatch
`_print_qr` in `gateway.platforms.weixin` to also `qrcode.make(url).save(path)`.

## 15. Over-broad tar excludes silently delete legitimate files
`--exclude='*/hermes-agent'` also removes the `hermes-agent` **skill** directory
(`skills/autonomous-ai-agents/hermes-agent/`).
**Fix:** after every migration, compare `find … -type f | wc -l` per top-level directory on both
sides and inspect the delta with `comm -23`. Expect the delta to be *only* intentional
exclusions (node_modules, `.locks`, `*.bak`).

## 16. A hand-written desktop connection has no session token
`connections.json` (v2) accepts `{id, kind:'remote', label, url}` and looks valid, but every remote
entry needs the token minted by the app's Sign-in flow. Connecting then fails with
`Remote Hermes gateway is selected, but no session token is saved`, and no login prompt appears.
`authMode` is only `token` | `oauth` — there is no `basic` value; a password-provider sign-in is what
produces the token. **Fix:** create/edit connections in **Settings → Registered gateways → Edit →
Sign in**; treat the JSON file as read-only diagnostics.

## 17. Two installs never sync — plan for one source of truth
Sessions live in each backend's `state.db` (WAL), skills in each backend's `skills/`, and
`hermes update` or a new Docker image only touch the install that runs it. After a migration the two
copies drift within hours (bundled-skill sync on every boot, new sessions, different builds), and
merging `state.db` files is unsafe. **Fix:** pick one live backend and make the other a client
(desktop Remote gateway) or a frozen rollback copy; sync `skills/`/`memories/`/`config.yaml`
one-way only if a second live instance is unavoidable.

## 18. Userspace-networking relay looks like an outage
Synology has no `/dev/net/tun`, so the package runs `--tun=userspace-networking` and traffic stays on
DERP (`tailscale ping` reports `via DERP(...)`, not `direct`). The first request after the path goes
cold can take ~10 s and trips client-side timeouts; warm requests are ~0.7–1.5 s. **Fix:** repeat the
request before diagnosing a failure, use `tailscale ping` to tell relay from direct, and enable UPnP
or forward UDP 41641 on the home router for a direct path.
