---
name: hermes-nas-deployment
description: "Use when deploying Hermes to a NAS/Docker host."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [deployment, docker, synology, nas, migration, tailscale, gateway]
---

# Deploying Hermes to a NAS (Docker)

Moving a working Hermes install from a laptop to an always-on NAS so messaging gateways
(QQ / WeChat / Telegram / …) run 24/7. Battle-tested on Synology DS218+ (DSM 7.4, x86_64).

## When to use

- User wants Hermes running 24/7 on a NAS/mini-server instead of their laptop
- Migrating existing config/skills/memory to a containerised Hermes
- Troubleshooting an already-deployed Synology Hermes container

**Read `references/synology-pitfalls.md` before starting** — concrete traps with fixes.
**Building the desktop app as a client** — see `references/desktop-remote.md` (registry, sign-in, diagnosis).

## Phase 0 — Recon (facts first, always)

Never plan from assumptions. Collect:

```bash
# NAS side
ssh <user>@<nas> 'uname -m; cat /etc/VERSION; grep MemTotal /proc/meminfo; nproc'
ssh <user>@<nas> 'df -h /volume1; id; ls /var/packages/; ls /usr/local/bin/'
ssh <user>@<nas> 'sudo -n true && echo SUDO_NOPASS || echo SUDO_NEEDS_PASS'
# outbound reachability — the #1 blocker
ssh <user>@<nas> 'for u in https://hermes-agent.nousresearch.com/ https://api.deepseek.com/ \
  https://auth.docker.io/token https://docker.m.daocloud.io/v2/ https://q.qq.com/; do \
  printf "%-45s " $u; curl -sS -m 8 -o /dev/null -w "%{http_code}\n" $u; done'
```

Decide from the facts: memory ceiling, registry reachability, outbound reachability.

## Phase 1 — Access & privileges

1. Enable SSH in DSM (控制面板 → 终端机和 SNMP).
2. Generate a dedicated key and install it **by the user** (`ssh-copy-id`) — never handle their password.
3. Add `~/.ssh/config` hosts: LAN alias **and** a Tailscale alias (short timeouts + `ServerAliveInterval`).
4. Synology: `docker.sock` is `root:root 660`, no `docker` group — a one-time **scoped** NOPASSWD grant is needed:

```bash
printf 'USER ALL=(ALL) NOPASSWD: /usr/local/bin/docker, /var/packages/ContainerManager/target/usr/bin/docker, /usr/syno/bin/synopkg\n' > /etc/sudoers.d/hermes-deploy
```

After that, always call `sudo -n /usr/local/bin/docker ...` (sudo matches the realpath).
Never ask the user to put a NAS password in `SUDO_PASSWORD` — that secret would then be migrated onto the NAS itself.

## Phase 2 — Container + data

```bash
mkdir -p /volume1/docker/hermes   # host data dir -> /opt/data
```

- Image: `nousresearch/hermes-agent:latest`; if Docker Hub is blocked, pull via a mirror path
  (`docker.m.daocloud.io/nousresearch/hermes-agent:latest`) — no dockerd config change, no restart of other containers.
- compose: `command: gateway run`, `env_file`, bind mount, `mem_limit`, `shm_size`, json-file log rotation.
  **No `cpus:`** — Synology's kernel rejects CPU quotas.
- DS218+ has one free SO-DIMM slot: a single 8 GB DDR3L-1600 (1.35 V, non-ECC, 204-pin) yields 10 GB
  (the official spec stops at 6 GB). After fitting it, raise `mem_limit` in the compose file (e.g. 4g)
  and recreate — the container returns on boot via `restart: unless-stopped`, but the old limit stays
  in the file.
- Env to set: `TZ=Asia/Shanghai`, `HERMES_UID`/`HERMES_GID` = the SSH user's uid/gid,
  `HERMES_DASHBOARD=1`, `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/_PASSWORD`,
  `API_SERVER_ENABLED=true` + `API_SERVER_HOST=127.0.0.1` + `API_SERVER_KEY`.
- Back up live SQLite with the **online backup API**, never `cp`:

```python
s = sqlite3.connect(f'file:{src}?mode=ro', uri=True)
d = sqlite3.connect(dst); s.backup(d)
```

## Phase 3 — Migration (tar pipe, not rsync/scp)

```bash
cd "$HOME/.hermes" && COPYFILE_DISABLE=1 tar -cf - \
  --exclude='./hermes-agent' --exclude='./node' --exclude='./bin' --exclude='./lsp' \
  --exclude='./logs' --exclude='./backups' --exclude='*.bak' . \
  | ssh <alias> 'tar -C /volume1/docker/hermes -xf -'
```

