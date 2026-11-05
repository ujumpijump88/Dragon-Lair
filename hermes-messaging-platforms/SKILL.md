---
name: hermes-messaging-platforms
description: "Verify/set up Hermes messaging platform channels (Weixin, WeCom, QQ Bot, Telegram, etc.) and per-channel personas."
---

# Hermes Messaging Platforms (Gateway Channels)

Connecting, verifying, and troubleshooting Hermes' messaging platform adapters — the gateway channels: Weixin/WeChat, Telegram, Discord, WeCom, Feishu, DingTalk, QQ, WhatsApp, etc.

## Golden rule: native adapter first, custom bridge last

Hermes ships native gateway adapters for many platforms, including **Weixin (personal WeChat) via Tencent iLink** — QR-login based, long-polling, no webhook needed. **Before building any custom bridge (itchat / wechaty / unofficial protocols), check `~/.hermes/hermes-agent/plugins/platforms/` and `hermes gateway setup`.** Unofficial personal-WeChat automation (itchat-uos etc.) risks account bans and is superseded by the native adapter. Do not build a bridge when a platform plugin exists. The user's "消息平台 / messaging platform" dashboard writes the same `platforms.<name>.enabled` config and `.env` creds that `hermes gateway setup` writes — check those first.

## Verification workflow (is a platform correctly configured?)

1. **Platform switch**: `platforms.<name>.enabled: true` in `~/.hermes/config.yaml`.
2. **Credentials**: env keys in `~/.hermes/.env`. Check presence/length ONLY — never print token values.
   ```bash
   for k in WEIXIN_ACCOUNT_ID WEIXIN_TOKEN ...; do v=$(grep -E "^$k=" ~/.hermes/.env | head -1 | cut -d= -f2-); echo "$k = $([ -n "$v" ] && echo SET || echo empty)"; done
   ```
3. **Gateway running**: `hermes gateway status` — expect "Gateway is running (PID ...)" plus per-platform warnings (e.g. whatsapp unpaired). An absent warning for the target platform = good sign.
4. **Connection + real traffic** (strongest evidence): grep `~/.hermes/logs/agent.log` for the platform:
   - Connected: `✓ weixin connected account=<id> base=...`
   - Inbound: `inbound message: platform=weixin user=... msg='...'`
   - Outbound: `response ready: platform=weixin ...` then `[Weixin] Sending response (N chars) to ...`
   - Actual inbound/outbound message lines prove the channel works end-to-end; static config alone is not proof.
5. **Docs are authoritative**: `https://hermes-agent.nousresearch.com/docs/user-guide/messaging/<platform>/` — fetch before answering setup/limitation questions.

## Per-platform notes

