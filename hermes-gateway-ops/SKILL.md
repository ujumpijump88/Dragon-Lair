---
name: hermes-gateway-ops
description: "Diagnose Hermes gateway provider-auth failures and restarts."
---

# Hermes Gateway Operations & Troubleshooting

## "Provider authentication failed" (供应商认证失败) — validated workflow

Symptom: a gateway platform (e.g. WeChat) is connected, but replies come back as "供应商认证失败 / provider auth failed". The channel is fine; the LLM provider credential is broken.

1. **Logs first**: `grep -iE "weixin|401|auth|credential" ~/.hermes/logs/agent.log | tail`.
   Look for the session's `provider=<name> base_url=<url> model=<model>`, `Error code: 401 Invalid Authentication`, and credential-pool lines: `marking <KEY> exhausted (status=401), rotating` + `no available entries (all exhausted or empty)` = no valid key for that provider.
2. **Probe the keys directly** (never echo the key — print length/status only):
   ```bash
   for k in KEY1 KEY2; do v=$(grep -E "^$k=" ~/.hermes/.env | cut -d= -f2-); echo "$k len=${#v}"; done
   curl -s -o /tmp/r.json -w "HTTP %{http_code}\n" -H "Authorization: Bearer $v" https://<provider>/v1/models
   ```
   Test BOTH endpoints when in doubt (e.g. api.moonshot.cn AND api.moonshot.ai). 401 on both = key invalid/revoked; 403 quota message = billing-cycle limit (even a valid key won't help this cycle).
3. **Fix** — switch to a known-good provider (always verify the replacement key with the same curl probe first):
   ```bash
   hermes config set model.provider deepseek
   hermes config set model.default deepseek-v4-flash
   ```
   Never hand-edit config.yaml — `hermes config set` only.
4. **Restart the manual gateway**: `hermes gateway status` says "Running manually" → `kill <pid>` (may need `kill -9`; a `Z <defunct>` state is normal until the parent reaps — confirm with `ps -p <pid> -o state`) → start fresh with `hermes gateway run` as a background process. Provider/credential pools load at startup, so a restart is REQUIRED for the change to take effect.
5. **Verify end-to-end**: `hermes gateway status`; log shows `✓ weixin connected`; send a test outbound with `hermes send -t weixin:<chat_id> "test"` (or `-t <platform>` = home channel); have the user reply from the platform and check the log for `provider=deepseek` + `Sending response`.

## WeChat (weixin/iLink) platform notes

- Native adapter = Tencent iLink bot (identity like `xxx@im.bot`); QR login via `hermes gateway setup` → Weixin. Credentials live in `~/.hermes/.env` (WEIXIN_ACCOUNT_ID / TOKEN / BASE_URL / CDN_BASE_URL / DM_POLICY / HOME_CHANNEL ...).
- DM policy `pairing` (default): first-time senders need approval — `hermes pairing list`, then `hermes pairing approve weixin <request-id>`.
- Ordinary WeChat groups generally DON'T work (iLink does not deliver group events to bot identities) — DM only; keep WEIXIN_GROUP_POLICY=disabled.
- Transient `[Weixin] poll error (1/3): Server disconnected` / `Cannot connect to ilinkai.weixin.qq.com:443` auto-retries — cosmetic unless persistent.
- An itchat-uos personal-WeChat bridge was tried earlier and abandoned (web protocol unstable/risky) — always prefer the native weixin platform.

## Pitfalls

- **macOS system proxy vs httpx**: on machines with a Clash-type system proxy (e.g. 127.0.0.1:7897), httpx reads it via SystemConfiguration even with NO proxy env vars, so localhost health checks time out while curl/requests work fine. Any httpx-based Hermes tooling can misbehave. Fix: `export NO_PROXY="127.0.0.1,localhost"` (see hindsight-memory-backend → references/china-network-downloads.md).
- The gateway model comes from config.yaml `model.*`; the desktop chat may run a per-chat override — always check the log line for the actual provider/model used by the failing platform.
- `hermes pairing approve` needs a pending request; `hermes pairing list` shows approved users (your own account shows up once approved — nothing to approve).