- Exclude the source tree (the image ships its own) and all binaries/caches.
- **Verify by file count** per directory (`find … -type f | wc -l`) on both ends —
  over-broad excludes like `*/hermes-agent` silently eat legitimate skill dirs.
- Copy DB snapshots separately (they were excluded by design).
- Strip macOS-only cron jobs (`caffeinate` etc.) afterwards.
- **Profile credential dedup**: if two profiles share bot credentials, the gateway multiplexer
  refuses to start (open policy without allow-all). Remove the platform config from the
  secondary profile; keep one profile owning the bot.

## Phase 4 — Cutover (one platform at a time)

Ordering that avoids duplicate connections and minimises downtime:

1. Stage the new side (config edits) but **leave the platform disabled**.
2. Disable the platform on the old side, restart its gateway (drops in seconds).
3. Enable on the new side, restart its gateway.
4. Verify from logs, then send a real message end-to-end.

```bash
# enable + restart on the NAS container
sudo -n docker exec hermes hermes config set platforms.qqbot.enabled true
sudo -n docker exec hermes hermes gateway restart
sudo -n docker exec hermes ps -eo cmd | grep 'hermes gateway'   # confirm it is alive
```

Platform credential files often live in **two** places (account JSON + `.env`); the adapter
reads `.env` first. Sync both.

## Phase 5 — Remote access (Tailscale)

- Sign up with a **personal** identity (Google/Apple/GitHub). Email domains that belong to an
  organisation (or public non-personal providers) drop you into someone else's tailnet.
- Synology: install the official SPK from `pkgs.tailscale.com` (`…-dsm7.spk`) with `synopkg install`.
- Headless/WSL-style auth: generate an **auth key** in the admin console and pass `--authkey`
  (no approval URL needed).
- macOS: the menu-bar app is the normal login path, but the bundled CLI also logs in —
  `/Applications/Tailscale.app/Contents/MacOS/Tailscale login --hostname=<name>` prints an auth URL
  and completes once the user authorises it in a browser (`up` is the unsupported verb).
- Synology runs `tailscaled` in userspace-networking mode (`--tun=userspace-networking`; DSM has no
  `/dev/net/tun`), so traffic is relayed via DERP unless a direct path is punched. Expect 200–600 ms,
  and a ~10 s first request after the path goes cold — repeat before declaring a timeout.

## Phase 6 — Backups

- Nightly full mirror **pulled by the client** (tar pipe; openrsync on macOS ignores `~/.ssh/config`).
- Weekly compressed archive, keep the last 4.
- Run the in-container SQLite online-backup script **before** the file mirror so the mirror carries fresh DBs.
- Wrap in a launchd agent (`StartCalendarInterval`) and test it manually once.

## Phase 7 — Freeze the old host (rollback)

```bash
hermes gateway stop
mv ~/Library/LaunchAgents/ai.hermes.gateway.plist ~/Library/LaunchAgents/ai.hermes.gateway.plist.disabled
```

Keep the old data directory untouched — it is the rollback path. Record the exact steps to
re-enable it in the handover doc.

## Phase 8 — Desktop app as a remote client

Point the desktop app at the NAS instead of running a second copy:
**Settings → Registered gateways → (entry) → Edit → Sign in**, with `http://<lan-ip>:9119` at home
and `http://<tailnet-ip>:9119` away. Keep both connections and switch by location — the LAN path is
far faster than the relay.

- Remote entries carry `authMode: token|oauth`; the token is minted by the app's Sign-in flow and
  stored encrypted. **Never hand-write a connection into `connections.json`** — a URL-only entry
  yields `Remote Hermes gateway is selected, but no session token is saved`.
- The remote host is configured **per profile**, so each profile can point at its own backend.
- Two installs are **independent instances**: sessions live in each backend's `state.db`, skills in
  each backend's `skills/`. Nothing syncs — make the remote the only copy you edit.

Registry schema and diagnosis: `references/desktop-remote.md`.

## Verification checklist

- [ ] `docker ps` shows the container up, port published
- [ ] `hermes gateway status` healthy; both platforms `connected` in the gateway log
- [ ] Real inbound message from each platform gets a real reply
- [ ] Dashboard reachable on LAN **and** over the tunnel (expect `302` to `/login`)
- [ ] Skill/session/memory file counts match the source host exactly
- [ ] Timezone and model are what you intended (`hermes status`)
- [ ] Nightly backup runs and produces a fresh, consistent DB dump
- [ ] Old host has no platform enabled (no duplicate connections)
- [ ] Desktop app connects to the remote backend via Sign in (not a hand-written token) and lists
      that backend's sessions

## Deliverables

Write a handover doc covering: architecture, paths/ports, day-2 commands, platform toggles,
backup/restore, rollback, troubleshooting table, and the pitfalls encountered.
