---
name: hermes-synology-nas
description: "Use when deploying Hermes on a Synology NAS (DSM7/Docker)."
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [synology, dsm, nas, docker, deployment, tailscale]
---

# Hermes on a Synology NAS

Verified on DS218+ / DSM 7.4 / Container Manager / Docker 24.0.2 (2026-10).

## Layout of the running instance

- SSH alias `nas` (192.168.50.106), user in `administrators`; key `~/.ssh/id_ed25519_hermes_nas`
- Container `hermes`; compose at `/volume1/docker/hermes/docker-compose.yaml`; data `/volume1/docker/hermes` → `/opt/data`
- Secrets: compose `env_file: /volume1/docker/hermes/hermes-container.env` **and** `/opt/data/.env` — `.env` wins for values like `API_SERVER_KEY`, so keep exactly one source
- Scoped sudo: `/etc/sudoers.d/hermes-deploy` with NOPASSWD for docker, docker-compose, synopkg, tailscale
- Dashboard `http://<nas>:9119`; the container runs `gateway run` under s6, dashboard supervised alongside

## Pitfalls (each one cost real debugging time)

1. **No CPU quota on DSM kernels** — `cpus:` in compose makes container creation fail with `NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler`. `mem_limit` works fine; drop `cpus`.
2. **Docker Hub is unreachable from CN networks** — pull a mirror path instead: `docker.m.daocloud.io/nousresearch/hermes-agent:latest` (dockerproxy.net 404s; daocloud works). Pre-verify a tag with the anonymous token flow (`https://m.daocloud.io/auth/token?...&scope=repository:<repo>:pull`). Editing `dockerd.json` also works but restarts every existing container.
3. **No SFTP subsystem on DSM** — `scp` fails with `Connection closed`. Push files with `ssh nas 'cat > /path/file' < localfile`.
4. **macOS `rsync` is openrsync** — it ignores `~/.ssh/config`, so rsync-over-ssh degrades to password auth and dies (`Permission denied, please try again` / `unexpected end of file`). Use `tar -cf - . | ssh nas 'tar -xf - -C dest'` (~12 MB/s on GbE) and swap directories for a clean mirror.
5. **sudo always needs a password** — ask the user for a one-time `sudo -i` in a real terminal (the Hermes terminal pane has no TTY; `ssh -t` may also fail). DSM has **no `visudo`**, so validate afterwards by running one of the granted commands with `sudo -n`. Never fall back to Hermes `SUDO_PASSWORD`: the `.env` is itself being migrated to the NAS.
6. **Trimmed busybox userland**: no `nc`, `getent`, `timeout`, `visudo`; `python3` is present; `synopkg` lives at `/usr/syno/bin/synopkg`.
7. **One gateway multiplexes every profile in the container** — any profile with an invalid platform block takes the whole multiplexer down (`Gateway exiting cleanly: Profile 'X' enables qqbot: open policy without allow-all opt-in`). Fix it or remove the block (`hermes -p X config unset platforms.qqbot`).
8. **Never start the gateway while another machine still serves the same bot credentials** — first disable platforms in the copied data dir: `hermes config set platforms.qqbot.enabled false` (same for weixin). Otherwise two installs fight over one bot session.
9. **Do config edits with a throwaway container** (no hand-editing config.yaml, no running gateway):
   `sudo docker run --rm -e HERMES_UID=<uid> -e HERMES_GID=<gid> -v /volume1/docker/hermes:/opt/data IMAGE hermes config set KEY VAL`
   s6 boot noise floods stdout — filter with `grep -viE "s6-rc|cont-init|preinit|\[stage2\]"`.
10. **SQLite is WAL** — never `cp` a live DB; use the sqlite3 backup API from inside the container, and only ever bind-mount a local volume (NFS/SMB corrupts it).
11. **Nous Portal OAuth refresh tokens are single-use** — copying `auth.json` to a second install revokes the session for both (`refresh-token reuse ... revoked this session`). Give each install its own login, or point the NAS at an API-key provider (DeepSeek) instead.
12. **Tailscale on Synology** — install the dsm7 SPK (`synopkg install <spk>`; the package-server route can fail with `Failed to query package list from server`). It runs `--tun=userspace-networking`; `tailscale up` needs root, so either grant the binary in sudoers or run `tailscale set --operator=$USER` once as root. Tailscale derives the tailnet from the **email domain**: a public domain such as `@21cn.com` silently joins a stranger's org tailnet ("account is unpaid / maximum users"). Use a Google/Apple/GitHub identity, or `tailscale logout` and re-`up` with one.

## Deployment order that works

1. Read-only recon: arch, DSM version, RAM, disk, Container Manager state, outbound connectivity.
2. SSH key auth (`ssh-copy-id nas`, password typed by the user).
3. Compose + `env_file` written into the data dir; dashboard basic-auth creds generated (`HERMES_DASHBOARD_BASIC_AUTH_USERNAME/_PASSWORD`).
4. Bulk copy of the source `~/.hermes` (exclude source tree, node/lsp/bin, backups, logs, `*.bak`; snapshot live DBs with the backup API and copy the snapshots). **Verify file counts on both sides** — an over-broad exclude (`*/hermes-agent`) silently eats a legitimate skill directory.
5. Throwaway-container config fixes: disable platforms, set `timezone: Asia/Shanghai` (the container defaults to UTC), reconcile conflicting keys in `.env`.
6. `docker compose up -d`, then verify in this order: container up → `gateway run` process alive → `/health` on the gateway API → one **real model call** → dashboard login → memory headroom (`docker stats` + `free -m`).

## Dashboard auth contract (not HTTP Basic)

The login page posts JSON: `POST /auth/password-login {"provider":"basic","username":...,"password":...,"next":"/"}` → 200 + `hermes_session_*` cookies. `curl -u` and form-encoded bodies both fail (302 back to `/login`); verify with the JSON call plus `/api/auth/me`.
