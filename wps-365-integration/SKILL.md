---
name: wps-365-integration
description: "Use when connecting Hermes to WPS 365 (云文档/金山文档)."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [wps, wps365, 金山文档, kdocs, cloud-docs, integration, agent, api]
---

# WPS 365 Integration (WPS 云文档 / 金山文档)

Class: connect Hermes to WPS 365 services — cloud docs (云文档), drive (云盘), IM, calendar, mail, meetings, dbsheet (多维表格). Verified 2026-08 against the live open.wps.cn platform + wps365-open/cli v0.3.1.

## Read the docs (SPA trick)

open.wps.cn / developer.kdocs.cn are JS SPAs — curl returns shells, not content. The real docs are **raw markdown** at a predictable path:

```
https://open-docs.wpscdn.cn/docs-md/zh/app-integration-dev/<doc-path>.md
```

To discover doc paths, download the doc-app bundle and grep it: `https://cloudcdn.qwps.cn/open/doc-app-web/assets/index-*.js` (~21 MB, holds nav/route strings).

Key docs (verified):
- `guide/self-app/summary.md` — app dev flow (create → configure → publish → admin approve)
- `guide/app-type.md` — 3 app types (企业自建 / 第三方企业 / 第三方个人)
- `wps365/server/certification-authorization/summary.md` — access-token model
- `wps365/server/api-description/flow.md` — call flow
- `mcp-server/introduction.md` — MCP (enterprise trial form)
- `cli/wps365-cli-installation-guide.md` — official "面向 AI Agent" CLI guide

Full map + probe results: `references/wps-open-platform-notes.md`.

## Four access paths (pick by situation)

| Path | Prereq | Best for |
|---|---|---|
| **WPS 365 CLI** | enterprise account + app + admin approval | agent shell access to 7 domains incl. file upload/download |
| **REST API** (openapi.wps.cn) | same enterprise prereq | scripted/HTTP calls, custom flows |
| **MCP Server** | enterprise + trial form | MCP-native hosts |
| **AI 助理身份 (AI Assistant Identity)** | WPS client 智能体管理, generate key | simplest: dedicated agent key, default full permissions — user's preferred path (protocol pending verify) |

## Install WPS 365 CLI (China network)

repo: `github.com/wps365-open/cli` (Go, MIT). The official one-liner pipes raw.githubusercontent.com — flaky from China; use GitHub Releases instead:

```bash
mkdir -p ~/.wps365-cli/bin
ARCH=$(uname -m | sed 's/arm64/aarch64/')
curl -sL -o /tmp/wps365-cli.tar.gz \
  "https://github.com/wps365-open/cli/releases/download/v0.3.1/wps365-cli-${ARCH}-apple-darwin.tar.gz"
tar -xzf /tmp/wps365-cli.tar.gz -C ~/.wps365-cli/bin && chmod +x ~/.wps365-cli/bin/wps365-cli
# ~/.zshrc: export PATH="$HOME/.wps365-cli/bin:$PATH"
wps365-cli version   # → cli: 0.3.1 / curated: 1.0
```

## Auth (all flags verified via --help)

- **Path A (easiest):** `wps365-cli config init` — one-click app registration; opens browser (create/bind app + authorize), CLI polls and stores credentials itself. Flags: `--new`, `--force`, `--debug`.
- **Manual (Path B):** `wps365-cli auth setup --client-id X --client-secret Y` — fully non-interactive (also `--redirect-uri`). Then `wps365-cli auth login --device --scopes "..."` — device flow, headless-friendly. Verify with `auth status` / `user me`.
- **API-key providers:** `wps365-cli provider add --auth-type api-key --auth-header <Header-Name> --base-url <url> --source-url <openapi-or-path>` mounts key-auth services; `provider list` shows built-in wps365 (oauth2, openapi.wps.cn).
- **Spec:** local OpenAPI at `~/Library/Application Support/wps365-cli/spec/api.yaml` (~1.8 MB, all /v7 endpoints incl. AI); refresh with `wps365-cli spec update -y`; ad-hoc calls: `wps365-cli api get "/v7/users/current"`.

## Enterprise prerequisite (CLI/REST/MCP paths)

1. Create 企业自建应用 at open.wps.cn/developer — **enterprise account required; personal accounts cannot create apps**
2. Add callback `http://localhost:18365/callback` (开发配置 → 安全设置 → 用户授权回调配置)
3. Request scopes (权限管理 → 能力权限). Cloud-doc essentials:
   `kso.file.readwrite` (含上传下载), `kso.file_search.readwrite`, `kso.drive.readwrite`, `kso.doclib.readwrite`, `kso.dbsheet.readwrite` (多维表格 CRUD). readwrite 已含 read。
4. Publish a version (应用发布 → 版本管理) + admin approval at work.wps.cn (应用市场 → 应用审核)

Two access-token types per API: 用户授权凭证 (delegated, user's own data) vs 应用授权凭证 (tenant scope, needs data-permission config). Each API's spec marks which it supports.

## AI 助理身份 (AI Assistant Identity) — simplest path, protocol pending

Found in WPS 客户端 / 工作台 → 智能体管理 (Agent management), dialog "AI助理能力说明" (read via screenshot OCR, 2026-08-08):
- Dedicated identity **designed for external Agents**; acts on user's behalf within granted scope: 文档 / 云盘 / IM / 会议 …
- Access via generated **访问密码 (key)**; **defaults to full open-platform permissions** (no per-scope application)
- Key rotation (重置密码) available; official warning to vet third-party hosts before configuring the key

⚠️ **Unresolved as of 2026-08**: the key's call protocol (base URL, auth-header scheme, OpenAI-compatible vs REST) is NOT yet verified — user had not generated the key at session end. When the key exists:
1. Keep it out of chat: save to a local file (e.g. `pbpaste > ~/.wps365-cli/assistant.key`)
2. Probe openapi.wps.cn endpoints with `Authorization: Bearer <key>` plus common header names
3. If a documented OpenAI-compatible base_url exists, test `/v1/chat/completions`
4. Mount via `provider add --auth-type api-key` once the protocol is known

## Pitfalls

- `open.wps.cn` and `developer.kdocs.cn` serve the SAME SPA bundle (cloudcdn.qwps.cn/open/web_open-homepage/).
- `POST openapi.wps.cn/oauth2/token` returns **415 for JSON** — send `application/x-www-form-urlencoded`. `GET /oauth2/device/verify` exists (200).
- GitHub unauthenticated API rate limit 60 req/hr — batch reads.
- MCP is **enterprise-only** (trial form: f.kdocs.cn/ksform/w/write/KrrG1pwZ).
- Do not promise personal-account access: app creation requires the enterprise account.
