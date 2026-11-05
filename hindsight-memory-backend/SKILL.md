---
name: hindsight-memory-backend
description: "Set up and operate Hindsight local memory (hindsight-embed)."
---

# Hindsight Local Memory Backend

Hindsight (vectorize-io/hindsight) = biomimetic memory for AI agents (retain/recall/reflect). Local mode = `hindsight-embed` CLI: an auto-managed daemon on localhost:8888 with embedded PostgreSQL; needs an LLM key (facts/entities/embeddings are extracted by an LLM pipeline). The product's own skills (hindsight-docs/local/architect/cloud/self-hosted) are installed from the repo as user-owned skills — this skill covers OPERATING the backend.

## Setup (validated)

1. CLI: `uvx hindsight-embed --help` (uvx = no pip install needed).
2. Configure the **default profile** — the only reliable non-interactive way:
   ```bash
   export HINDSIGHT_API_LLM_PROVIDER=openai
   export HINDSIGHT_API_LLM_API_KEY=<key>
   export HINDSIGHT_API_LLM_BASE_URL=https://api.deepseek.com/v1
   export HINDSIGHT_API_LLM_MODEL=deepseek-v4-flash
   uvx hindsight-embed configure   # no --profile → default profile; API_KEY env present → non-interactive
   ```
   Any OpenAI-compatible endpoint works (DeepSeek verified: provider=openai + base_url). Verify: `uvx hindsight-embed profile list` → `default ✓ active  Port: 8888`.
3. Start daemon: `uvx hindsight-embed daemon start`. FIRST RUN downloads the whole hindsight-api runtime into the uv cache (torch ~106MB, mlx-metal, litellm, claude-agent-sdk, transformers, pg0-embedded …) — see China-network section below.

## Pitfalls / quirks

- `hindsight-embed profile create default` FAILS: "Profile name cannot be empty" — the CLI normalizes "default" → "" and create rejects empty. "default" is the implicit profile stored at `~/.hindsight/embed`. `profile set-env default` also fails ("Profile 'default' does not exist") before the profile exists. **Use `configure` without `--profile`** — despite --help labelling it deprecated, `profile create` cannot express the default profile.
- `profile create <name>` requires `--port` (required arg).
- Bank id `default` in `memory retain default "<text>"` is the MEMORY BANK, not the profile — don't confuse the two.
- Status/logs: `uvx hindsight-embed daemon status`; `~/.hindsight/daemon.log` (uvx download progress lands here too).
- 401s in the daemon log → LLM key rejected; the daemon marks the key exhausted.

## China network / flaky downloads (validated)

- **TUNA mirror 403s uv**: `https://pypi.tuna.tsinghua.edu.cn/simple` returns 403 Forbidden to uv's client — do NOT use it for uv.
- **Aliyun works**: `export UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ UV_DEFAULT_INDEX=https://mirrors.aliyun.com/pypi/simple/` — these propagate to the daemon's uvx subprocess (it copies os.environ, confirmed in daemon_embed_manager.py).
- Big wheels drop TLS mid-download on unstable links ("peer closed connection without sending TLS close_notify"). uv's cache is content-addressed, so completed wheels persist across attempts; a retry loop converges:
  ```bash
  export UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ UV_DEFAULT_INDEX=https://mirrors.aliyun.com/pypi/simple/
  for i in $(seq 1 20); do uvx hindsight-api@0.8.6 --help && break; sleep 5; done
  uvx hindsight-embed daemon start
  ```
  (Pre-warming `uvx hindsight-api@<version>` populates the same tool environment the daemon reuses.) On a flaky network the first full start may need several cycles — do not assume the start failed permanently after one timeout.

## macOS system proxy vs httpx (CRITICAL — the "daemon not running" phantom)

On machines with a Clash-type proxy set at the macOS SYSTEM level (e.g. 127.0.0.1:7897), httpx reads it via urllib/SystemConfiguration **even when `env` shows no proxy variables**. Localhost requests then route through the proxy and `ReadTimeout`. Symptoms: `daemon status` says "not running" while `curl http://127.0.0.1:8888/health` returns 200 `{"status":"healthy","database":"connected"}`; every `memory ...` command kill/restarts the healthy daemon (port PID keeps changing) and eventually "Failed to start daemon". curl/requests/raw sockets/aiohttp are NOT affected — the curl-OK-but-httpx-timeout discrepancy is the diagnostic clue.

Fix (required for ALL hindsight-embed commands on such machines):
```bash
export NO_PROXY="127.0.0.1,localhost"   # also export lowercase no_proxy; persist in ~/.zshrc
```
Diagnose with: `python -c "import httpx._utils as u; print(u.get_environment_proxies())"` — shows the phantom proxy.

## daemon start readiness false-negative

`daemon start` waits up to 180s on a readiness probe that can report "✗ Daemon failed to start (timeout)" while the daemon is actually healthy and listening. **Trust `curl /health`, not the CLI verdict.** The daemon also auto-exits after ~5 min idle; the CLI restarts it on demand.

## Use (verified end-to-end)

```bash
uvx hindsight-embed memory retain default "<rich full-context text>" --context preferences|learnings|procedures
uvx hindsight-embed memory recall default "query"
uvx hindsight-embed memory reflect default "query"
```
Pass RICH context — the server extracts facts/entities itself; pre-summarizing loses value. Success looks like: `Memory retained successfully (document: cli_put_...)` / recall returning `[WORLD]`/`[EXPERIENCE]` entries.

## References

- references/china-network-downloads.md — GitHub access & rate limits (raw vs API vs git), gh CLI install without Homebrew, `hermes skills install` fallback via git clone + copy, proxy/mirror summary
