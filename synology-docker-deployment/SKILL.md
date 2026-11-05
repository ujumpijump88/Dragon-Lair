---
name: synology-docker-deployment
description: "Deploy and host Docker services on a Synology NAS."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [synology, dsm, docker, container-manager, nas, deploy, ssh, registry-mirror]
---

# Synology NAS Docker Deployment

Hosting a long-running containerized service (agent, bot, web app) on a Synology DiskStation through Container Manager. Covers the DSM-specific friction that generic Docker guidance misses: user/group model, sudo, registry reachability, filesystem-dependent backups, and memory classes.

## When to Use

- The user wants to run a service 24/7 on a Synology NAS / Container Manager instead of on a workstation.
- A workload is moving off a laptop or desktop onto always-on NAS hardware.
- Any Docker work on DSM stalls on SSH access, sudo, image pulls, or "will it fit in this RAM".

Not for: plain Docker on a generic Linux server (the DSM quirks below do not apply).

Support files:
- `scripts/nas-recon.sh` — read-only reconnaissance probe; run this FIRST, before planning anything.
- `scripts/verify-hermes-container.sh` — post-start acceptance battery (container, gateway API, dashboard login, memory).
- `references/hermes-in-docker.md` — running/migrating Hermes Agent itself in the official image; cutover mechanics, credential-sharing traps, auth mechanisms as actually implemented.
- `templates/hermes-compose.yaml` — compose file scaffold for a Hermes gateway + dashboard.

## Rule 0 — Recon before you plan, and never guess hardware

Run `scripts/nas-recon.sh <host> [user]` (or paste its body over SSH) before writing any plan. It is read-only: identity, arch, DSM version, model, RAM/swap, volume free space and **filesystem type**, docker binary/socket, sudo state, installed packages, timezone, and per-endpoint outbound reachability with status codes.

Planning a memory limit, a backup strategy, or an image pull path without those facts produces a plan that has to be rewritten. `free -m` and `/proc/mounts` are the two lines that most often change the design.

## Rule 1 — Access: expect three separate gates, solve them in order

**Gate 1 — SSH is off, or the account is not allowed.** DSM → 控制面板 → 终端机和 SNMP → enable SSH. Then: **Synology denies SSH to accounts outside the `administrators` group even when the password is correct** — the symptom is a bare `Permission denied (publickey,password)` with no differentiation, which looks exactly like a wrong password. Confirm the group membership the moment you get in:

```bash
ssh nas 'id'   # want: groups=...(administrators)
```

Add the user to `administrators` in DSM → 控制面板 → 用户与群组 → 编辑 → 群组. Docker access effectively requires it anyway.

