# Deploying Hermes on a Home NAS (Docker) — Synology DSM Workflow

Scope: move a working single-machine Hermes onto an always-on NAS (Synology Container Manager /
docker) and expose it remotely. The staging discipline and the recon table apply to any Docker
host; the DSM, macOS-client and Tailscale notes are the parts that are not obvious.

## Stage the cutover — never flip everything at once
1. Prep + verify on the new host with **every chat platform disabled**.
2. Switch ONE platform (old host stops serving it → new host starts), verify with a real message.
3. Switch the rest, then stop the old host's gateway; keep its data dir frozen as the rollback.

Why: a gateway that connects the same bot credentials from two hosts fights itself and the bot
silently stops answering real users. Staging turns the interruption into seconds instead of
"unknown length".
- Platform enablement is read at gateway start, so a flip means restarting that host's gateway —
  which drops and reconnects **every** platform on it, not just the one being moved. Budget and
  announce the whole window, not the part that was asked for.
- Proof of a live adapter lives in the container log: `Connecting to <platform>…`,
  `✓ <platform> connected`, then the adapter's own `Ready, session_id=…`. Finish with a real
  inbound message from the platform — a connected adapter is not yet a working bot.

## Working agreement for infra changes
- Ask, don't assume: put the plan to the user as numbered questions, each with a recommended
  answer, and wait for sign-off before running anything.
- Lead with a table of recon facts, then the questions; re-ask when a new fact invalidates an
  earlier answer.
- State the real interruption window rather than the hoped-for one, and prefer a low-traffic
  window (late night, for a study group) for the flip.

## 0. Recon the host before promising anything
Each fact changes the plan — collect them first, report the numbers, then choose limits:

| Check | Command | What it decides |
|---|---|---|
| arch | `uname -m` | image variant |
| total RAM | `grep MemTotal /proc/meminfo` | container memory cap; browser tools on/off |
| volume fs | `grep ' /volume1 ' /proc/mounts` | ext4 → **no** Btrfs snapshots, backup plan changes |
| docker | `ls -l /usr/local/bin/docker` | DSM ships docker under Container Manager and it may be absent from a non-login PATH — call the full path |
| privilege | `sudo -n true` | whether a sudoers grant is needed |
| egress | `curl -sS -m 8 -o /dev/null -w '%{http_code}' <url>` for the model provider, the Hermes installer host, and the container registry | which provider is actually usable; whether images must come from a mirror |

## 1. Access and least-privilege sudo
- DSM: SSH is off by default and only `administrators`-group accounts may use it; the user enables
  it in 控制面板 → 终端机与 SNMP.
- Install an SSH key, and hand the user the exact `ssh-copy-id` / paste-block command to run
  themselves — password prompts need a real TTY and an agent session cannot answer them. Never
  ask for the password, and never store it in `SUDO_PASSWORD`: that `.env` is itself copied to
  the NAS, so it would travel with the data it protects.
- Repeated failed password attempts trip DSM's auto-block IP ban. Probe reachability with a TCP
  connect instead of retrying logins; if the IP is banned, the user clears it in
  控制面板 → 安全性 → 自动封锁.
- `docker.sock` is `root:root` and there is no `docker` group. Grant NOPASSWD for the exact
  binaries only (docker, docker-compose, synopkg, any VPN CLI) into `/etc/sudoers.d/<name>`
  mode 440, written by the user from a root shell. List BOTH the convenience symlink and its
  resolved target (`/usr/local/bin/docker` *and*
  `/var/packages/ContainerManager/target/usr/bin/docker`): sudo matches on the resolved path, so a
  grant naming only the symlink silently never applies. Confirm the directory is loaded at all
  with `grep -i includedir /etc/sudoers`.
- DSM has no `visudo` — validate the grant **functionally** (`sudo -n <cmd> version`) and confirm
  the boundary still holds (`sudo -n <unlisted-cmd>` must still ask for a password).

## 2. Image
- Docker Hub is commonly unreachable from home/CN networks while mirrors are not. Pull through a
  mirror prefix and tag it, or configure a registry mirror on the host.
- Pre-check the tag before pulling: an anonymous token request
  (`<mirror>/auth/token?service=…&scope=repository:<repo>:pull`) then a manifest GET should be 200.
- Compose for DSM: omit `cpus:` — the DSM kernel has no CFS quota, `docker compose up` fails with
  `NanoCPUs can not be set` and the container never starts. `mem_limit` works and is the useful knob.
- Keep the mirror-prefixed reference in the compose `image:` (not only on the pull command) so a
  later update is just `docker compose pull && docker compose up -d`.
- `scp` into DSM can fail with `Connection closed` because the SFTP subsystem is disabled; write
  files with `ssh host 'cat > /path' < local` or a tar pipe.

## 3. Copy the data
- Exclude what is reproducible: git source tree, `node/`, `bin/`, `lsp/`, `logs/`, `backups/`,
  `*.bak*`, caches. Keep `config.yaml`, `.env`, `auth.json`, `state.db`, `skills/`, `memories/`,
  `sessions/`, `profiles/`.
- Snapshot every live SQLite db with the backup API (python `sqlite3` `src.backup(dst)`) — never
  `cp` a WAL database — and install the snapshots as the real files.
- **Exclusion patterns silently eat real content.** A generic `*/hermes-agent` also matches
  `skills/autonomous-ai-agents/hermes-agent/`. After every bulk copy, diff file counts *and* the
  sorted file list per top-level dir against the source, then re-copy what is missing.
