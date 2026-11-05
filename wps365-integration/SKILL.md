---
name: wps365-integration
description: "接入 WPS 365 云文档（CLI/MCP/REST/AI 助理密钥）。读取/写入云文档前先读本技能。"
version: 1.0.0
author: Hermes Agent (curator)
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [wps, wps365, kdocs, 金山文档, cloud-docs, mcp, oauth, agentspace]
    related_skills: [hermes-agent, ocr-and-documents, google-workspace, notion]
---

# WPS 365 / WPS 云文档接入

用户场景：让 Hermes 读取/分析 WPS 云文档内容 + 上传写入。官方为 AI Agent 提供三套通道（CLI / MCP / REST API），另有「AI 助理身份」密钥通道（状态见下）。

## 硬性前提

- **WPS 365 企业账号**是官方通道（CLI/MCP/REST 企业自建应用）的共同前提——官方文档原话：「个人账号无法完成应用创建与审批」。个人账号只能走本地文件同步替代方案。
- 权限生效链路：创建企业自建应用 → 申请 scope → 提交版本发布 → 企业管理员在 https://work.wps.cn 应用市场审批。仅申请不发布，权限一直是「待提交审核」。
- OAuth 回调地址固定 `http://localhost:18365/callback`。

## 通道 1：WPS 365 CLI（已验证可用，官方文档就是写给 Agent 的）

**本机接入状态（2026-08-08）**：已绑定应用 `AK20260808FHWLUL`（`config init` 创建），用户 delegated token 授权成功（scope：`kso.doclib/drive/file/file_search` readwrite + `kso.user_base.read`），`user me` 正常返回用户信息。
**⚠️ config init 新应用默认无任何 scope**——`auth login --device` 报 `invalid_scope: ... is not allowed` 即权限未申请；需开发者后台「权限管理」申请 → 应用发布 → 管理员审批。备选捷径：fastapp 一键配置 https://365.kdocs.cn/woa/openclaw/fastapp（自动申请插件全套权限的机器人应用），拿 appId/appSecret 用 `auth setup --client-id/--client-secret` 配置（设备码授权不依赖回调地址，通用）。
**⚠️ 403 `interface_company_doc`**：用户企业（全球未來科學家聯盟有限公司）云文档接口不可用（drive list / files search 均 403）——企业 WPS 365 云文档服务未开通或应用数据权限未配置，**非 token 问题**（user me 正常）。排查：work.wps.cn 企业管理后台查云文档模块开通情况。

- 官方仓库 `github.com/wps365-open/cli`（Go，MIT）。官方安装指南以「本文档面向 AI Agent」开头，规定流程：装 CLI + 引导用户浏览器建应用 → **唯一暂停点**等 client_id/client_secret → 其余全自动。
- 本机已装 v0.3.1 于 `~/.wps365-cli/bin`（PATH 已入 ~/.zshrc）。`wps365-cli version` 验证。
- **安装坑**：`raw.githubusercontent.com` 的 install.sh 常超时（中国网络）→ 直接 GitHub Releases 手动下载架构对应二进制（macOS arm64：`wps365-cli-aarch64-apple-darwin.tar.gz`，解压到 ~/.wps365-cli/bin）。
- 关键命令（均支持非交互 flag，Hermes 后台可跑）：
  - `config init`（官方路径 A，免手动建应用；浏览器完成注册/绑定，自动写凭证；`--new` / `--force`）
  - `auth setup --client-id X --client-secret Y`（凭证存系统钥匙串）
  - `auth login --scopes "kso.file.readwrite,..."`（`--device` 设备码流程可 headless）
  - `api get|post "/v7/xxx"` 调任意端点（未覆盖接口兜底）
  - `provider add --auth-type api-key --auth-header ... --base-url ... --source-url <openapi>` 挂载 API-key 服务
  - `spec status|update`：OpenAPI spec 本地化于 `~/Library/Application Support/wps365-cli/spec/api.yaml`（800+ 端点）+ curated.yaml
- 7 大业务域：通讯录/日历/IM/邮件/云文档/多维表格/会议。云文档 scope：`kso.file.readwrite`（含上传下载）、`kso.file_search.readwrite`、`kso.drive.readwrite`、`kso.doclib.readwrite`、`kso.dbsheet.readwrite`（多维表格增删改查）。

## 通道 2：WPS 365 MCP（官方，企业试用申请制）

- MCP 2.0 端点：`https://openapi.wps.cn/mcp/v2/<tool>/message`，鉴权 `Authorization: Bearer <access_token>`（透传用户授权 token；需在后台关闭接口签名）。
- 工具域（详见 `references/wps365-api-reference.md`）：kso-yundoc 云文档（搜索/提取内容转 markdown）、kso-calendar、kso-dbsheet、kso-mail、kso-meeting、kso-message、kso-todo、kso-scenario、kso-airpage；**部分域有应用授权版**：`kso-dbsheet-app`、`kso-message-app`（端点同名 <tool>/message）。云文档权限 `delegated: kso.mcp_yundoc.readwrite`。
- 企业试用申请：https://f.kdocs.cn/ksform/w/write/KrrG1pwZ

## 通道 3：REST API（openapi.wps.cn）

- token 端点：`POST https://openapi.wps.cn/oauth2/token`，Content-Type **必须** `application/x-www-form-urlencoded`（JSON 返回 415），`grant_type=client_credentials&client_id=<APPID 形如 AK2024***>&client_secret=<APPKEY>`；access_token 有效期 2 小时。
- 凭证两类：用户授权（delegated，OAuth 授权码流程）/ 应用授权（app，client_credentials）。同 API 两种凭证数据范围不同。
- 云盘 API 例：`GET /v7/drives?allotee_type=user|group|app&page_size=N`（security 同时声明 app + delegated scope）。

