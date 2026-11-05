# QQ Bot (Official API v2) — Setup & Capability Facts

Verified 2026-08 against Hermes source (`~/.hermes/hermes-agent/gateway/platforms/qqbot/`, `website/docs/user-guide/messaging/qqbot.md`) and CowAgent docs (`docs.cowagent.ai/channels/qq.md`, `channels/index.md`). Hermes ships a native QQ Bot adapter — no bridge needed.

## Why QQ Bot matters (capability matrix facts)

| Channel | Text | Image | File | Voice | Group Chat |
|---|---|---|---|---|---|
| WeChat (personal, iLink/ClawBot) | ✅ | ✅ | ✅ | ✅ | ❌ (no API) |
| **QQ Bot** | ✅ | ✅ | ✅ | ✅ | ✅ (@-mention) |
| Feishu / DingTalk / WeCom Bot / Telegram / Discord / Slack / QQ | — | — | — | — | ✅ |

Personal WeChat's official API has NO group-chat interface at all — every product (Hermes, CowAgent, chatgpt-on-wechat) hits the same wall. QQ Bot is the low-friction replacement for Chinese users (everyone has QQ). QQ Bot also supports guild channels + guild DMs; no public IP needed (WebSocket long connection).

## Prerequisites (user does this at q.qq.com — ~10 min)

1. Visit **q.qq.com**, sign in with QQ. First-time users must complete **developer registration** (real-name verification: ID + SMS; individuals OK, free).
2. 应用管理 → 创建应用 → choose **机器人 (Bot)** type. Fill name/avatar/description.
3. 开发管理 page: copy **AppID**; click generate → copy **AppSecret** ⚠️ AppSecret is shown ONCE — warn the user to save it immediately.
4. Enable intents: C2C messages, Group @-messages, Guild messages (QQ open platform subscribes `GROUP_AND_C2C_EVENT` + `PUBLIC_GUILD_MESSAGES` by default).
5. Sandbox mode first for testing (`QQ_PORTAL_HOST=sandbox.q.qq.com`); publish for production.
6. 应用管理 → 使用范围与成员: scan the QR with QQ client to add the bot to groups / start DMs.

## Hermes configuration

`~/.hermes/.env`:
```
QQ_APP_ID=your-app-id
QQ_CLIENT_SECRET=your-app-secret
```
`~/.hermes/config.yaml`:
```yaml
platforms:
  qqbot:
    enabled: true
    extra:
      markdown_support: true
      group_policy: "open"        # open | allowlist | disabled | pairing(default!)
      group_allow_from: []        # group OpenIDs
      dm_policy: "open"           # open | allowlist | disabled
```
⚠️ **`group_policy: "open"` requires an allow-all opt-in**: the gateway refuses to start with `Refusing to start: qqbot has dm_policy/group_policy set to 'open' but neither GATEWAY_ALLOW_ALL_USERS nor QQ_ALLOW_ALL_USERS is enabled` unless `QQ_ALLOW_ALL_USERS=true` is in `.env` (verified 2026-08). Add it whenever you set `open`.

⚠️ **Default `group_policy` is `pairing`, which SILENTLY drops every group @-message** — adapter code: `extra.get("group_policy", "pairing")`, and `_is_group_allowed` returns False for `pairing`. Symptom: bot connects fine (C2C DMs work) but group @-messages never appear in logs, no error. Fix: set `group_policy: "open"` (or `allowlist` + `group_allow_from`) + the opt-in above, restart, retest.

⚠️ **`channel_prompts` keys are the group OpenID, NOT the visible QQ group number** — the adapter uses `group_openid` as `chat_id` (`_handle_group_message`), so a key like `"1094250278"` (the human-facing group number) never matches. Capture the real OpenID from gateway logs after the first group @-message, then bind.

Restart gateway (`hermes gateway restart`); existing platforms (e.g. weixin) reconnect automatically — multi-channel coexistence is by design. If `hermes gateway restart` hangs >120s and the gateway ends up stopped, fall back to `hermes gateway run` in background and verify per-channel `✓ connected` log lines.

## Env vars
| Var | Purpose | Default |
|---|---|---|
| `QQ_APP_ID` / `QQ_CLIENT_SECRET` | Bot credentials (required) | — |
| `QQBOT_HOME_CHANNEL` | OpenID for cron/notification delivery | — |
| `QQ_ALLOWED_USERS` / `QQ_ALLOW_ALL_USERS` | DM access control | open / false |
| `QQ_GROUP_ALLOWED_USERS` | Group access allowlist | — |
| `QQ_PORTAL_HOST` | `sandbox.q.qq.com` for sandbox routing | `q.qq.com` |
| `QQ_STT_*` | Voice transcription (Zhipu glm-asr default, or OpenAI-compatible) | glm-asr |

