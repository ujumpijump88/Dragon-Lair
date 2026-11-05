#!/bin/bash
# Hindsight local-memory daemon start/stop/status — copy & adapt to any local daemon.
# Why direct start instead of `uvx hindsight-embed daemon start`:
#   the CLI manager's ~180s readiness timeout kills the (healthy) child on this machine.
# Why NO_PROXY: macOS system proxy makes Python httpx return 502 on localhost.
#
# Usage: start-hindsight.sh [start|stop|status]

set -e

API_BIN="$HOME/.local/share/uv/tools/hindsight-api/bin/hindsight-api"
CONFIG_FILE="$HOME/.hindsight/embed"
PORT=8888
LOG_FILE="$HOME/.hindsight/daemon.log"
export NO_PROXY="localhost,127.0.0.1"
export no_proxy="localhost,127.0.0.1"

health() {
  curl -s --max-time 3 "http://127.0.0.1:${PORT}/health" 2>/dev/null | grep -q healthy
}

stop_daemon() {
  local pid
  pid=$(lsof -nP -ti "TCP:${PORT}" 2>/dev/null | head -1)
  if [ -n "$pid" ]; then
    echo "Stopping daemon (PID $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 2
    echo "Stopped"
  else
    echo "Daemon not running"
  fi
}

case "${1:-start}" in
  stop)
    stop_daemon
    exit 0
    ;;
  status)
    if health; then
      echo "OK: daemon running (127.0.0.1:${PORT})"
    else
      echo "DOWN: daemon not running"
    fi
    exit 0
    ;;
  start)
    if health; then
      echo "OK: daemon already running (127.0.0.1:${PORT})"
      exit 0
    fi
    echo "Starting daemon..."
    # Config reaches the daemon only via env vars (manager injects them normally).
    set -a
    source <(grep -E '^[A-Z_]+=' "$CONFIG_FILE")
    set +a
    export HINDSIGHT_API_DAEMON_LOG="$LOG_FILE"
    nohup "$API_BIN" --idle-timeout 0 --port "$PORT" >> "$LOG_FILE" 2>&1 &
    echo "Waiting for readiness (warm ~15-60s, cold ~3min)..."
    for i in $(seq 1 40); do
      if health; then
        echo "OK: http://127.0.0.1:${PORT}/health"
        exit 0
      fi
      sleep 5
    done
    echo "FAILED: timeout waiting for daemon; see $LOG_FILE"
    exit 1
    ;;
  *)
    echo "Usage: $0 [start|stop|status]"
    exit 1
    ;;
esac
