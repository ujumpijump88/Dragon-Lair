---
name: wps-365-openapi
description: "Use when 接入/调用 WPS 365 开放平台：wps365-cli、云文档/云盘 API、WPS MCP。"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [wps, wps365, kdocs, openapi, integration, cloud-docs, mcp]
---

# WPS 365 开放平台接入

WPS 365（金山办公企业版）开放平台接入：云文档/云盘/多维表/日历 API、MCP server、官方 CLI、OpenClaw 插件。适用于「让 Hermes 读写 WPS 云文档/云盘/多维表」一类任务。

## 接入总览（2026-08 实测路径）

标准接入 = 开放平台应用（appId/appSecret）+ 用户 OAuth 授权 → `Authorization: Bearer <access_token>` 调 `https://openapi.wps.cn/v7/*`。

最快路径：

1. **安装官方 CLI**（github.com/wps365-open/cli，Go 二进制，MIT）
   - 中国网络 raw.githubusercontent.com 不稳：直接下 GitHub Releases 二进制（`wps365-cli-aarch64-apple-darwin.tar.gz`）
   - 解压到 `~/.wps365-cli/bin/`，PATH 加 `$HOME/.wps365-cli/bin`（写入 ~/.zshrc）
   - 验证：`wps365-cli version` → `cli: 0.3.1`

2. **绑定应用**：`wps365-cli config init --new --force`（后台跑，输出设备码链接，**5 分钟过期**，过期 exit 2）
   - 用户浏览器打开链接 → 登录企业账号 → 创建应用 → CLI 自动写入 client_id（AK 前缀）+ client_secret（钥匙串）
   - 成功标志：`OK: 应用配置成功! App ID: AK...`
   - 非交互配置已有应用：`wps365-cli auth setup --client-id <id> --client-secret <secret>`

3. **⚠️ 关键坑：config init 新应用默认无任何 scope 权限** —— `auth login` 报 `invalid_scope: ... is not allowed` 就是权限没申请。需去 https://open.wps.cn/developer 应用「权限管理」申请 scope → 应用发布 → 创建版本提交发布 → 企业管理员在 work.wps.cn 审批。
   - 备选捷径：fastapp 一键配置 https://365.kdocs.cn/woa/openclaw/fastapp 自动申请插件全套权限（机器人应用），拿 appId/appSecret 配到 CLI。

4. **用户授权**：`wps365-cli auth login --device --scopes "kso.drive.readwrite,kso.file.readwrite,..."`（设备码流程，**无需回调地址**，headless 可用）
   - 授权回调地址（插件/网页应用用）：`https://365.kdocs.cn/woa/openclaw/callback` 或本地 `http://localhost:18365/callback`

5. **调 API**：`wps365-cli api get "/v7/drives?allotee_type=user&page_size=10"` 或 curl 带 Bearer token

## 鉴权体系

| 凭证 | 获取 | 用途 |
|---|---|---|
| 用户授权 token (delegated) | OAuth 授权码/设备码 | 代表用户操作（云文档、日历、消息）|
| 应用授权 token (app) | `POST /oauth2/token` client_credentials | 应用自身资源、通讯录等 |
| KSO-1 签名（私网部署） | HMAC-SHA256(appSecret) | 私网 API，详见 references/api-endpoints.md |

- `403 ... does not support app authorization, required delegated scopes: [...]` = 该 API 需要**用户授权** token
- `401 invalid_token ... Invalid token format. header not found` = Bearer 值不是有效 access_token（JWT）
- `POST /oauth2/token` **只收 `application/x-www-form-urlencoded`**，JSON body 返回 41500001

## 云文档核心端点（openapi.wps.cn，v7）

```
GET  /v7/drives?allotee_type=user|app&page_size=N            # 盘列表
GET  /v7/drives/{drive_id}/files/{parent_id}/children       # 子文件列表
POST /v7/drives/{drive_id}/files/{parent_id}/create         # 新建文件/夹
POST /v7/drives/{drive_id}/files/{parent_id}/request_upload # 上传（第一步）
POST /v7/drives/{drive_id}/files/{parent_id}/commit_upload  # 上传（第二步）
GET  /v7/drives/{drive_id}/files/{file_id}/content          # 读文档内容(markdown)
GET  /v7/files/{file_id}/meta                               # 文件信息
GET  /v7/files/search                                       # 文件搜索
```

## WPS MCP Server

- 端点：`https://openapi.wps.cn/mcp/v2/{kso-yundoc|kso-calendar|kso-dbsheet|kso-dbsheet-app|kso-mail|kso-message|kso-meeting|...}/message`
- 鉴权：`Authorization: Bearer <用户 access_token>`（MCP 协议 POST + JSON-RPC；文档 https://open.wps.cn/documents/app-integration-dev/mcp-server/use-guide）
- 云文档工具：`kso_yundoc_search_yundoc` / `kso_yundoc_extract_yundoc_content`（返回 markdown）/ `kso_yundoc_get_file_meta`；权限 `delegated: kso.mcp_yundoc.readwrite`
- MCP 关闭接口签名（KSO-1 不适用）

## 官方 OpenClaw 插件（参考实现，不看文档也能逆向）

npm 包 `@wps365/openclaw-wpsxiezuo`（WPS 协作机器人 channel 插件）= 官方 API 调用逻辑：
```bash
npm view @wps365/openclaw-wpsxiezuo version   # 用 registry.npmmirror.com
npm pack @wps365/openclaw-wpsxiezuo           # 解压看 dist/tools/oapi/*.js
```
- `dist/tools/oapi/cloud-doc.js`：云文档 tools 实现（端点 + 参数 + 上传流程）
- `dist/core/wps-client.js`：KSO-1 签名算法、AuthProvider 结构
- 插件配置 `~/.openclaw/openclaw.json`：`channels.wps-xiezuo {appId, appSecret, baseUrl: https://openapi.wps.cn}`
- 插件能力：云文档增删查/搜索/读内容/本地文件上传、智能文档编辑、多维表、智能表格、日历、待办、会议室

## 已知坑 / 注意事项

1. **AI 助理身份（WPS-key）≠ 标准 API 凭证**（2026-08 实测）：密钥格式 `apik:<32hex>.<32hex>`，身份 ID `ag_<32hex>`，授权满配（云文档/云盘/IM/会议/表单）但 **openapi/agentspace/mcp 所有公开网关均 401「凭证无效」**——外部 API 通道未开放，别浪费时间探测（详见 references/api-endpoints.md）。
2. **config init 新应用无默认 scope**（见步骤 3）。
3. 文档站是 SPA（curl 只拿壳）：markdown 源在 `https://open-docs.wpscdn.cn/docs-md/zh/{path}.md`；文档树 API `https://open.wps.cn/docs/api/collections/{guide|wps365|mcp-server|...}?lang=zh`；前端 JS bundle 在 cloudcdn.qwps.cn（可 grep 挖链接/端点）。
4. 设备码链接 5 分钟过期，后台进程会 exit 2，需重新跑。
5. spec 文件（800+ 端点 OpenAPI，含 security/scope 定义）：macOS 在 `~/Library/Application Support/wps365-cli/spec/api.yaml` + curated.yaml（grep scope 名查授权要求）。

## 验证

```bash
wps365-cli auth status    # client_id/secret 状态
wps365-cli user me        # 当前用户（需授权）
wps365-cli api get "/v7/drives?allotee_type=user&page_size=10"
```

## 参考文件

- `references/api-endpoints.md` — 详细端点/签名算法/AI 助理身份调查结论/文档站逆向技巧
