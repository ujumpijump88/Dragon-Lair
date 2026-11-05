# WPS 365 接入参考资料（2026-08-08 会话实测整理）

## 官方文档地址

- WPS 开放平台：https://open.wps.cn/ （开发者后台 /developer，企业管理后台 /work.wps.cn）
- CLI 使用指南（README）：https://github.com/wps365-open/cli
- CLI 安装指南（面向 Agent）：https://open.wps.cn/documents/cli/wps365-cli-installation-guide.md
- MCP 对接指南：https://open.wps.cn/documents/app-integration-dev/mcp-server/use-guide
- MCP 工具列表：https://open.wps.cn/documents/app-integration-dev/mcp-server/tools/（每域一个 mcp_kso-*.md）
- 认证与授权概述：/app-integration-dev/wps365/server/certification-authorization/summary
- 获取租户 access_token：/app-integration-dev/wps365/server/certification-authorization/get-token/selfapp-tenant-access-token
- 数字员工聊天组件：/app-integration-dev/guide/open-components/agentspace-chat-websdk

markdown 源直取：`https://open-docs.wpscdn.cn/docs-md/zh/<上面路径>.md`
文档树 API：`GET https://open.wps.cn/docs/api/collections?lang=zh` → `GET /docs/api/collections/<id>?lang=zh`

## 关键 scope 表

| Scope | 说明 |
|---|---|
| kso.user_base.read | 查当前用户（仅 delegated） |
| kso.file.read / readwrite | 云文档读写（含上传下载） |
| kso.file_search.readwrite | 搜索文件 |
| kso.drive.readwrite | 驱动盘管理 |
| kso.doclib.readwrite | 文档库管理 |
| kso.dbsheet.read / readwrite | 多维表格 |
| kso.mcp_yundoc.readwrite | MCP 云文档（delegated） |
| kso.mcp_airpage.readwrite | MCP 智能文档 |
| kso.component.agentspace_chat | 数字员工聊天组件 |
| kso.calendar_events.readwrite / kso.mail.readwrite / kso.meeting.readwrite / kso.chat_message.readwrite | 其他业务域 |

## MCP 工具端点（MCP 2.0）

`https://openapi.wps.cn/mcp/v2/<tool>/message`，header `Authorization: Bearer <access_token>`，Streamable HTTP（Accept: application/json, text/event-stream）。

| tool | 能力 | 关键工具 |
|---|---|---|
| kso-yundoc | 云文档 | kso_yundoc_search_yundoc / extract_yundoc_content（markdown）/ get_file_meta / permissions_batch_create |
| kso-airpage | 智能文档 | 块级读写 |
| kso-dbsheet | 多维表格 | 记录/字段 CRUD |
| kso-calendar / kso-mail / kso-meeting / kso-message / kso-todo / kso-scenario | 其他域 | 各域 CRUD |

## CLI spec 本地路径

- `~/Library/Application Support/wps365-cli/spec/api.yaml`（完整 OpenAPI，800+ 端点，/v7/ 前缀）
- `~/Library/Application Support/wps365-cli/spec/curated.yaml`（精装命令定义）
- 查端点：`grep -nE "^  /" api.yaml`；查 security：端点定义尾部 `security:` 段（app: / delegated: 列表）
- 常见端点前缀：/v7/drives（云盘）、/v7/aiopen/*（AI 能力：drives/{drive_id}/files/{file_id}/qa、sessions、aigc/compose）、/v7/airsheet/*、/v7/airpage/*、/v7/oauth2/*

## AI 助理密钥探索记录（2026-08-08 定论：外部接入未开放）

- 来源：WPS 客户端/工作台「智能体管理」→ 创建 AI 助理身份 →「生成访问密码」
- 身份 ID：`ag_<32hex>`（独立于密钥，界面单独显示，如 ag_85881c744b87a834706c727971a98ebd）
- 密钥格式：`apik:<32hex>.<32hex>`——**apik: 是前缀本身**（界面掩码「apik ………」），非 "API Key:" 标签；密钥可重置轮换
- 身份类型「用户助理」；授权满配（云文档/云盘/IM/会议/表单全部已授权，免申请 scope）
- 弹窗文案：「AI 助理身份是专为你的 Agent 设计的独立身份…通过密钥接入…默认授予当前开放平台的全部权限」
- **已测失败（40+ 组合全 401）**：openapi.wps.cn Bearer/裸 key/apik: 前缀（401 invalid token format）；oauth2/token client_credentials 各组合含 ag_id（401 invalid_client）；MCP v1/v2 全部工具域含 kso-dbsheet-app/kso-message-app（401 access token validation failed）；agentspace.wps.cn Bearer（code 401030003 凭证无效）；365.kdocs.cn / openapi.kdocs.cn（无路由）；/v1/chat/completions（空）
- **结论**：官方文档站（guide/wps365/mcp-server/docs-center 全集合）无任何 WPS-key 调用文档；截至 2026-08-08 外部第三方 API 通道未开放/未公开，密钥仅在 WPS 客户端生态内部消费。接入需求走 CLI `config init` + 企业自建应用 OAuth 保底
- 网关域名：openapi.wps.cn（业务 API）、agentspace.wps.cn（智能体平台 admin/api/v1、api/v2/gpt/、api/v3）、365.kdocs.cn（开放平台入口，3rd/open/...）、openapi.kdocs.cn（非 WPS365 API，路由全 404）

## OpenClaw 官方插件（WPS 365 ↔ 开源 Agent 框架）

- 文档站前端 bundle（doc-app-web assets/index-*.js）常量：`OPENCLAW_PLUGIN_URL="https://365.kdocs.cn/l/cnO3PU3devdH"`、`WPS365_CLI_BASE="/wps365-cli"`、CollectionOrder 含 `openclaw:8`
- 官方弹窗文案：「WPS 365 now supports OpenClaw! Chat with WPS Digital Employee via OpenClaw to use 365 skills for sending messages, creating schedules, and booking meetings」——注意官方列出的能力是 IM/日程/会议，未提云文档
- 插件文档短链需 365.kdocs.cn 登录态，curl 只能拿到登录跳转页；插件本体不在 GitHub（wps365-open 组织仅 cli 一个仓库；GitHub 搜 "wps openclaw" 只有社区第三方插件如 skyispainted/openclaw-channel-wps-xiezuo、hornbillw/openclaw-channel-xiezuo）
- OpenClaw = 开源 AI agent 框架（与 Hermes/Claude Code 同类）；此插件是「AI 助理身份/WPS-key 未来可能的官方消费通道」线索，若官方发布外部接入文档应优先跟进验证
- 数字员工（Agentspace）平台建应用入口：https://agentspace.wps.cn/build；应用 AK/SK 查看：https://365.kdocs.cn/3rd/open/developer/manager/{agentId}/app-info
