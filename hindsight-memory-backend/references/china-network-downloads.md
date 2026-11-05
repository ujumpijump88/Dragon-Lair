# China-network downloads, proxies, and GitHub access (verified 2026-08, macOS arm64)

Companion to the SKILL.md sections. Covers GitHub access patterns and CLI installs that this environment needs repeatedly.

## GitHub access & rate limits
- `api.github.com` unauthenticated: **60 req/hr per IP**. `hermes skills install <owner/repo/path>` and repo-content listing consume it — it can be exhausted mid-task.
- `raw.githubusercontent.com`: NOT API-rate-limited — use for single files (e.g. fetching a SKILL.md).
- `git clone`: git protocol, NOT the REST API — not counted against the limit; works when the API is exhausted.
- Raise to 5,000/hr: `gh auth login` (needs gh CLI) or set GITHUB_TOKEN.
- Determine the latest release tag without the API (rate-limit-safe):
  ```bash
  curl -sIL -o /dev/null -w "%{url_effective}" https://github.com/<owner>/<repo>/releases/latest
  ```

## gh CLI install without Homebrew (macOS arm64)
```bash
VER=$(curl -sIL -o /dev/null -w "%{url_effective}" https://github.com/cli/cli/releases/latest | sed -E 's#.*/tag/##' | tr -d '\r')
curl -sL -o /tmp/gh.zip "https://github.com/cli/cli/releases/download/$VER/gh_${VER#v}_macOS_arm64.zip"
unzip -o -q /tmp/gh.zip -d /tmp/gh-pkg
cp /tmp/gh-pkg/gh_${VER#v}_macOS_arm64/bin/gh ~/.hermes/bin/gh
```
- `gh auth login` uses interactive survey prompts; background-pty input delivery can fail — have the user run it in the in-app terminal, or use `gh auth login --with-token` (paste token, Enter, Ctrl+D).

## Installing Hermes skills when `hermes skills install` fails
```bash
git clone --depth 1 https://github.com/<owner>/<repo>.git /tmp/repo
cp -R /tmp/repo/skills/<skill-name> ~/.hermes/skills/<skill-name>
hermes skills list   # verify: shows source=local, enabled
```
Local copies lose hub-managed updates (`hermes skills update`); re-copy from the repo to refresh.

## Proxy/mirror summary
- **macOS system proxy (Clash 127.0.0.1:7897)**: httpx reads it via SystemConfiguration even with no env vars → localhost timeouts. Fix `NO_PROXY="127.0.0.1,localhost"`. curl/requests/aiohttp unaffected. Detect: `python -c "import httpx._utils as u; print(u.get_environment_proxies())"`.
- **PyPI mirrors for uv**: TUNA 403s uv; **Aliyun works** — `export UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ UV_DEFAULT_INDEX=https://mirrors.aliyun.com/pypi/simple/`.
- **uv cache retry convergence**: uv caches completed wheels; on flaky links loop `uvx <pkg>@<ver> --help` until it exits 0, then the real command. Don't give up after one timeout.
