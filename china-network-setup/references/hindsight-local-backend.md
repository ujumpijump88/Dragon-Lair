# Hindsight local-memory daemon — bring-up recipe (this machine, 2026-08)

Goal: `hindsight-local` skill backend = `uvx hindsight-embed` CLI + local daemon on
`127.0.0.1:8888` with DeepSeek LLM, local bge-small embeddings, embedded pg0 Postgres.

Final working state (all verified end-to-end: retain + recall via CLI and HTTP API).

## Architecture facts (learned from source, hindsight-embed 1.x / hindsight-api 0.8.6)
- `hindsight-embed` CLI = daemon manager. `daemon start` spawns `uvx hindsight-api@<ver>`.
- The daemon does NOT read `~/.hindsight/embed` itself — the manager loads that config
  file and passes values to the daemon as ENVIRONMENT variables (`os.environ.copy()` +
  profile env). Launching the daemon binary directly requires sourcing the config:
  `set -a; source <(grep -E '^[A-Z_]+=' ~/.hindsight/embed); set +a`
- Default profile config = `~/.hindsight/embed` (named profiles = `~/.hindsight/profiles/<name>.env`).
- `profile create default` FAILS by design ("Profile name cannot be empty"): "default" is
  normalized to "" and the implicit default profile is configured via `configure` (without
  `--profile`) or by editing `~/.hindsight/embed` directly.
- `configure` without `--profile` + `HINDSIGHT_API_LLM_API_KEY` env set → non-interactive.
  BUG: it does NOT persist `HINDSIGHT_API_LLM_BASE_URL` — append manually or the daemon
  hits OpenAI's default endpoint (403 `unsupported_country_region_territory` from CN).
- CLI daemon detection = health check on `get_url(profile)` = `http://127.0.0.1:8888/health`
  (httpx, trust_env=True → reads macOS system proxy → 502 → "Daemon is not running").
  Fix: `NO_PROXY=localhost,127.0.0.1`.
- `daemon start` manager: waits ~178-181s for readiness; on timeout reports failure AND
  kills the (healthy) child. On this machine startup takes ~15s warm but the manager's
  readiness loop can still time out → NEVER rely on `uvx hindsight-embed daemon start`;
  use the direct-start script (see templates/start-hindsight.sh).

## Ordered failure log (each with fix)
1. `uvx hindsight-embed` env build: big wheels (torch 106MB, mlx-metal 54MB, claude-agent-sdk
   75MB) drop TLS on files.pythonhosted.org. → Aliyun mirror + retry loop; converges via uv cache.
2. TUNA mirror: 403 to uv (`An index returned a 403 Forbidden error`) → use Aliyun.
3. `uvx hindsight-api` env: `tokenizers==0.23.1` installed but transformers 5.14.1 runtime
   check requires `<=0.23.0` — and **tokenizers 0.23.0 does not exist on PyPI (404)** (yanked).
   → Patch installed `transformers/dependency_versions_table.py` line to `tokenizers>=0.22.0,<=0.23.1`.
   (LocalSTEmbeddings raises misleading "sentence-transformers is required" when a transitive
   import fails — check the real import error in the tool env python first.)
4. Embedding model BAAI/bge-small-en-v1.5: huggingface.co blocked; hf-mirror.com reachable
   but hf_hub fails with `LocalEntryNotFoundError` on HEAD verification. → Assemble local dir:
   copy cached blobs (`~/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5/blobs/`) for the
   two 133MB weights, curl -C - each small file from `hf-mirror.com/<repo>/resolve/main/<file>`.
5. pg0 embedded PostgreSQL 18.1 fails: libpq hardcodes `/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib`.
   No Homebrew, /opt not writable. → Build OpenSSL 3.6.3 from codeload tarball to `~/openssl3`
   (Configure darwin64-arm64-cc shared no-tests; make -j8 build_sw; make install_sw), then
   install_name_tool -change on all 10 pg0 binaries referencing the homebrew path (postgres,
   pg_dump*, libpq.5.dylib, sslinfo.dylib, pgcrypto.dylib, ...). Verified `postgres --version`.
6. Reranker `cross-encoder/ms-marco-MiniLM-L-6-v2` also needs a download → set
   `HINDSIGHT_API_RERANKER_PROVIDER=rrf` (RRF passthrough, no neural model, no download).
7. DeepSeek 403 `unsupported_country_region_territory` → was missing `HINDSIGHT_API_LLM_BASE_URL`
   (see configure bug above). Set to `https://api.deepseek.com/v1`.
8. `daemon start` manager kills healthy daemon at 181s → direct start (below).
9. CLI "Daemon is not running" + hangs trying to auto-start (litellm sdist re-download loop) →
   NO_PROXY fix (section 4 of SKILL.md) + daemon already running.

## Working config (~/.hindsight/embed active lines)
```
HINDSIGHT_API_LLM_PROVIDER=openai
HINDSIGHT_API_LLM_API_KEY=<deepseek key>
HINDSIGHT_API_LLM_MODEL=deepseek-v4-flash
HINDSIGHT_API_LLM_BASE_URL=https://api.deepseek.com/v1
HINDSIGHT_API_RERANKER_PROVIDER=rrf
HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=/Users/xiebojun/hindsight-models/bge-small-en-v1.5
```

## Direct start (what works)
```
set -a; source <(grep -E '^[A-Z_]+=' ~/.hindsight/embed); set +a
HINDSIGHT_API_DAEMON_LOG=~/.hindsight/daemon.log \
  ~/.local/share/uv/tools/hindsight-api/bin/hindsight-api --idle-timeout 0 --port 8888 &
```
Use templates/start-hindsight.sh (start/stop/status).

## API (bypass CLI if needed)
- retain:  `POST /v1/default/banks/default/memories`  body `{"items":[{"content":"...","context":"learnings"}]}`
- recall:  `POST /v1/default/banks/default/memories/recall` body `{"query":"...","limit":5}`
- health:  `GET /health`

## Tool env build (what was installed)
```
UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ \
  uv tool install "hindsight-api@0.8.6" \
    --with "sentence-transformers>=5.0.0" --with "tokenizers==0.23.1"
```
(tokenizers pin: 0.23.0 does not exist; patch transformers table afterwards.)