- From macOS: `rsync` is openrsync, which does not read `~/.ssh/config` — it degrades to password
  auth and fails. Use a `tar -cf - … | ssh host 'tar -xf -'` pipe, or pass an explicit
  `-e "ssh -i <key> -o IdentitiesOnly=yes"`. macOS also has no `timeout` binary.
- Grep the copy for host-specific artifacts and drop them: a cron script calling a macOS-only
  binary fails forever on Linux — remove the JOB, not just the script.
- Platform credentials must end up in exactly one profile; strip them from the others (see
  `multi-profile-gateway.md`).
- Set the timezone twice: container env `TZ=<zone>` **and** `hermes config set timezone <zone>`.
  A container otherwise runs UTC and every timestamp and cron schedule drifts.
- WAL databases need a local bind mount — NFS/SMB/FUSE backing risks corrupting them, so on a
  NAS point the data dir at a local volume path.

## 4. First boot with platforms OFF
- Before the very first start, disable each chat platform in the target config so the new gateway
  cannot grab the credentials the old host is still serving:
  `hermes config set platforms.<platform>.enabled false`.
- You can run the CLI without starting the gateway via a one-off container:
  `docker run --rm -e HERMES_UID=<uid> -e HERMES_GID=<gid> -v <data>:/opt/data <image> hermes config set …`
- The gateway multiplexes **every** profile in the container: one profile with an invalid platform
  config aborts startup for all of them — see the startup-abort section in
  `multi-profile-gateway.md`.
- The dashboard needs the gateway's API server: `API_SERVER_ENABLED=true`, keep
  `API_SERVER_HOST=127.0.0.1`, and publish only the dashboard port.
- Container env vs the mounted `.env`: **the `.env` file wins**. Define each secret once — a stale
  `API_SERVER_KEY` in a copied `.env` silently invalidates the value set in compose.

## 5. Verify layer by layer
`docker ps` showing Up is not verification. Check in order:
1. `docker exec <c> ps -eo pid,etime,cmd | grep 'hermes gateway'` — the gateway survives s6
   restarts and stays up (the dashboard keeps the container `Up` even when the gateway has died).
2. `curl 127.0.0.1:<api-port>/health` → `{"status":"ok"}`.
3. A real completion through the gateway's own API (loopback + key) — this proves skills, memory
   and provider wiring, not merely that a process exists. The listener can take ~30 s to bind
   after `up -d` — an immediate connection-refused is not yet a failure; re-probe before
   diagnosing.
4. Dashboard login: `POST /auth/password-login` with JSON
   `{"provider":"basic","username":…,"password":…,"next":"/"}` returns session cookies, then
   `GET /` with the cookie returns 200. It is **not** HTTP Basic and **not** a form POST; a wrong
   path merely redirects to `/login?next=…` and looks like a credentials failure. Confirm the
   identity afterwards with `GET /api/auth/me` (returns the username and provider).
5. `docker stats` + `free -m` on the host — the host, not the container, is the real limit.

## 6. Remote access (Tailscale on DSM)
- Install the vendor SPK directly when the package-server query fails: download
  `tailscale-x86_64-<ver>-dsm7.spk` from the vendor's stable URL and `synopkg install <file>.spk`.
- The DSM package runs userspace networking with its socket under `/volume1/@appdata/Tailscale/`.
  `up` / `logout` need root, or a one-time `tailscale set --operator=<user>` from a root shell —
  after that the CLI works unprivileged.
- Non-interactive join: generate an auth key in the admin console and pass `--authkey=`. The
  `Pre-approved` checkbox only appears when the tailnet has device approval enabled.
- **Accounts are domain-scoped.** Signing in with an email at a public or corporate domain can
  drop the user into someone else's organization tailnet ("Your account is unpaid / the tailnet
  has reached the maximum number of users"). Fix: sign in with Google/Apple/Microsoft/GitHub or a
  recognized personal domain, and create the account BEFORE joining any device.
- macOS client: the GUI app owns the connection, so the CLI cannot `tailscale up` — login must be
  completed in the app. A browser still holding the previous account's session blocks the flow;
  log out first or use a private window.
- Synology QuickConnect proxies only DSM's own web services — it cannot reach SSH or an arbitrary
  container port, so it is not a substitute for the VPN.

## 7. Backups on a non-snapshot host
ext4 (no Btrfs) means no free snapshots. Layer three things: a container-side consistent DB
backup, a nightly full mirror to a second machine, and a weekly archive with rotation.
- Run the nightly job from the machine that already has key-based access (e.g. launchd on the
  Mac) so no extra permission is needed on the NAS.
- Keep the consistency step inside the container (`docker exec <c> python3 /opt/data/scripts/backup-db.py`)
  — the host usually has no matching SQLite tooling.
- Use the tar-over-ssh pipe for the mirror when the driving machine is macOS.
- The old machine's frozen data dir IS the rollback copy; do not delete it until the new host has
  run clean for a while.

## Hardware headroom
- DS218+ class (2-bay, Apollo Lake): 2 GB onboard plus one free DDR3L SO-DIMM slot, reachable after
  removing the drive trays — no disassembly needed. Official max 6 GB; a single 8 GB DDR3L 1600
  (PC3L-12800S, 1.35V, non-ECC, 204-pin) module is community-verified for 10 GB total. Buy the
  aftermarket module, not the vendor-branded 4 GB part.
- While RAM is tight, cap the container with `mem_limit` and leave browser tools off; raise the cap
  after the memory is added.
