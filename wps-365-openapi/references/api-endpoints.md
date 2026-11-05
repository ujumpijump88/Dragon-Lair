# WPS 365 开放平台 — 详细知识库（2026-08 实测）

本文件记录 WPS 365 开放平台接入的深层细节，供排查与扩展使用。正文要点见 SKILL.md。

## 1. KSO-1 签名算法（私网部署）

来源：官方 npm 插件 `@wps365/openclaw-wpsxiezuo` 的 `dist/core/wps-client.js`。

```
stringToSign = "KSO-1" + method + requestURI + contentType + dateStr + sha256Hex(body)
signature    = HMAC-SHA256(appSecret, stringToSign)  # hex 编码
headers:
  X-Kso-Date: <RFC1123 UTC date，如 Thu, 08 Aug 2026 03:00:00 GMT>
  X-Kso-Authorization: KSO-1 {appId}:{signature}
```

- 私网 HTTP API 通常要求 **OAuth Bearer + KSO-1 签名同时发送**（PrivateNetworkAuthProvider）
- 公网（openapi.wps.cn）只需要 Bearer；MCP 明确关闭接口签名
- 判断公网/私网：`hostname === "openapi.wps.cn"` 为公网

## 2. 鉴权端点细节

- `POST https://openapi.wps.cn/oauth2/token`
  - Content-Type 必须 `application/x-www-form-urlencoded`（JSON → 41500001）
  - client_credentials：`grant_type=client_credentials&client_id=AK...&client_secret=...`
  - access_token 有效期 2 小时（expires_in=7200），token_type=bearer
  - 文档：/app-integration-dev/wps365/server/certification-authorization/get-token/selfapp-tenant-access-token
