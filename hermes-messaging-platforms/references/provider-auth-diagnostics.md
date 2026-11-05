# Provider credential auth-failure diagnostics (verified session)

## Scenario
Weixin channel healthy (`✓ weixin connected`, inbound/outbound flowing) but the user-facing reply was
「供应商认证失败。检查已配置的凭证」— an **LLM provider auth error**, not a channel error.

## Smoking-gun log lines (`~/.hermes/logs/agent.log`)
```
ERROR agent.chat_completion_helpers: Streaming failed before delivery: Error code: 401 - {'error': {'message': 'Invalid Authentication', 'type': 'invalid_authentication_error'}}
INFO  agent.credential_pool: credential pool: marking KIMI_CN_API_KEY exhausted (status=401), rotating
INFO  agent.credential_pool: credential pool: no available entries (all exhausted or empty)
WARNING agent.conversation_loop: API call failed (attempt 1/3) error_type=AuthenticationError provider=kimi-coding-cn base_url=https://api.moonshot.cn/v1 model=kimi-k2.7-code
```
Also possible: 403 `usage limit for this billing cycle` on a fallback model — account quota exhausted, distinct from key validity.

Note the `provider=... base_url=... model=...` on the failing call — that tells you WHICH key to inspect.

## Masked key test
Presence/length first, then curl (print HTTP code + error body only — never the key):
```bash
CN=$(grep -E "^KIMI_CN_API_KEY=" ~/.hermes/.env | cut -d= -f2-)
curl -s -o /tmp/k.json -w "HTTP %{http_code}\n" --max-time 15 -H "Authorization: Bearer $CN" https://api.moonshot.cn/v1/models && head -c 300 /tmp/k.json
```
Observed: 401 on BOTH api.moonshot.cn and api.moonshot.ai for BOTH stored Kimi keys → keys revoked/expired, not a network issue.
Contrast check: a good key returns HTTP 200 with the model list (e.g. api.deepseek.com/v1/models → `deepseek-v4-flash`, `deepseek-v4-pro`).

## Fix applied (switch provider to a verified-good key)
```bash
hermes config set model.provider deepseek
hermes config set model.default deepseek-v4-flash

# stop old gateway supervisor: kill <pid>, verify death with
ps aux | grep hermes_cli.*gateway     # empty = gone (ps -p still shows the zombie <defunct>)

hermes gateway run                    # background; Hermes tracks it
hermes gateway status                 # expect "Gateway is running (PID ...)"
grep -E "weixin" ~/.hermes/logs/agent.log | tail   # expect ✓ weixin connected, no 401

hermes send -t "weixin:<chat_id>" "test message"   # outbound end-to-end, no agent loop
```
`hermes send -t <platform>:<chat_id>` — chat_id from log `chat=...` lines or the platform's `*_HOME_CHANNEL` env var.

## Lessons
- A platform's "connected" log + real inbound/outbound message lines prove the channel; a credential-style reply means the failure is upstream (provider key / quota).
- The credential pool marks a key exhausted on 401 and won't retry it until reset or gateway restart — after fixing a key run `hermes auth reset <provider>` (or restart).
- Gateway channels use config.yaml `model.*` defaults; desktop per-chat overrides don't affect them. Desktop working + gateway failing = inspect the gateway's provider keys.
- Transient `[Weixin] poll error (n/3): Server disconnected` (network flakiness to ilinkai.weixin.qq.com) can coexist with all of the above — don't confuse it with auth failures; it auto-retries.
