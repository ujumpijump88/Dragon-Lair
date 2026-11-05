# Multi-Profile Gateway & Per-Chat Personas

How to run several Hermes profiles behind ONE gateway, route shared-bot chats to another
profile, and give a single chat its own persona. Applies to every messaging platform; QQ-bot
specifics included because its ids and persona mechanics differ from the rest.

## Topology: one gateway per host
- The supported topology is the default profile's gateway serving every live profile
  (`gateway.multiplex_profiles: true`, the default). Per-profile gateways are retired.
- Converge an old host: `hermes gateway migrate --multiplex --dry-run` (prints plan +
  blockers, changes nothing), then `hermes gateway migrate --multiplex -y`. Safe to re-run;
  there is no rollback command.
- Verify:
  - `hermes gateway list` → every profile shows "served by the default multiplexer".
  - `~/.hermes/gateway_state.json` → `served_profiles` lists all profiles;
    `multiplex_standalone_reason` is null.
  - `hermes gateway status` shows no "STANDALONE: it serves only its own profile" warning.
  - `grep '\[MULTIPLEX\]' ~/.hermes/logs/gateway.log` for each served profile's adapter
    decisions (skipped platforms, parked duplicates, reconnects).

## Duplicate bot credentials (the STANDALONE warning)
- One bot token = one poller. Two profiles holding the same credential → one adapter is
  parked and the gateway warns that the other profile's bot stays silent.
- Fix (the documented default): keep the token in the profile that should own the bot
  (usually `default`), remove it from the other profile's `.env` — back it up first, then
  filter: `grep -v -E '^(QQ_APP_ID|QQ_CLIENT_SECRET|WEIXIN_TOKEN)=' .env > tmp && mv tmp .env`
  — add `gateway.profile_routes` for the other profile's chats, then run
  `hermes gateway migrate --multiplex`. The duplicate-token preflight passes only after the
  credential removal.

## profile_routes — route specific chats to another profile
In the DEFAULT profile's config:
```yaml
gateway:
  profile_routes:
    - name: qq-study-group
      platform: qqbot              # adapter platform value
      chat_id: "<group openid>"    # exact id; also user_id / thread_id / guild_id
      profile: tutor_bot           # target must exist and be served
```
- Specificity wins additively (`user_id` > `thread_id` > `chat_id` > `guild_id`); all declared
  fields must hold (AND); unmatched traffic stays on the default profile.
- A route applies to inbound received by the DEFAULT profile's bot unless it names another
  bot with `bot_profile: <profile>`. The routed profile needs no credential of its own —
  replies and background notifications go out through the shared bot.
- Routes are ignored when `gateway.multiplex_profiles` is off.
- Verify without sending a message — use the install's venv python (it has yaml):
  ```python
  from gateway.profile_routing import parse_profile_routes, match_profile_route
  routes = parse_profile_routes(cfg["gateway"]["profile_routes"])  # dicts → ProfileRoute objects
  match_profile_route(routes, platform="qqbot", guild_id=None, chat_id="<id>",
                      thread_id=None, parent_chat_id=None, adapter_profile=None, user_id=None)
  ```
  Pitfall: `match_profile_route` needs `ProfileRoute` objects — raw dicts from config raise
  `AttributeError: 'dict' object has no attribute 'matches'`. Always run them through
  `parse_profile_routes` first.

## Per-chat personas: `channel_overrides`, NOT `channel_prompts`
The mechanism that applies on EVERY platform is the per-channel override:
```yaml
platforms:
  qqbot:
    channel_overrides:
      "<chat_id>":
        system_prompt: "..."
        # optional: model, provider
```
- Pitfall: legacy `platforms.<p>.channel_prompts` is only read by adapters that call
  `resolve_channel_prompt` (telegram/discord/feishu/mattermost/slack). The **qqbot adapter
  never reads it** — a group persona configured there silently does nothing. Before trusting
  `channel_prompts` on any platform, grep that adapter for `channel_prompt`.
- Write the override in the profile that SERVES the chat (the routed profile) and mirror it
  in `default`'s config — cheap insurance for whichever config path the run resolves it from.
- `hermes config set` parses structured values as YAML/JSON. For long multi-line text, build
  `{"system_prompt": "..."}` with python `json.dumps` into a temp file, then pass it as one
  argument: `hermes config set 'platforms.qqbot.channel_overrides.<id>' "$(cat file)"`
  (single-line JSON survives quoting; check the text contains no ASCII single quote).
  Verify with `hermes config get platforms.qqbot.channel_overrides`.
- Finding the chat id: platform-native, not human-readable. QQ example: group openid and user
  openid are DIFFERENT 32-hex strings — never use the numeric group number. Sources:
  `~/.hermes/sessions/sessions.json` keys
  (`agent:main:qqbot:group:<group_openid>:<member_openid>`) and gateway.log inbound lines
  (`chat=...`).

## Routed-only profiles: disable their platform blocks
- A served profile whose platform block is `enabled: true` but has no usable credential makes
  the multiplexer build a secondary adapter and reconnect it with backoff indefinitely.
  Token platforms (telegram/discord/slack/mattermost/matrix/weixin) are skipped cleanly, but
  other platforms are not credential-gated: `_platform_has_bot_credential` returns True for
  any platform outside `PLATFORM_TOKEN_ENV_NAMES` (qqbot among them), so an enabled empty
  qqbot block retries forever ("Secondary qqbot reconnect retry in Ns").
- Fix: `hermes -p <profile> config set platforms.<platform>.enabled false` (repeat per
  platform the profile should not poll). The reconnect loop re-reads the profile config on
  each attempt and gives up silently once disabled; the running multiplexer also re-scans
  served profiles after config/.env changes, so no gateway restart is needed.
- Keep the platform block itself (with its `channel_overrides`) — `enabled: false` does not
  affect persona resolution for routed chats.

## An invalid platform block in ANY profile aborts the whole multiplexer
- Some platform policies are validated when the multiplexer builds its profile set, not per
  adapter: a served profile whose `qqbot` block keeps `group_policy: open` without an allow-all
  opt-in makes the process log `Gateway multiplexer config error: Profile '<p>' enables qqbot:
  open policy without allow-all opt-in` and **exit cleanly** — every profile's bot, including the
  default's, goes down with it.
- The container still shows `Up` (s6 keeps the dashboard alive) and `docker ps` looks healthy, so
  diagnose from `docker logs`, never from container state.
- Fix for a profile that serves no chats of its own: `hermes -p <profile> config set
  platforms.<platform>.enabled false`, or `hermes -p <profile> config unset platforms.<platform>`
  to drop the block entirely. Keep the persona text elsewhere first if you still need it.
- Do this BEFORE the first start of a migrated/second gateway: a copied data dir carries the old
  host's platform blocks, and the abort only shows up at boot.

## Applying & verifying changes
- `hermes gateway migrate --multiplex` restarts the default gateway onto the new config
  (drains in-flight turns first; bots reconnect within seconds).
- Afterward check: `hermes gateway list`, `gateway_state.json`, and gateway.log for
  `[MULTIPLEX]` lines / absence of `Secondary ... reconnect retry` lines.
