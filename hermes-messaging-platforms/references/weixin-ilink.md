# Weixin (personal WeChat) via Tencent iLink

## What it is
Hermes adapter for **personal WeChat accounts** using Tencent's iLink Bot API. Long-polling transport — no public endpoint/webhook needed. Distinct from WeCom (enterprise WeChat).

## Setup
1. `hermes gateway setup` → select Weixin → terminal QR login (`gateway.platforms.weixin.qr_login`).
2. Scan with the WeChat mobile app, **tap confirm on the phone** (times out ~30s otherwise, QR regenerates).
3. Credentials auto-saved to `~/.hermes/.env` + `~/.hermes/weixin/accounts/`.
4. Start/restart gateway: `hermes gateway` / `hermes gateway restart`. Works when run manually (not just as a service).

## Environment variables (~/.hermes/.env)
Required: `WEIXIN_ACCOUNT_ID`, `WEIXIN_TOKEN`, `WEIXIN_BASE_URL` (default https://ilinkai.weixin.qq.com), `WEIXIN_CDN_BASE_URL` (default https://novac2c.cdn.weixin.qq.com/c2c)
DM policy: `WEIXIN_DM_POLICY` (pairing|open|allowlist|disabled), `WEIXIN_ALLOW_ALL_USERS`, `WEIXIN_ALLOWED_USERS`
Groups: `WEIXIN_GROUP_POLICY`, `WEIXIN_GROUP_ALLOWED_USERS`
Delivery: `WEIXIN_HOME_CHANNEL`, `WEIXIN_HOME_CHANNEL_NAME`

## config.yaml
```yaml
platforms:
  weixin:
    enabled: true
```

## Log signatures (~/.hermes/logs/agent.log)
- Connected: `gateway.platforms.weixin: [Weixin] Connected account=<id> base=https://ilinkai.weixin.qq.com`
- Inbound: `[Weixin] inbound from=<uid> type=dm media=0` then `inbound message: platform=weixin user=<uid>@im.wechat chat=... msg='...'`
- Outbound: `response ready: platform=weixin chat=... response=N chars` then `[Weixin] Sending response (N chars) to <uid>`
- Transient (normal): `[Weixin] poll error (n/3): Server disconnected` / `Cannot connect to host ilinkai.weixin.qq.com:443` — auto-retry with backoff; only worry if continuous.
- Non-blocking media hiccup: `[Weixin] send_voice failed to=...` — the text reply is still sent afterwards.

## Limitations (iLink side, NOT a config bug)
- The bot is a separate identity `xxx@im.bot` — NOT the personal account that scanned the QR. @-mentioning the personal account ≠ mentioning the bot.
- Ordinary WeChat groups generally cannot invite the bot and iLink usually does not deliver group events — **DM is the only reliable channel** regardless of group policy settings.
- Docs: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/weixin/

## Verified example diagnostics (real session)
- `hermes gateway status` → "Gateway is running (PID ...)" with only a whatsapp warning → weixin OK.
- Real traffic proof in agent.log: inbound '收到' → reply 114 chars; inbound '现在几点' → reply. Config alone is not proof; message lines are.
- Two transient `poll error` entries ~15 min apart, auto-recovered (inbound still received after) — no action needed.
