#!/bin/bash
# Refresh /Applications/Hermes.app (or the Linux/Windows equivalent) after `hermes update`
# reported the bundle was skipped because the desktop app was running.
#
# Usage: run DETACHED so it survives the desktop app + its backend exiting:
#   python3 -c "import os,sys
#   if os.fork()>0: sys.exit(0)
#   os.setsid()
#   if os.fork()>0: sys.exit(0)
#   os.execv('/bin/bash',['/bin/bash','<abs path to this script>'])"
# launchctl submit/bootstrap is blocked inside a supervised gateway - do not use it.
# Confirm with the user first: this quits the desktop app and ends the current session.
set -u
export PATH="$HOME/.hermes/hermes-agent/.hermes/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# CN network: node ignores git/system proxy, and Electron is fetched from GitHub release assets.
# Prefer the registry binary path - the npmmirror.com/mirrors/electron/ host can fail outright on a
# proxy-less network while registry.npmmirror.com/-/binary/electron/ answers directly.
export ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://registry.npmmirror.com/-/binary/electron/}"
export npm_config_registry="${npm_config_registry:-https://registry.npmmirror.com}"
export NO_PROXY="localhost,127.0.0.1"
LOG=/tmp/hermes-refresh.log
APP=/Applications/Hermes.app
MAIN="$APP/Contents/MacOS/Hermes"
HERMES=$(command -v hermes || echo "$HOME/.hermes/hermes-agent/.hermes/bin/hermes")
: > "$LOG"
echo "=== $(date) start (hermes=$HERMES)" >> "$LOG"

# Give the agent's turn time to finish delivering its message.
sleep "${START_DELAY:-20}"

osascript -e 'quit app "Hermes"' >> "$LOG" 2>&1
for _ in $(seq 1 30); do pgrep -f "$MAIN" >/dev/null || break; sleep 1; done
if pgrep -f "$MAIN" >/dev/null; then
  echo "force-terminating desktop app" >> "$LOG"
  pkill -TERM -f "$MAIN"; sleep 5; pkill -KILL -f "$MAIN" 2>/dev/null; sleep 2
fi
echo "=== app quit, running update" >> "$LOG"

cd "$HOME/.hermes/hermes-agent" || exit 1
"$HERMES" update -y >> "$LOG" 2>&1
RC=$?
echo "=== update exit=$RC" >> "$LOG"

sleep 2
open -a "$APP" >> "$LOG" 2>&1
echo "=== $(date) relaunched (update rc=$RC)" >> "$LOG"
# Verify afterwards: app.asar mtime must now be newer than before, and `hermes --version` current.
