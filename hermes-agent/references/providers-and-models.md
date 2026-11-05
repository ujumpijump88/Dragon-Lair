# Providers & Model Aliases

Set via `hermes model` (picker) or `hermes setup`. 35+ provider profiles ship as
plugins under `plugins/model-providers/`; user plugins of the same name override.
Full docs: https://hermes-agent.nousresearch.com/docs/integrations/providers

### Providers

| Provider | Auth | Key env var(s) |
|----------|------|----------------|
| openrouter | API key | `OPENROUTER_API_KEY` |
| anthropic | API key | `ANTHROPIC_API_KEY` (also `CLAUDE_CODE_OAUTH_TOKEN`) |
| nous | OAuth device code | `hermes auth add nous` (or `NOUS_API_KEY`) |
| openai-codex | OAuth | `hermes auth add openai-codex` |
| qwen-oauth | OAuth | `hermes auth add qwen-oauth` |
| minimax-oauth | OAuth | `hermes auth add minimax-oauth` |
| copilot | Token | `COPILOT_GITHUB_TOKEN` / `GH_TOKEN` (Copilot device flow — `gh auth login` tokens do NOT work) |
| copilot-acp | External CLI | Copilot CLI on PATH or `COPILOT_CLI_PATH` |
| gemini | API key | `GOOGLE_API_KEY` or `GEMINI_API_KEY` |
| xai | API key | `XAI_API_KEY` (SuperGrok OAuth also supported) |
| deepseek | API key | `DEEPSEEK_API_KEY` |
| zai (GLM) | API key | `GLM_API_KEY` / `ZAI_API_KEY` |
| minimax / minimax-cn | API key | `MINIMAX_API_KEY` / `MINIMAX_CN_API_KEY` |
| kimi-coding / -cn | API key | `KIMI_API_KEY` / `KIMI_CN_API_KEY` |
| alibaba (+coding-plan) | API key | `DASHSCOPE_API_KEY` / `ALIBABA_CODING_PLAN_API_KEY` |
| xiaomi | API key | `XIAOMI_API_KEY` |
| huggingface | Token | `HF_TOKEN` |
| fireworks / novita / nvidia / deepinfra / gmi / arcee / stepfun / upstage / kilocode / ai-gateway / opencode-zen / opencode-go / ollama-cloud | API key | `<NAME>_API_KEY` |
| bedrock / vertex / azure-foundry | Cloud SDK / key | AWS SDK creds / Vertex ADC / `AZURE_FOUNDRY_API_KEY` |
| custom | Config | `model.base_url` + `model.api_key` in config.yaml |

Multiple credentials per provider pool and rotate automatically (`hermes auth`).
Fallback chain when the primary fails: `hermes fallback add|remove|list`.

### User-defined model aliases

Work with `/model <name>` in CLI and every gateway platform. Resolved by
`hermes_cli/model_switch.py::resolve_alias()`; user aliases are checked BEFORE
the built-in table, so a user `sonnet`/`grok` shadows the built-in.

```yaml
# Full form
model_aliases:
  fav:
    model: claude-sonnet-4.6
    provider: anthropic
  local-qwen:
    model: qwen3.5:397b
    provider: custom
    base_url: "https://ollama.com/v1"

# Short form ("provider/model"), also via CLI:
#   hermes config set model.aliases.fav openrouter/anthropic/claude-sonnet-4.6
model:
  aliases:
    fav: openrouter/anthropic/claude-sonnet-4.6
```

`/model fav` — session-scoped; add `--global` to persist as default.

Built-in aliases (catalog-resolved against the active provider): `sonnet`,
`opus`, `haiku`, `claude`, `gpt5`, `gpt`, `codex`, `o3`, `o4`, `gemini`,
`deepseek`, `grok`, `llama`, `qwen`, `minimax`, `nemotron`, `kimi`, `glm`,
`step`, `mimo`, `trinity`.

### "<Provider> is not connected" — diagnose before re-adding credentials

Work in this order; do not start a device flow until you know which provider is
dead and how many subsystems point at it.

1. `hermes auth list` — per-provider credential pools, with inline
   `auth failed … (401) (re-auth may be required)` flags. A provider listed with
   `0` credentials has no key and no OAuth token.
2. `hermes auth status <provider>` — the only supported health check. It
   **requires** the provider argument; bare `hermes auth status` exits with a
   usage error. Never health-check by calling the OAuth token endpoint yourself
   (kills the session — see below).
3. Read `$HERMES_HOME/auth.json`: `active_provider`, `credential_pool.<provider>`
   (empty list = dead), and `providers.<provider>.last_auth_error` — read `code`,
   `reason`, `relogin_required`. `invalid_grant` + `relogin_required: true` means
   only a fresh login fixes it.
4. Grep `config.yaml` for the dead provider id. One dead provider is usually
   wired into several subsystems: `model.provider`, `image_gen.provider`,
   `auxiliary.*`, and the `fallback_providers` / `fallback_model` chain. A live
   session already running on a different provider keeps working, so "chat still
   answers" does not mean the config is healthy — the error surfaces the first
   time any other subsystem (image gen, aux model, a new session) resolves the
   dead provider.
5. Offer both routes explicitly: re-login (keeps the intended provider, restores
   Tool Gateway / image gen) or repoint defaults to an already-connected provider
   (`hermes config set model.provider <p>` + `model.default <model>`, then check
   `image_gen.provider`). Never hand-edit `config.yaml`.

### OAuth device-code login (Nous Portal, Codex, Qwen, MiniMax)

Device codes expire in minutes and the CLI only polls — never run the login
silently in the foreground and wait.

```bash
# background + pty, output to a log you can poll
terminal(background=true, pty=true,
         command="hermes auth add nous --no-browser > $SCRATCH/nous_login.log 2>&1")
# then read the log for user_code + verification_uri_complete, immediately
# `open` that URL in the user's browser and post the code to them
open "https://portal.nousresearch.com/manage-subscription?user_code=XXXX-XXXX"
```

Poll the log for success/expiry, then confirm with `hermes auth status <provider>`.
If the code expires before the user acts, restart the login rather than reusing it.
`--browser` / `--no-browser` control auto-opening; pass `--no-browser` when you
intend to `open` the URL yourself so two tabs don't race.

### Pitfalls

- **`invalid_grant` / "refresh-token reuse and revoked this session"** — Nous
  refresh tokens are single-use: any second caller of `/api/oauth/token` (a
  monitoring script, a self-heal hook, another install sharing `auth.json`, or an
  agent manually testing the token endpoint) rotates the token without
  persisting it and Portal revokes the whole session. Re-auth is the only fix;
  use `hermes auth status <provider>` for health checks and keep `auth.json`
  per-install.
- **First attempt dies with `httpx.ConnectTimeout` on the TLS handshake while
  `curl` reaches the same URL** — that is transient (VPN/proxy flapping), not a
  dead endpoint. Probe the exact call with the install's own interpreter before
  troubleshooting network config:
  `VENV=$(ls -d ~/.hermes/installs/*/environments/*/venv | head -1); $VENV/bin/python -c "import httpx; print(httpx.post('https://portal.nousresearch.com/api/oauth/device/code', data={'client_id':'hermes-cli'}, timeout=15).status_code)"`
  then simply retry the login once. Do not conclude the provider or the network
  is down from a single handshake timeout.
- A direct-connection portal call succeeds whether or not a local proxy
  (Clash/mihomo) is running; only loopback-backed services need `NO_PROXY`.