**Gate 2 — password auth is unusable by the agent.** A non-interactive agent shell cannot absorb a password prompt; SSH fails instantly with no visible reason, which reads to the user as "nothing happened". Install a key instead, and hand the user a command for a real terminal:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_<name>.pub <user>@<host>
```

Then verify from the agent side (auth-free when it fails): `ssh -o BatchMode=yes <host> 'echo OK'`.

Key points when walking the user through it:
- **SSH password prompts echo nothing** — no dots, no asterisks, no cursor movement. State this explicitly, or the user reports "typing does nothing".
- **Never let the user paste the password** into the prompt: the terminal echoes it in cleartext, `@` and other characters get swallowed, and a trailing newline submits early. Tell them to type it by hand.
- Let the user self-check the string before spending an auth attempt: `read -s PW && echo "你输入了 ${#PW} 个字符" && unset PW`.
- **TTY-free fallback:** DSM → 用户与群组 → enable 用户主目录, then File Station → `home/.ssh/authorized_keys` containing the public key. Permissions must be `.ssh` 700 and `authorized_keys` 600 or sshd silently ignores the file.
- Never accept the NAS password yourself, and never store it in `.env` (it would migrate into the container along with the rest of the config).

**Gate 3 — DSM auto-block.** DSM locks the source IP after ~5 failed auth attempts in a short window (控制面板 → 安全性 → 自动封锁). After any failed attempts, warn the user to STOP retrying and check the block list. Test reachability without consuming an attempt:

```bash
nc -z -G 3 <host> 22 && echo OPEN || echo BLOCKED
```

## Rule 2 — Docker on DSM: absolute paths and a scoped sudo grant

- `which docker` frequently returns nothing over a non-login SSH shell even though Container Manager is installed. The binary is `/usr/local/bin/docker` → `/var/packages/ContainerManager/target/usr/bin/docker`. Use the absolute path.
- `docker.sock` is `root:root 660` and **there is no `docker` group on DSM** — membership in `administrators` does NOT grant docker CLI access. The failure is `permission denied while trying to connect to the Docker daemon socket`.
- `sudo` for a DSM administrator still requires a password (`sudo: a password is required`), and the agent has none. Ask the user to grant a **scoped** NOPASSWD entry — only the two binaries, not general sudo — and validate before installing:

```bash
printf '%s\n' '<user> ALL=(ALL) NOPASSWD: /usr/local/bin/docker, /var/packages/ContainerManager/target/usr/bin/docker, /usr/local/bin/docker-compose, /var/packages/ContainerManager/target/usr/bin/docker-compose' \
  | sudo tee /etc/sudoers.d/hermes-docker >/dev/null \
  && sudo chmod 440 /etc/sudoers.d/hermes-docker
```

**`sudo` matches the resolved path, not the symlink you typed** — grant every binary twice (the `/usr/local/bin/...` symlink *and* its real target under `/var/packages/ContainerManager/target/usr/bin/...`), or the entry silently never matches and you keep seeing `sudo: a password is required` with no explanation. Include `/usr/syno/bin/synopkg` only when a package restart is genuinely needed — restarting Container Manager restarts every container it manages, so ask first.

**`visudo` does not exist on DSM** (`visudo: command not found`), so the fragment cannot be pre-validated — and a malformed one breaks sudo for everything. Validate after the fact, in this order: confirm the main file includes the directory (`grep -i includedir /etc/sudoers` must show `#includedir /etc/sudoers.d` — the `#` is directive syntax, not a comment), then prove both halves of the grant:

```bash
ssh nas 'sudo -n /usr/local/bin/docker version --format "{{.Server.Version}}"'  # must print a version
ssh nas 'sudo -n /bin/ls /root'                                                # must still say "a password is required"
```

The second command is the real test — it proves the grant stayed scoped instead of opening sudo wholesale.

**Writing the fragment needs root, and `sudo` needs a TTY.** From the agent's shell (including the desktop app's terminal pane) `ssh nas 'sudo ...'` fails with `sudo: a terminal is required to read the password; either use the -S option ...`, which reads to the user as "no prompt appeared, nothing happened". Hand the whole privileged step to the user as an interactive recipe: open the real Terminal app, `ssh nas`, then `sudo -i`, type the password once, paste the block, `exit`. Ask them not to paste passwords into the prompt (the terminal echoes it and swallows `@`).

Container Manager's GUI (项目管理) is the fallback when no grant is possible, but it is slow to iterate against.

Remaining shell facts for this rule:

- The shell is busybox-flavoured: `getent`, `groups`, `synopkg` may not exist. Use `id`, `ls /var/packages`, `ls /var/packages/<pkg>/target/usr/bin/`.
- Container Manager already runs dockerd — never install a second Docker engine alongside it.

## Rule 3 — Registry reachability is a decision point, not an assumption

DNS resolving and the product website loading does NOT imply Docker Hub is reachable. Test the actual registry endpoints and branch on the result:

```bash
for u in https://auth.docker.io/token https://registry-1.docker.io/v2/ \
         https://docker.m.daocloud.io/v2/ https://dockerproxy.net/v2/ \
         https://registry.cn-hangzhou.aliyuncs.com/v2/; do
  printf '%-50s ' "$u"; curl -sS -m 8 -o /dev/null -w 'HTTP=%{http_code}\n' "$u" 2>&1 | tail -1
done
```

