# Channel Context Isolation & Home Channel (verified 2026-08)

Two lessons from running a QQ Bot study-group channel (students = third parties) alongside the owner's WeChat/desktop channels.

## 1. Context isolation is MANDATORY for channels serving third parties

**The leak**: Hermes injects GLOBAL memory + user profile into EVERY channel session. A bot channel that serves outsiders (student groups, customers, strangers) will casually mention the owner's private/work life — because that context is in its system prompt. This is a privacy leak visible to people who are NOT the user.

**Real case**: tutor bot in a student QQ group replied "倒是你…有食堂排菜要调整随时丢给我" — the owner's canteen-management job (stored in memory/user profile) leaked into the group.

**Fix**: append a highest-priority isolation block to that group's `channel_prompts`:
```yaml
qqbot:
  channel_prompts:
    "<group_openid>": |
      ...teaching persona...
      【上下文隔离（最高优先级）】
      - 你只服务于本群的教学任务。
      - 禁止提及/暗示/回应与学习无关的个人信息：群主的工作、其他聊天软件中的对话、私人生活、项目、财务等。
      - 被问这类话题 → 礼貌回"这个问题不属于我的教学范围哦"并拉回学习。
```
Then restart the gateway and **re-test with a fresh message** — the old (leaking) behavior lingers in logs until the new config takes effect; don't judge the fix from pre-restart log lines.

**General rule**: any channel whose audience ≠ the account owner needs an explicit isolation clause in its persona. WeChat DM (owner-only) can keep full context; group channels with students/customers must not.

## 2. Home channel (/sethome) for cron & notification delivery

When a platform bot DMs the user `📬 No home channel is set for <Platform>. Type /sethome to make this chat your home channel...`:

- **Fix**: send `/sethome` **in the private chat** that should receive cron job results / cross-platform messages.
- **What it does**: home channel = where scheduled deliveries land (cron results, cross-platform forwards).
- **Optional**: without it, interactive chat (group tutoring, DMs) works fine — only scheduled/cron deliveries have no destination.
- **Prefer the owner's private chat, NOT a shared group**: scheduled summaries (e.g. weekly 错题复盘) should go to the owner personally, not spam the student group.
- Equivalent config: `QQBOT_HOME_CHANNEL=<openid>` in `.env` (or `*_HOME_CHANNEL` per platform).

## Related
- `qq-bot-setup.md` — full QQ Bot setup recipe, capability matrix, `group_policy` pitfalls, channel_prompts keyed by group OpenID.
