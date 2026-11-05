---
name: china-network-setup
description: "China-network Mac install fails: mirrors, uv, HF, dylibs."
---

# China-Network Setup (macOS, no Homebrew)

Environment class: China mainland network (international hosts flaky, TLS drops mid-download, huggingface.co blocked), macOS **without Homebrew** (`/opt` root-owned), and a **macOS system-level HTTP proxy** set (breaks Python httpx calls to localhost). Applies to xiebojun's Mac and any similar setup.

## When to use
- pip/uv/uvx download failures, `peer closed connection without sending TLS close_notify` mid-download
- huggingface.co unreachable; HF model downloads fail
- binaries fail with `Library not loaded: /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib` (no such file)
- Python httpx gets 502/connection errors on `http://127.0.0.1` while curl succeeds

## 1. Python packages (uv/pip) — mirrors
- **TUNA (`pypi.tuna.tsinghua.edu.cn`) returns 403 to uv** (and sometimes curl). Use **Aliyun**: `UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ UV_DEFAULT_INDEX=https://mirrors.aliyun.com/pypi/simple/`.
- Export BOTH `UV_INDEX_URL` and `UV_DEFAULT_INDEX`. Children spawned by tools usually inherit env via `os.environ.copy()`; if a child ignores them, inject into the child's own env instead.
- Big wheels drop TLS after a few MB. **Retry-loops converge**: uv caches completed wheels/content-addressed blobs, so re-running `uvx pkg@ver` / `uv tool install` until success makes incremental progress every round.
- GitHub release assets (`objects.githubusercontent.com`) can fail while **`codeload.github.com` works**: `curl -L -C - -o x.tar.gz "https://codeload.github.com/<owner>/<repo>/tar.gz/refs/tags/<tag>"`.

## 2. HuggingFace models
- Direct huggingface.co blocked; `HF_ENDPOINT=https://hf-mirror.com` is reachable but drops large transfers, and hf_hub HEAD-verification can fail with `LocalEntryNotFoundError` even after blobs downloaded.
- Robust fallback: **assemble a local model dir** — copy complete blobs from `~/.cache/huggingface/hub/models--<owner>--<name>/blobs/`, fetch missing small files with a retry loop of `curl -sL -C - "https://hf-mirror.com/<repo>/resolve/main/<file>"`, then point the consuming tool at the local path (e.g. `HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=/path/to/dir`). Verify every expected file exists before use.

## 3. Homebrew-dependent dylibs (no Homebrew)
- Homebrew-built binaries hardcode `/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib`. Build OpenSSL to a user dir, then rewrite dependents:
  ```
  curl -L -C - -o /tmp/ossl.tar.gz https://codeload.github.com/openssl/openssl/tar.gz/refs/tags/openssl-3.6.3
  cd /tmp/openssl-openssl-3.6.3 && ./Configure darwin64-arm64-cc shared no-tests --prefix=$HOME/openssl3
  make -j8 build_sw && make install_sw
  OL=$HOME/openssl3/lib
  install_name_tool -id "$OL/libssl.3.dylib" "$OL/libssl.3.dylib"
  install_name_tool -id "$OL/libcrypto.3.dylib" "$OL/libcrypto.3.dylib"
  install_name_tool -change "libcrypto.3.dylib" "$OL/libcrypto.3.dylib" "$OL/libssl.3.dylib"
  for f in $(grep -rl "/opt/homebrew/opt/openssl@3" <install_dir>); do
    install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib "$OL/libssl.3.dylib" "$f"
    install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib "$OL/libcrypto.3.dylib" "$f"
  done
  ```
- Verify with `otool -L <binary>` then run the binary's `--version` BEFORE starting the service.
- install_name_tool invalidates ad-hoc signatures; unsigned/ad-hoc dylibs still load in normal processes.

## 4. macOS system proxy → Python httpx 502 on localhost
- Symptom: `curl` gets 200 on `http://127.0.0.1:PORT/health` but Python httpx gets **502**. httpx `trust_env` reads macOS System Configuration proxy settings (via urllib).
- Fix (both cases matter): `export NO_PROXY="localhost,127.0.0.1" no_proxy="localhost,127.0.0.1"` before running the Python CLI/tool. This is required for the hindsight-embed CLI on this machine.

## 5. uv tool environments (uvx)
- `uv tool install pkg@ver --with "extra>=X"` builds the shared tool env that `uvx pkg@ver` reuses (runs from `~/.local/share/uv/tools/<pkg>/`).
- If the `uvx` spec differs from the install spec (e.g. plain `uvx pkg@ver` vs installed `--with` extras), uv may re-resolve and re-download the whole graph. Keep invocation specs identical to the install spec.
- Tool envs live under `~/.local/share/uv/tools/`; archive/cached CLI envs under `~/.cache/uv/archive-v0/`.

## 6. Long-lived daemons & supervisors
- Supervisors with readiness timeouts (~180s) may declare failure and kill a child that actually came up slowly. **Start the daemon binary directly** (Hermes background process), not via the supervisor CLI.
- Tools may not read their own config file when launched directly — config reaches the daemon via env injected by the manager. Source the config file before launching: `set -a; source <(grep -E '^[A-Z_]+=' <cfgfile>); set +a`.
- Check real health with `curl http://127.0.0.1:<port>/health`, not the manager's status command (status may key off a registry the failed manager never wrote).

## 7. Interactive CLIs (gh auth login, etc.)
- Background PTYs cannot deliver keystrokes to survey-style prompts (go-prompt/survey). Have the USER run interactive flows in the Hermes in-app terminal pane; observe progress with `read_terminal`; verify completion afterwards (`gh auth status`, config file created).
- `gh` without Homebrew: download the macOS release binary to `~/.hermes/bin` — resolve latest tag via `curl -sIL https://github.com/cli/cli/releases/latest` (Location header), then fetch `gh_<ver>_macOS_arm64.zip`.

## References & templates
- `references/hindsight-local-backend.md` — full bring-up recipe for the Hindsight local-memory daemon on this machine (every failure + fix in order)
- `templates/start-hindsight.sh` — known-good daemon start/stop/status script (copy & adapt to any daemon)
