# WPS 365 OpenAPI 速查（2026-08 实测 + 官方插件源码实证）

## 网关与凭证

- 公网网关：`https://openapi.wps.cn`（v7 REST + /mcp/v2 + /oauth2）
- 应用 token：`POST /oauth2/token`，`grant_type=client_credentials&client_id=<APPID(AK...)> &client_secret=<APPKEY>`，返回 access_token（**2h**）+ expires_in。Content-Type 必须 `application/x-www-form-urlencoded`（JSON 报 41500001）。
- 授权码端点 `/oauth2/auth`；设备码校验 `/oauth2/device/verify?user_code=...`。
- 用户 delegated token：`wps365-cli auth login --device --scopes ...`（免回调地址，headless 可用）。

## KSO-1 签名（私网/专有云环境）

```
stringToSign = "KSO-1" + method + uri + contentType + X-Kso-Date(RFC1123) + sha256hex(body)
signature    = HMAC-SHA256(appSecret, stringToSign)  # hex
Headers: X-Kso-Date, X-Kso-Authorization: "KSO-1 {appId}:{signature}"
```

私网 HTTP 通常要求 OAuth Bearer + KSO-1 同时发送；公网 openapi.wps.cn 只需 Bearer。MCP 关闭接口签名。

## 权限 4 维（文档 guide/permission）

1. 访问凭证：client_id / client_secret
2. API 权限（scope）：能调哪些接口；申请后须发布版本 + 企业管理员审核才生效
3. 可用范围：哪些用户能看到/使用应用
4. 数据权限：应用可访问的企业数据范围；**配置后才能调云文档/消息等业务接口**，否则 403 `interface_company_doc`

企业 web 端能看到文档 ≠ 应用有数据权限。只配置不发布 = 停在「待提交审核」，不生效。

## 常见错误码

| 错误 | 含义 / 处理 |
|---|---|
| `403000004 does not support app authorization, required delegated scopes` | 该 API 只支持用户授权 → 用 delegated token |
| `401 invalid_token "header not found"` | Bearer 值不是有效 token（如直接塞 API key） |
| `invalid_scope` | scope 未申请/未审核 → 开发者后台申请 + 发布 + 审核 |
| `403 interface_company_doc` | 应用缺企业文档「数据权限」→ 权限管理配数据权限 + 发布 + 审核 |
| `401030003 凭证无效`（agentspace.wps.cn） | 该网关不认当前凭证 |
| `41500001 Content-Type unsupported` | oauth2/token 必须 form-urlencoded |
| `400 Bad Request`（files/search 等） | 缺必填参数（如 type）或中文未 URL 编码 |

## 云文档 v7 端点（openclaw 插件 dist/tools/oapi/cloud-doc.js 实证）

- `GET /v7/drives?allotee_type=user&page_size=N` — 盘列表（allotee_type: user|group|app）
- `GET /v7/drives/{drive_id}/files/{parent_id}/children` — 子文件列表
- `POST /v7/drives/{drive_id}/files/{parent_id}/create` — 新建文件/夹
- `POST /v7/drives/{drive_id}/files/{parent_id}/request_upload` + `commit_upload` — 上传
- `GET /v7/drives/{drive_id}/files/{file_id}/content` — 提取文档内容
- `GET /v7/files/{file_id}/meta` — 文件元信息
- `GET /v7/files/search?keyword=&type=file_name|content|all&page_size=` — 搜索（type 必填）
- 可选 header `X-Kso-Id-Type: internal|external`（用户/部门 id 转换）

## scope 速查（spec api.yaml 提取）

drive/file 系：`kso.drive.readwrite` `kso.file.readwrite` `kso.file_search.readwrite` `kso.doclib.readwrite` `kso.file_link.readwrite` `kso.file_permission.readwrite` `kso.file_version.readwrite`
表格系：`kso.dbsheet.readwrite`（多维表）`kso.airsheet.readwrite`（智能表格）`kso.airpage.readwrite`（智能文档）
MCP 系：`kso.mcp_yundoc.readwrite`（MCP 云文档）`kso.mcp_airpage.readwrite` `kso.mcp_dbsheet.readwrite`（MCP 文档权限常出现在 /v7 接口的 delegated 列表里，与 AI 助理授权体系同源）
其他：`kso.user_base.read` `kso.calendar.readwrite` `kso.calendar_events.readwrite` `kso.chat.readwrite` `kso.chat_message.readwrite` `kso.mail.readwrite` `kso.meeting.readwrite` `kso.todo.readwrite`

## 相关外部资源

- CLI 仓库：github.com/wps365-open/cli（install.sh / docs / releases）
- OpenClaw 官方插件：npm `@wps365/openclaw-wpsxiezuo`（npmmirror tarball 可看源码；插件配置 ~/.openclaw/openclaw.json，回调 365.kdocs.cn/woa/openclaw/callback）
- 插件一键建应用：365.kdocs.cn/woa/openclaw/fastapp（自动申请插件所需权限点 + 事件 kso.app_chat.message.create / kso.developer.application.auth_code.create）
- 文档站：open.wps.cn/documents（SPA）；md 源 open-docs.wpscdn.cn/docs-md/zh/<path>.md；文档树 open.wps.cn/docs/api/collections[/<id>?lang=zh]
- 智能体平台：agentspace.wps.cn（数字员工；API 需独立凭证，WPS-key 不可用）