| Platform | key | Notes |
|---|---|---|
| Weixin (personal WeChat) | `weixin` | iLink bot identity; **DM-only — cannot join ordinary WeChat groups, and third parties cannot add the bot as a friend** (it's an assistant attached to the logged-in account, not an independent searchable WeChat account; no QR to share). See `references/weixin-ilink.md`. |
| QQ Bot | `qqbot` | Official QQ Bot API v2 (WebSocket, no public IP). **Group @-mentions ✅, C2C DM ✅, guild ✅** — the go-to channel when users need WeChat-style group chat. Config: `QQ_APP_ID`/`QQ_CLIENT_SECRET` in `.env`; adapter at `gateway/platforms/qqbot/`; docs `website/docs/user-guide/messaging/qqbot.md`. Full recipe: `references/qq-bot-setup.md`. |
| WeCom (Enterprise WeChat) | `wecom` | Smart Robot over WebSocket + callback mode for self-built apps. |

## Provider auth failures ("供应商认证失败 / check configured credentials")

The channel is healthy — the **LLM provider credential** is being rejected. Diagnosis order:

1. **Confirm channel health first**: `hermes gateway status`, then grep agent.log for `✓ <platform> connected` + recent inbound/outbound lines. If the channel connects and delivers, the failure is upstream of the platform.
2. **Find the smoking gun** in `~/.hermes/logs/agent.log`:
   - `401 Invalid Authentication` / `openai.AuthenticationError`
   - `credential pool: marking <ENV_KEY> exhausted (status=401), rotating` then `no available entries (all exhausted or empty)`
   - Quota is a different beast: 403 `usage limit for this billing cycle` — a *valid* key can still be out of quota.
3. **Test provider keys directly** (never print the key — report presence/length, HTTP code, and error body only):
   ```bash
   v=$(grep -E "^<PROVIDER>_API_KEY=" ~/.hermes/.env | cut -d= -f2-)
   curl -s -o /tmp/k.json -w "HTTP %{http_code}\n" --max-time 15 \
     -H "Authorization: Bearer $v" https://<provider-base>/v1/models && head -c 300 /tmp/k.json
   ```
   401 = key invalid/revoked; 403 = quota; 200 = key is fine (look elsewhere).
4. **Fix**:
   - Key invalid → regenerate at the provider console, update `~/.hermes/.env`, then clear the credential pool's exhaustion state (`hermes auth reset <provider>`, see `hermes auth --help`) or restart the gateway.
   - Prefer switching provider → `hermes config set model.provider <p>` + `hermes config set model.default <m>` (CLI only — never hand-edit config.yaml). Restart the gateway, re-verify `✓ <platform> connected`, then end-to-end test.
5. **Gateway channels use config.yaml `model.*` defaults** — per-chat model/provider overrides in the desktop app do NOT change what gateway channels use.

## Delivery testing & pairing

- **Outbound end-to-end test** (no agent loop): `hermes send -t <platform>:<chat_id> "message"` — chat_id from log lines (`chat=...`) or the platform's `*_HOME_CHANNEL` env var (weixin format: `weixin:o9c...@im.wechat`).
- **Pairing / DM access**: `hermes pairing list` (pending + approved), `hermes pairing approve <platform> <request-id|code>`, `hermes pairing revoke <platform> <user-id>`, `hermes pairing clear-pending`. If `list` already shows the sender approved, that explains why messages flow — no action needed.

## Multi-channel coexistence & per-channel persona

- **One gateway, many channels**: the gateway is a single process that runs ALL enabled platforms concurrently. Adding a new platform (e.g. QQ Bot) does NOT disable existing ones (e.g. Weixin) — each keeps its own independent send/receive. After adding a platform, restart the gateway once to load it; existing channels auto-reconnect.
- **Per-channel persona (`channel_prompts`)**: Hermes supports per-chat/group system prompts via `channel_prompts` (top-level config, keyed by chat/group ID — also `channel_overrides`). Verified in `gateway/run.py` (`_get_system_prompt_for_channel`) and docs (telegram.md/slack.md/discord.md). Use for "one brain, two personas": e.g. WeChat DM = default assistant, QQ study group = tutoring persona. Numeric YAML keys normalize to strings; topic-level overrides group-level.
- **QQ group chat needs the group ID + `group_policy`**: set `platforms.qqbot.extra.group_policy: open` (or allowlist) and `group_allow_from` in config.yaml; bot must be @-mentioned in groups. Group ID appears in gateway logs after first group message.

## Pitfalls

- **Transient poll errors are normal**: `[Weixin] poll error (n/3): Server disconnected` auto-retries with backoff. Only investigate when continuous; then check reachability of the platform API host (e.g. `ilinkai.weixin.qq.com:443`).
- **QR login needs phone confirmation**: scanning alone is not enough — the user must tap confirm on the phone within ~30s or the code times out and regenerates.
- **DM access policies gate first contact**: `pairing` policy blocks unknown senders until approved (`hermes pairing approve` / dashboard). "Messages never trigger" is often an unpaired sender.
- **Don't print .env secrets** — report SET/empty + length only.
- **Group messages may be impossible**: platform-side limitation (e.g. iLink bot can't join ordinary WeChat groups, can't be friend-added by third parties) — not a config bug; don't burn time "fixing" it. Pivot to a group-capable channel (QQ Bot, Feishu, DingTalk, Telegram) when group chat is a hard requirement. WeChat-only users who ask for group automation should be told plainly: no official-API product (Hermes, CowAgent, etc.) can do personal-WeChat group bots — it's a WeChat platform restriction, not a product gap.
- **QQ bot quick-disconnect**: usually invalid AppID/Secret, missing intents, or sandbox-only bot (sandbox bots only talk to the QQ sandbox test channel). Verify at q.qq.com before debugging the adapter.
- **Cross-channel session isolation (the "I already sent it" trap)**: WeChat, QQ, and desktop are **independent gateway sessions** — a credential/ID/instruction the user sends on one channel is NOT visible on another. If the user insists they already sent something you never saw, it likely went to a different channel (ask which, or read it from a screenshot); only config (credentials, skills, `channel_prompts`, memory) is global, chat history is per-channel. Real case: user posted AppID in QQ and AppSecret in WeChat — each half was visible only on its own channel. See `references/qq-bot-setup.md`.
- **`hermes gateway restart` may hang past 120s and leave the gateway stopped**: the restart supervisor gets killed with the agent; `hermes gateway status` then reports "not running". Fallback: start `hermes gateway run` in background (Hermes tracks it), then verify status + per-channel `✓ connected` log lines.
- **Killing the gateway leaves a zombie**: `hermes gateway restart` runs as a single supervisor process; after `kill` it lingers as `<defunct>` (STAT Z) that still shows in `ps -p`. Verify death with `ps aux | grep hermes_cli.*gateway` (empty = gone), then start `hermes gateway run` in background (Hermes tracks it).
- **Desktop model ≠ gateway model**: per-chat model/provider overrides in the desktop app don't affect gateway channels — they use config.yaml `model.*` defaults. A channel replying with a credential error while the desktop chat works fine points at the *gateway's* provider config/keys.

## Reference files
- `references/weixin-ilink.md` — Weixin/iLink setup, env vars, log signatures, limitations, verified-example diagnostics.
- `references/provider-auth-diagnostics.md` — provider-credential auth failure: smoking-gun log lines, masked key testing, provider switch + gateway restart recipe (verified session).
- `references/qq-bot-setup.md` — QQ Bot (official API v2): capability matrix, q.qq.com registration, Hermes config, env vars, message limits, troubleshooting.