`HTTP=401` on a `/v2/` endpoint means **reachable and healthy** (that is the normal unauthenticated reply). `HTTP=000` means the connection failed.

When `auth.docker.io` is unreachable but a mirror answers 401, configure a registry mirror (Container Manager → 注册表 → 设置, or `/var/packages/ContainerManager/etc/dockerd.json` + restart the package) — preferred, since it fixes every future pull. Fallback without touching config: pull the mirror-prefixed path and re-tag:

```bash
docker pull docker.m.daocloud.io/<org>/<image>:<tag>
docker tag  docker.m.daocloud.io/<org>/<image>:<tag> <org>/<image>:<tag>
```

**Pre-flight the tag before spending a pull.** A `/v2/` 401 answers "mirror is up"; it does not prove your image exists or ships your architecture. The challenge header names the token realm — use it, then read the multi-arch index:

```bash
# 1) read the realm from the 401 challenge
curl -sD - -o /dev/null -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
  https://<mirror>/v2/<org>/<image>/manifests/<tag> | grep -i www-authenticate
# 2) trade it for an anonymous pull token, then fetch the manifest; expect HTTP=200
curl -s "https://<token-host>/auth/token?service=<mirror>&scope=repository:<org>/<image>:pull"
curl -s -H "Authorization: Bearer $TOKEN" -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  https://<mirror>/v2/<org>/<image>/manifests/<tag> | grep -E 'architecture|os"'
```

Confirm `amd64`/`linux` is in the list on an x86 DSM unit. Third-party mirrors also vary: probe more than one, since a proxy site can answer `404` for a repo another serves fine. Point the compose `image:` at the mirror-prefixed path once verified, so every later update is a plain `docker compose pull`.

## Rule 4 — Filesystem type decides the backup design

Read it before promising anything: `grep ' /volume1 ' /proc/mounts`.

- **ext4 volumes cannot do Btrfs snapshots.** Snapshot Replication is unavailable on them. Do not plan around snapshots; fall back to scheduled `rsync` to another machine, CloudSync, or Hyper Backup (**not installed by default** — check `ls /var/packages`).
- A NAS data directory is usually the ONLY copy of irreplaceable state. Always pair the service's own export/backup command with an off-device copy.
- **Never place a live SQLite/WAL data directory on NFS, SMB, or FUSE**, and never publish it via SMB while a container has it open. Local volume bind mount only. A block-level rsync of a running DB is also unsafe — use the app's own backup command, or stop the container first.

## Rule 5 — Size the workload against the NAS class

Check `free -m` (total AND available) and `nproc` before promising a service.

- 2 GB-class units have ~1 GB usable after DSM. Long-running agent/bot processes fit, but browser-automation toolsets, parallel subagents, and embedding backfills do not. Set an explicit container memory limit and disable the heavy toolsets on such units.
- Swap on HDD-backed volumes throttles hard; treat it as crash protection, not headroom.
- **When RAM is the binding constraint, do not block the deployment on hardware.** Ship a limited configuration, and recommend the memory upgrade in parallel: most 2-bay `+` models have one free SODIMM slot reachable by removing the drive trays, and Synology's official ceiling is usually half what community-tested sticks achieve (e.g. DS218+: 2 GB soldered + free slot, official 6 GB, 8 GB DDR3L SODIMMs verified working).
- Confirm the CPU architecture (`uname -m`) supports the image; `apollolake`-class Celerons are x86_64 and fine.
- **Never set `cpus:` in compose on DSM.** The kernel exposes no CFS CPU quota and container creation fails outright: `NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler or the cgroup is not mounted`. `mem_limit` is the limit that works; drop `cpus` entirely rather than "fixing" it.
- Disk: check `df -h /volume1` — images plus data need multiple GB free; a volume above ~85% full causes churn and should be flagged before, not after, the pull.

## Rule 6 — Find the box by MAC when the IP has drifted