## AI 助理身份密钥（⚠️ 外部接入未开放，2026-08-08 实测定论）

WPS 客户端/工作台「智能体管理」创建，官方弹窗：「专为 Agent 设计的独立身份，通过密钥接入，授权范围内代表用户访问文档/云盘/IM/会议」。

**已确认的界面信息**（截图 OCR 验证）：
- 身份 ID 独立存在：`ag_<32hex>`（如 `ag_85881c744b87a834706c727971a98ebd`）
- 密钥格式：`apik:<32hex>.<32hex>`——**`apik:` 是密钥前缀本身**（界面掩码显示「apik ………」），不是 "API Key:" 标签
- 身份类型「用户助理」；授权满配：云文档/云盘/IM/会议/表单全部「已授权」（免申请 scope）
- 密钥可重置轮换；「查看授权」「凭证管理」入口在身份概览页

**40+ 组合实测全部 401（勿重复，除非官方发布新接入文档）**：
- openapi.wps.cn：Bearer/裸 key/apik: 前缀各种组合 → 401 invalid token format（密钥非 JWT）
- openapi.wps.cn/oauth2/token client_credentials（前段/后段/整体/ag_id 各组合）→ 401 invalid_client not_found
- MCP v1/v2 全部工具域（含应用授权版 kso-dbsheet-app、kso-message-app）→ 401 access token validation failed
- agentspace.wps.cn API：Bearer 凭证位被识别但 code 401030003「凭证无效」
- 365.kdocs.cn / openapi.kdocs.cn → 无有效路由
- 官方文档站全集合（guide/wps365/mcp-server/docs-center）无任何 WPS-key 调用文档

**结论**：截至 2026-08-08 该功能的**外部第三方 API 通道未开放/未公开**，密钥只在 WPS 客户端生态内部消费。用户若仍要接入：走保底方案——通道 1 CLI `config init` + 企业自建应用 OAuth（确定可用）。

**已确认的官方消费方：OpenClaw 插件**（WPS-key 未来开放接入时的参考实现）。npm 包 `@wps365/openclaw-wpsxiezuo`（npmmirror 下载，`npm pack` 解压看源码）：
- 配置 `~/.openclaw/openclaw.json`：`channels.wps-xiezuo {appId, appSecret, baseUrl: https://openapi.wps.cn}`；用户授权回调 `https://365.kdocs.cn/woa/openclaw/callback`
- 插件本质 = appId/appSecret + 用户 OAuth → Bearer 调 openapi.wps.cn v7 端点；云文档 tools 在 `dist/tools/oapi/cloud-doc.js`（`/v7/drives`、`children`、`create`、`request_upload`+`commit_upload`、`content`、`/v7/files/search`）；KSO-1 签名算法在 `dist/core/wps-client.js`（HMAC-SHA256(appSecret, "KSO-1"+method+uri+contentType+date+sha256(body))，私网用）
- 插件能力：云文档增删查/搜索/读内容/本地文件上传、智能文档编辑、多维表、智能表格、日历、待办、会议室

相关平台：agentspace.wps.cn（数字员工/智能体平台，建应用在 /build；应用 AK/SK 在 https://365.kdocs.cn/3rd/open/developer/manager/{agentId}/app-info）。WPS 官方另有 OpenClaw 插件（文档短链 365.kdocs.cn/l/cnO3PU3devdH，需登录态）——是 WPS-key 未来可能的官方消费通道，细节见 references/wps365-api-reference.md。

## 官方文档挖掘技巧（本类任务反复可用）

- **文档 markdown 源直取**：文档页路径 → `https://open-docs.wpscdn.cn/docs-md/zh/<路径>.md`（如 mcp-server/use-guide.md、mcp-server/tools/mcp_kso-yundoc.md）。
- **文档树 API**：`GET https://open.wps.cn/docs/api/collections?lang=zh`（集合列表）→ `GET /docs/api/collections/<id>?lang=zh`（嵌套文档树，node.path 即文档路径）。
- **SPA 逆向**：下载 JS bundle（cloudcdn.qwps.cn/open/...）grep URL/路径关键词，找 API 网关域名与路径（本会话借此定位 openapi.wps.cn、agentspace.wps.cn、open-docs.wpscdn.cn）。
- **鉴权语义探测**：401「invalid token format」= token 被解析但无效；401「凭证无效」= 凭证位正确内容无效；403「does not support app authorization」= 身份类型不匹配（该 API 仅 delegated）；400「authorization header not found」= 鉴权头名不对。用 `scripts/probe_wps_auth.sh`（密钥从环境变量读）批量探测。

## 截图 OCR（读 WPS 界面必备）

Hermes 无 vision 工具时，用 macOS 零安装 OCR 提取用户截图文字（中英均可）：
```bash
swift scripts/vision_ocr.swift /path/to/screenshot.png
```

## 验证步骤

1. `wps365-cli version` → 0.3.1
2. `wps365-cli auth status`（登录后）
3. 冒烟：`wps365-cli user me`，或 `wps365-cli api get "/v7/drives?allotee_type=user&page_size=10"`

## 支持文件

- `references/wps365-api-reference.md` — 官方文档 URL、scope 表、MCP 工具端点、AI 助理密钥探索记录
- `scripts/vision_ocr.swift` — macOS Vision 框架 OCR（swift 运行，零安装）
- `scripts/probe_wps_auth.sh` — 鉴权方式批量探测矩阵（密钥从 $WPS_AGENT_KEY 读）
