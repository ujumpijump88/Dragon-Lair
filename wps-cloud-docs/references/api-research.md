# WPS 开放平台调研笔记（2026-08 实测）

## 关键端点
- 文档站 markdown 源：`https://open-docs.wpscdn.cn/docs-md/zh/<path>.md`（文档页 SPA 壳抓不到正文时，直接拼 md 路径；404 = 文档未发布或路径名不同）
- 文档树 API：`GET https://open.wps.cn/docs/api/collections/{id}?lang=zh`，id ∈ guide/wps365/mcp-server/client/collaboration-middleware/docs-center（openclaw 不在列表但前端有）
- MCP 端点：`https://openapi.wps.cn/mcp/v2/<tool>/message`（streamable HTTP + JSON-RPC；Bearer 用户 token）。工具：kso-yundoc（云文档）、kso-calendar、kso-dbsheet[-app]、kso-mail、kso-meeting、kso-message[-app]、kso-airpage、kso-todo、kso-scenario。**企业白名单制**。
- OpenAPI 网关：`https://openapi.wps.cn`（v7 前缀），token 端点 `POST /oauth2/token`（client_credentials，client_id=AK 开头 APPID）

## 权限模型（四维）
1. 访问凭证（client_id/client_secret）→ 2. API 权限 scope（需申请+发布+企业管理员审核）→ 3. 可用范围（哪些用户可见）→ 4. 数据权限（目前仅通讯录支持配置）
- `interface_company_doc` = 企业级「企业文档接口」特权，企业未开通（订阅不含/未付费）时所有 /v7/drives、/v7/files/* 一律 403，与 scope/数据权限/IP 白名单/接口签名无关。安全设置页（授权回调/IP白名单/H5域名/免重复授权/使用条款/接口签名）解决不了。
- MCP 有独立企业白名单：`Company ID xxx from access token is not in the MCP company whitelist`

## wps365-cli（github.com/wps365-open/cli，Go，release v0.3.1+）
- 安装：raw.githubusercontent.com 中国网络超时 → 从 GitHub Releases 下载对应架构 tarball 解压到 ~/.wps365-cli/bin（arm64 = aarch64-apple-darwin）；PATH 加 ~/.wps365-cli/bin
- `config init --new --force`：设备码绑定应用（open.wps.cn/developer/cli?user_code=xxx，5 分钟）
- `auth login --device --scopes "kso.drive.readwrite,..."`：设备码授权，无回调地址依赖（回调 localhost:18365 冲突时用 --device）
- scope 未审核时 device flow 报 `invalid_scope: The requested scope 'xxx' is not allowed`——是应用侧未申请/未审核，不是用户问题
- `auth token` 打印 access_token；`api get|post` 任意 v7 端点
- spec 本地：`~/Library/Application Support/wps365-cli/spec/{api.yaml,curated.yaml}`（api.yaml 1.8MB 全量 OpenAPI，含每个端点的 security scope 与参数枚举）
- 权限点参考（云文档）：kso.drive.readwrite / kso.file.readwrite / kso.file_search.readwrite / kso.doclib.readwrite / kso.mcp_yundoc.readwrite / kso.airpage.readwrite / kso.airsheet.readwrite

## OpenClaw 官方插件（逆向参考）
- npm：`@wps365/openclaw-wpsxiezuo`（registry.npmmirror.com 下载 tgz 解包即可看源码）
- 结构：dist/core/wps-client.js（KSO-1 签名 + AppAuthProvider Bearer）、dist/tools/oapi/{cloud-doc,dbsheet,airsheet,airpage,calendar,todo,meeting-room}.js（对应 v7 端点）
- 插件配置：openclaw.json → channels.wps-xiezuo {appId, appSecret, baseUrl: https://openapi.wps.cn, accounts:{...}}，用户授权回调 https://365.kdocs.cn/woa/openclaw/callback
- 云文档工具端点即标准 v7：/v7/drives、/v7/drives/{id}/files/{parent}/children、create、request_upload+commit_upload、{file}/content、/v7/files/{id}/meta、/v7/files/search

## KSO-1 签名（私网/接口签名场景）
```
stringToSign = "KSO-1" + method + uri + contentType + dateStr(RFC1123 UTC) + sha256hex(body)
signature = hmacSha256Hex(appSecret, stringToSign)
headers: X-Kso-Date: dateStr, X-Kso-Authorization: "KSO-1 {appId}:{signature}"
```

## AI 助理身份（WPS-key）实测结论
- 创建于 WPS 客户端/工作台「智能体管理」；ID 格式 `ag_<32hex>`，密钥 `apik:<id>.<secret>`，身份类型「用户助理」
- 授权满配（云文档/云盘/IM/会议/表单），但**所有公开网关 401**（openapi REST+MCP 全版本、agentspace.wps.cn、kdocs 网关、oauth2 token 各种 grant）——外部 API 未开放，仅 WPS 自家生态消费；「凭证管理」只有重置按钮，无接入信息
- agentspace.wps.cn = WPS Agentspace（数字员工平台），API 前缀 admin/api/v1|v2、api/v1、api/v2/gpt/、api/v3；用 Bearer 时 401「凭证无效」

## 其他
- kdocs 分享文档「另存为 HTML」只是编辑器壳（无正文），正文需登录态；公开分享文档的 file_id 可从 __WPSENV__ JSON 提取
- 中国大陆网络：npmmirror 拉 npm 包、codeload.github.com 拉 GitHub 源码、阿里云 pypi 镜像