- 设备码流程：`wps365-cli auth login --device`（CLI 内部走 openapi.wps.cn/oauth2/device/* 系列）
- OAuth 授权端点：`https://openapi.wps.cn/oauth2/auth`（CLI auth status 可见）

## 3. 关键错误码速查

| HTTP/错误 | 含义 | 处理 |
|---|---|---|
| 403 403000004 "does not support app authorization" | API 只支持用户授权 | 换 delegated token |
| 401 401000001 "Invalid token format. header not found" | Bearer 值不是 JWT/access_token | 换真实 token（密钥≠token）|
| 401 40100008 invalid_client not_found | client_id/secret 错 | 检查 AK 前缀 ID 与 secret |
| 400 40000001 invalid_request | grant_type/参数错 | 查文档参数 |
| 415 41500001 Content-Type unsupported | 用了 JSON | 改 form-urlencoded |
| 401 invalid_scope (设备码) | 应用没申请该 scope | 开发者后台申请+发布+管理员审核 |
| 401 401030003 "凭证无效" (agentspace) | 凭证未被识别 | 换正确通道 |
| 401 401020001 "账号未登录" (agentspace) | 需要会话 cookie 类认证 | 该网关需登录态 |

## 4. MCP 工具清单（v2）

端点模式：`https://openapi.wps.cn/mcp/v2/{slug}/message`，鉴权 `Authorization: Bearer <user token>`。

| slug | 工具 | 权限 |
|---|---|---|
| kso-yundoc | 云文档搜索/内容提取(markdown)/评论/文件信息/分享/权限 | delegated: kso.mcp_yundoc.readwrite |
| kso-airpage | 智能文档 | kso.mcp_airpage.readwrite |
| kso-calendar | 日程 | kso.mcp_calendar.* |
| kso-dbsheet | 多维表格（用户授权）| kso.mcp_dbsheet.* |
| kso-dbsheet-app | 多维表格（应用授权）| app: kso.dbsheet.readwrite |
| kso-mail | 邮箱 | kso.mcp_mail.* |
| kso-meeting | 会议 | kso.mcp_meeting.* |
| kso-message / kso-message-app | 协作消息与会话 | kso.mcp_message.* |

MCP 对接指南：https://open.wps.cn/documents/app-integration-dev/mcp-server/use-guide（含 Python streamablehttp_client 示例、Cursor 配置示例）。

## 5. AI 助理身份（WPS-key）调查结论（2026-08）

- 位置：WPS 客户端/工作台「智能体管理」→ 创建 AI 助理身份（每用户仅 1 个）
- 形态：身份 ID `ag_<32hex>`（如 ag_85881c...），密钥「WPS-key」显示为 `apik: ………`，完整格式 `apik:<32hex>.<32hex>`
- 授权：默认满配（云文档/云盘/IM 协作/会议/表单 全部「已授权」），「未来将支持按能力配置授权范围」
- **实测结论：所有公开网关拒绝** —— openapi.wps.cn（REST v7 + MCP v1/v2 全部工具）、agentspace.wps.cn（401 凭证无效）、oauth2/token（invalid_client）、kdocs 系网关。界面「凭证管理」只有重置按钮，无接入信息。
- 判断：WPS 自家生态（WPS AI/Comate/Agentspace）内部消费的凭证，**外部第三方 API 通道未开放**。不要反复探测；留着密钥等官方开放。
- 对照：OpenClaw 官方插件用「应用 appId/appSecret + 用户 OAuth」，与 WPS-key 无关。

## 6. 文档站逆向技巧（open.wps.cn / kdocs 系）

- 文档站是 React SPA：curl 首页/文档页只拿 ~579B 壳，正文内容不在 HTML
- **markdown 源直取**：`https://open-docs.wpscdn.cn/docs-md/zh/{路由路径}.md`（如 `/app-integration-dev/mcp-server/use-guide.md`）。部分新文档 md 未发布（404）
- **文档树 API**：`https://open.wps.cn/docs/api/collections?lang=zh`（集合列表：guide/wps365/mcp-server/client/docs-center 等）；`/docs/api/collections/{id}?lang=zh`（完整文档树，含全部路径）
- 前端 bundle：`https://cloudcdn.qwps.cn/open/.../*.js`（10-21MB），grep 可挖：API 路径、scope、文档链接、隐藏功能（本会话挖出 `OPENCLAW_PLUGIN_URL`、`/wps365-cli` 基路径、agentspace.wps.cn、`/passport/secure/api/grant_token` 等）
- kdocs 分享文档（365.kdocs.cn/l/xxx）：正文走 WebSocket/专用协议，curl 拿不到；让用户复制正文或「复制为 Markdown」
- 登录态内容：短链（如 cnO3PU3devdH）重定向到登录页，需用户浏览器会话

## 7. 官方 CLI 备忘（wps365-cli）

- 安装：GitHub wps365-open/cli releases（中国网络用 release 直链，勿用 install.sh 管道）
- spec：`~/Library/Application Support/wps365-cli/spec/api.yaml`（完整 OpenAPI，含每个端点的 security/scope！）+ curated.yaml（精选命令）
- 常用命令：`config init`（绑定）、`auth setup/login/status/token`、`api get|post`（通用端点）、`provider`（外部 provider，支持 api-key 认证类型）、`spec update`、`drive/dbsheet/calendar/mail/im/meeting/user`（精装命令）
- 设备码授权成功后 token 存钥匙串/加密文件，`auth refresh` 可续期

## 8. 常用 scope 参考（从 spec 提取）

```
kso.user_base.read          用户基础信息
kso.drive.readwrite         云盘文件管理（含上传下载）
kso.file.readwrite          文件读写
kso.file_search.readwrite   文件搜索
kso.doclib.readwrite        文档库
kso.dbsheet.readwrite       多维表格
kso.airpage.readwrite       智能文档
kso.airsheet.readwrite      智能表格
kso.calendar.readwrite / kso.calendar_events.readwrite   日历/日程
kso.todo.readwrite          待办
kso.chat.readwrite / kso.chat_message.readwrite          会话/消息
kso.contact.read / kso.contact.readwrite                 通讯录
kso.meeting.readwrite / kso.meeting_rooms.readwrite      会议/会议室
```

注意：spec 里列出的 scope 名与授权端点实际允许的 scope 可能不同步——`invalid_scope` 以授权端点为准（应用已申请并通过审核的才允许）。
