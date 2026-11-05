#!/bin/bash
# Read-only Synology NAS reconnaissance. Never modifies anything.
# Usage: ./nas-recon.sh <host> [user]     (requires passwordless SSH)
set -u
HOST="${1:?usage: nas-recon.sh <host> [user]}"
USR="${2:-$(whoami)}"
ssh -o ConnectTimeout=10 -o BatchMode=yes "${USR}@${HOST}" '
echo "=== identity ==="; id; hostname
echo "=== arch / kernel ==="; uname -m; uname -r
echo "=== DSM version ==="; cat /etc/VERSION
echo "=== model ==="; cat /proc/sys/kernel/syno_hw_version 2>/dev/null
echo "=== cpu / memory ==="; nproc; grep MemTotal /proc/meminfo; free -m
echo "=== volume + FILESYSTEM (decides snapshot/backup options) ==="
df -h /volume1; grep " /volume1 " /proc/mounts
echo "=== docker binary + socket ==="
ls -l /usr/local/bin/docker 2>&1
ls -l /var/run/docker.sock 2>&1
ls /var/packages/ContainerManager/target/usr/bin/ 2>/dev/null | head -12
echo "=== sudo state ==="; (sudo -n true 2>/dev/null && echo SUDO_NOPASS_OK) || echo SUDO_NEEDS_PASSWORD
echo "=== installed packages ==="; ls /var/packages | tr "\n" " "; echo
echo "=== existing data dir ==="; ls -la /volume1/docker 2>&1 | head -20
echo "=== running containers (only if docker usable) ==="
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>&1 | head -10
echo "=== timezone ==="; date
echo "=== outbound reachability (401 on /v2/ = reachable) ==="
for u in https://hermes-agent.nousresearch.com/docs/ https://portal.nousresearch.com/ \
         https://api.deepseek.com/ https://q.qq.com/ https://pypi.org/simple/ \
         https://auth.docker.io/token https://registry-1.docker.io/v2/ \
         https://docker.m.daocloud.io/v2/ https://dockerproxy.net/v2/ \
         https://registry.cn-hangzhou.aliyuncs.com/v2/ https://ghcr.io/v2/ https://quay.io/v2/; do
  printf "%-50s " "$u"
  curl -sS -m 8 -o /dev/null -w "HTTP=%{http_code} t=%{time_total}s\n" "$u" 2>&1 | tail -1
done
echo "=== proxy env ==="; env | grep -i proxy || echo NO_PROXY_ENV
'