## Usage & limits (official API)

- Group chat: bot must be **@-mentioned**; replies valid **5 minutes**.
- Direct messages: replies valid 60 min, max 5 replies per message.
- **Active push: 4 per user per month** (DM + group) — plan scheduled tasks accordingly.
- Web console alternative: `hermes gateway setup` → select QQ Bot.

## Verification
- Log signature on connect: `[QQ] ✅ Connected successfully` (CowAgent) — for Hermes, `hermes gateway status` and grep agent.log for the qqbot adapter lines. Hermes success sequence: `[QQBot:<AppID>] Access token refreshed` → `WebSocket connected to wss://api.sgroup.qq.com/websocket` → `✓ qqbot connected` → `[QQBot:<AppID>] Ready, session_id=...`.
- Group ID for `channel_prompts` / allowlist: appears in gateway logs after the first group @-message.

## Cross-channel session isolation (verified gotcha, 2026-08)
WeChat, QQ, and desktop are **independent gateway sessions**. A credential/ID sent on one channel is invisible on the others. Real case: a user setting up this exact QQ Bot channel posted **AppID in the QQ chat** (another bot session replied) and **AppSecret in WeChat** — the agent in WeChat only ever saw the AppSecret, causing "I already sent it" confusion. Diagnose by asking which channel the info went to, or reading it from a screenshot. Config (`.env`, config.yaml, `channel_prompts`, memory/skills) is global; per-session chat history is not.

## Tutoring-persona use case (middle-school study group)
One bot handles all subjects; per-group persona via `channel_prompts` (top-level config, keyed by **group OpenID — not the visible QQ group number**; see the ⚠️ note in the config section above):
```yaml
qqbot:
  channel_prompts:
    "<group_openid>": |
      You are a middle-school tutor. Grade first, then explain each mistake
      step-by-step, keep a per-student error notebook by subject, and give a
      similar practice problem. Be encouraging.
```
Pair with a tutoring Skill (grading workflow, error-notebook template) + Memory (student names, weak points, textbook edition) for a full 教学档案. Different subject groups can each get their own style.

### ⚠️ Privacy leak: global memory bleeds into the QQ group (verified fix 2026-08)
Hermes' **global memory/user-profile is injected into EVERY channel session** — including the QQ study group. Real case: the tutor bot casually mentioned the user's canteen-menu work (食堂排菜) in the student group, because the memory about the user's job is global. Students seeing the owner's personal/work info is both confusing and a privacy breach.

**Fix**: add an explicit **context-isolation block** to the group's `channel_prompts`, marked highest priority, that (a) forbids mentioning/implying any non-study personal info about the group owner (job, other chat apps like WeChat, private life, projects), (b) mandates a polite brush-off ("这个不属于教学范围哦，我们继续学习吧") if asked, and (c) says the bot's knowledge is limited to what the group's teaching needs. Verified: after adding this block and restarting, the bot stopped leaking. Always include it for any persona whose audience is not the owner.

### ⚠️ "Students replied but nothing in logs" → they didn't @-mention the bot
QQ only pushes **@-mentioned** group messages to the bot (GROUP_AT_MESSAGE_CREATE intent). If students reply to the bot's question without @-mentioning it, the messages never arrive — no log lines at all, no error. This is the #1 support issue on day one. Tell students explicitly: **every question AND every reply must start with @bot**. Verify via `grep "inbound message: platform=qqbot" ~/.hermes/logs/agent.log`.

## Troubleshooting
- **Quick disconnect** → invalid AppID/Secret, missing intents, or sandbox-only bot talking to non-sandbox channel.
- **No group responses** → bot not @-mentioned, group_policy not open/allowlisted, or bot not added via usage-scope QR.
- **Voice not transcribed** → check `asr_refer_text` in attachment; fallback STT provider needs `QQ_STT_API_KEY`.
- **Frequent `WebSocket error: WebSocket closed` + reconnect (every 20-40 min)** → NORMAL. QQ's gateway kicks the client periodically; the adapter auto-reconnects in ~2s with `Resume sent (session_id=...)`. 35 disconnects over a day with every one self-healing is not a fault — don't chase it. Only investigate if reconnects fail or messages go missing around a disconnect (and even then, the missing-message cause is usually no-@-mention, above).
- **Bot DM says "No home channel is set for Qqbot ... Type /sethome"** → home channel is where cron results / cross-platform messages get delivered. Optional: reply `/sethome` in a private chat with the bot to route scheduled deliveries (e.g. weekly error-notebook digests) to the owner's DM instead of the study group. Not required for group teaching to work.