A NAS IP from memory is often stale (DHCP). Sweep and filter by Synology's OUI `00:11:32` / `00:1b:2f` / `00:08:9b`:

```bash
for i in $(seq 1 254); do ping -c1 -W200 192.168.1.$i >/dev/null 2>&1 & done; wait
arp -a | grep -iE '00:11:32|00:1b:2f|00:08:9b'
```

An `ARP ... (incomplete)` entry means the host is on the subnet but dark — treat it as offline, not as a wrong password. Then tell the user to bind the MAC to a fixed address in the router; otherwise the same failure recurs.

## Rule 7 — Deploy in stages so the running production service never blinks

When the target host is taking over a workload that is live elsewhere (bots, gateways, schedulers), split the work:

1. **Stage 1 — completely inert to the current host:** registry access, data directory, image pull, compose file, container up, service-level health check. The existing machine keeps serving. **Boot the new container with every messaging platform explicitly disabled** — a second gateway holding the same bot credentials disconnects the running host even when it uses its own data directory. Disable them through the CLI before the first start (recipe in `references/hermes-in-docker.md`).
2. **Stage 2 — switch the channels that can only be live in one place** (message bot tokens), one at a time, verifying each.
3. **Stage 3 — freeze the old host** only after every acceptance check passes.

Run `scripts/verify-hermes-container.sh` as the mechanical part of the Stage-1 acceptance battery. Define the acceptance list and the rollback trigger as hard, checkable conditions up front (e.g. "three consecutive unanswered messages on any channel, or missing memory state → stop the container and restart the old host"), not as a feeling. Keep the old host intact and stopped rather than uninstalled — it is the rollback path.

## Rule 8 — Getting bytes onto the NAS: `scp` is the wrong tool

- **`scp` dies with `Connection closed` on a default DSM install.** macOS ships OpenSSH 9+, which speaks SFTP first, and DSM leaves the SFTP subsystem off unless it is enabled separately. Do not send the user hunting for that toggle — pipe instead:

```bash
ssh nas 'cat > /volume1/docker/<svc>/docker-compose.yaml' < ./docker-compose.yaml
```

- **Bulk trees: `tar` over SSH, not `rsync`.** macOS `rsync` is `openrsync`, a 2.6.9-compatible subset that silently lacks flags GNU-shaped recipes assume. `COPYFILE_DISABLE=1` suppresses the `._*` AppleDouble files, and extraction as the admin user re-owns everything to that user for free — which is what a container pinned to `HERMES_UID`/`PUID` of that user needs:

```bash
cd <src> && COPYFILE_DISABLE=1 tar -cf - --exclude='./state.db' . | ssh nas 'tar -C <dest> -xf -'
```

- **Store from macOS floods the receiving tar with xattr noise** — `Ignoring unknown extended header keyword 'LIBARCHIVE.xattr.com.apple.provenance'`, thousands of lines that bury the single real error. Send tar's stderr to a file, then filter: what survives is the actual failure list (and may legitimately be just unusable entries like `pax format cannot archive sockets`).

- Transfer as the admin user, then `chmod 600` anything holding credentials (env files, compose files under a data directory) — a data directory created world-writable at the top level leaves secrets readable to every account on the box.

## Standing user-facing rules for this class

- The interactive steps belong to the user: password prompts, DSM GUI toggles, enabling SSH, scanning a pairing QR. Hand over the exact command plus the expected success output, and explain what "no output" means (silence means success for most Unix one-liners).
- Do not touch DSM system settings, existing shared folders, or other containers' data. Confine writes to the new data directory and the new container; ask before anything destructive (sudoers, package restart, deleting data).
- Report findings as facts with the raw command output that produced them, then ask for decisions — never present an assumption about the hardware as a plan.
- Work large infra moves in **rounds**: put the whole open decision frontier to the user at once, one decision per item with your recommended answer stated first and the reasoning compressed to one line, then wait for approval before running anything. Approve-then-execute, and execute in the staged order above, reporting verified results (command output) rather than intentions.
