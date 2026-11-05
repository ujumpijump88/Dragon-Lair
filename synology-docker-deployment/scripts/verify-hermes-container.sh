#!/bin/sh
# Acceptance battery for a Hermes Agent container on a NAS (Synology Container Manager).
#
# Run on the Docker host, or pipe it over SSH from the workstation:
#   ssh nas 'CONTAINER=hermes HERMES_DASH_USER=u HERMES_DASH_PASS=p API_KEY=k sh -s' \
#     < scripts/verify-hermes-container.sh
#
# Env:
#   HERMES_DASH_USER, HERMES_DASH_PASS   dashboard credentials (needed for the auth check)
#   API_KEY                              API_SERVER_KEY (needed for the gateway API check)
#   CONTAINER   default hermes
#   WEB_PORT    default 9119
#   API_PORT    default 8642
#   DOCKER      default "sudo -n /usr/local/bin/docker"
#
# Note: the dashboard login is a JSON POST to /auth/password-login. There is no HTTP Basic
# auth, so curl -u can never succeed here - do not "fix" this back to -u.

CONTAINER=${CONTAINER:-hermes}
WEB_PORT=${WEB_PORT:-9119}
API_PORT=${API_PORT:-8642}
DOCKER=${DOCKER:-"sudo -n /usr/local/bin/docker"}
CK=$(mktemp 2>/dev/null || echo /tmp/hermes-verify-ck.txt)
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
skip() { printf 'SKIP  %s\n' "$1"; }

printf '== Hermes container acceptance: %s ==\n' "$CONTAINER"

# 1. container up
$DOCKER ps --filter "name=^${CONTAINER}$" --format '{{.Names}} {{.Status}} {{.Ports}}' | grep -q "$CONTAINER" \
  && ok "container running: $($DOCKER ps --filter "name=^${CONTAINER}$" --format '{{.Status}}')" \
  || bad "container not running"

# 2. both supervised processes alive
for p in 'hermes gateway' 'hermes dashboard'; do
  if $DOCKER exec "$CONTAINER" ps -eo cmd 2>/dev/null | grep -v grep | grep -q "$p"; then
    ok "process alive: $p"
  else
    bad "process missing: $p (check docker logs; a config error aborts the multiplexer)"
  fi
done

# 3. gateway health endpoint
HEALTH=$($DOCKER exec "$CONTAINER" curl -sS -m 10 "http://127.0.0.1:${API_PORT}/health" 2>/dev/null)
case "$HEALTH" in
  *'"status": "ok"'*|*'"status":"ok"'*) ok "gateway health: $HEALTH" ;;
  *) bad "gateway health endpoint: ${HEALTH:-no response}" ;;
esac

# 4. real completion through the gateway (proves model auth + prompt assembly)
if [ -n "$API_KEY" ]; then
  RESP=$($DOCKER exec "$CONTAINER" curl -sS -m 180 -H "Authorization: Bearer $API_KEY" \
    -H 'Content-Type: application/json' \
    -d '{"model":"hermes","messages":[{"role":"user","content":"reply with the single word OK"}]}' \
    "http://127.0.0.1:${API_PORT}/v1/chat/completions" 2>/dev/null)
  case "$RESP" in
    *'"content"'*) ok "gateway completion: $(printf '%s' "$RESP" | tr -d '\n' | cut -c1-160)" ;;
    *) bad "gateway completion failed: $(printf '%s' "$RESP" | cut -c1-200)" ;;
  esac
else
  skip "gateway completion (set API_KEY)"
fi

# 5. dashboard login + identity (JSON POST, not HTTP Basic)
if [ -n "$HERMES_DASH_USER" ] && [ -n "$HERMES_DASH_PASS" ]; then
  curl -sS -m 10 -c "$CK" -o /dev/null "http://127.0.0.1:${WEB_PORT}/login" 2>/dev/null
  LOGIN=$(curl -sS -m 15 -b "$CK" -c "$CK" -H 'Content-Type: application/json' \
    -d "{\"provider\":\"basic\",\"username\":\"$HERMES_DASH_USER\",\"password\":\"$HERMES_DASH_PASS\",\"next\":\"/\"}" \
    "http://127.0.0.1:${WEB_PORT}/auth/password-login" 2>/dev/null)
  case "$LOGIN" in
    *'"ok":true'*|*'"ok": true'*) ok "dashboard login accepted" ;;
    *) bad "dashboard login rejected: $(printf '%s' "$LOGIN" | cut -c1-160) (wrong provider name / wrong path / wrong credentials)" ;;
  esac
  ME=$(curl -sS -m 10 -b "$CK" "http://127.0.0.1:${WEB_PORT}/api/auth/me" 2>/dev/null)
  case "$ME" in
    *'"user_id"'*) ok "dashboard identity: $(printf '%s' "$ME" | cut -c1-140)" ;;
    *) bad "dashboard identity: ${ME:-no session}" ;;
  esac
else
  skip "dashboard login (set HERMES_DASH_USER / HERMES_DASH_PASS)"
fi
rm -f "$CK"

# 6. memory headroom - the binding constraint on 2 GB-class units
printf '-- container memory --\n'
$DOCKER stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.MemPerc}}' "$CONTAINER" 2>/dev/null
printf '-- host memory --\n'
free -m 2>/dev/null | head -2

printf '\n== %d passed, %d failed ==\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
