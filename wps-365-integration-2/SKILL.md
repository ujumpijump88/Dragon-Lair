---
name: wps-365-integration
description: "Integrate WPS 365 cloud docs: CLI, auth, API, permissions."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [wps, wps365, 金山文档, kdocs, openapi, cloud-doc, integration, mcp, openclaw]
---

# WPS 365 / WPS 云文档 接入

把 Hermes 接进 WPS 365 开放平台（企业版云文档/多维表/日历/IM）。核心事实：官方有 CLI（github.com/wps365-open/cli）、MCP server（openapi.wps.cn/mcp/v2）、OpenClaw 插件（npm `@wps365/openclaw-wpsxiezuo`），全部走同一个网关 `openapi.wps.cn` + OAuth。用户已有 WPS 365 企业账号。

## 已验证可用的接入流程（CLI）

1. **安装**：raw.githubusercontent.com 的 install.sh 在中国网络常超时 → 从 GitHub Releases 手动下载二进制（`wps365-cli-aarch64-apple-darwin.tar.gz`，arm64 Mac）解压到 `~/.wps365-cli/bin`，PATH 加进 ~/.zshrc。验证 `wps365-cli version`。
2. **绑定应用**（设备码，5 分钟过期，用 background 进程跑）：
   `wps365-cli config init --new --force` → 输出浏览器链接 + user_code → 用户浏览器登录企业账号创建应用 → CLI 自动写 client_id，secret 存钥匙串。
3. **用户授权**（设备码，10 分钟过期，**无需回调地址**）：
   `wps365-cli auth login --device --scopes "<逗号分隔 scope>"` → 用户浏览器确认 → delegated token 落盘（2h 有效，自动 refresh）。
4. **验证**：`wps365-cli user me` 返回用户信息即通。

## 权限模型（最大的坑）

开放平台 4 维权限：访问凭证（AK/SK）、API 权限（scope）、可用范围、数据权限。

- **config init 创建的应用默认无任何 scope** → auth login 报 `invalid_scope`。须在开发者后台 open.wps.cn/developer → 权限管理 申请 scope → 发布版本 → **企业管理员审核**。
- **企业文档接口（/v7/drives、/v7/files/search 等）报 403 `interface_company_doc`，MCP 报 `Company ID xxx is not in the MCP company whitelist` = 租户级「企业文档开放服务」未开通**（需付费企业认证/WPS 365 企业版订阅）。实测：scope 全部开通、IP 白名单未配、web 端云文档可用，接口仍 403；MCP 错误直接点名企业不在白名单。安全设置（IP 白名单/KSO-1 签名/H5 域名）**无法解决**——这是服务开通不是请求校验。先试：权限管理配置数据权限（全部成员/部门）+ 发布 + 管理员审核（可能仍不充分）；最终解法是企业侧申请（MCP 试用表单 https://f.kdocs.cn/ksform/w/write/KrrG1pwZ 或联系商务）。**个人订阅用户不想再付费 → 走 AirScript 脚本令牌（下节）**。
- 常用 scope：`kso.drive.readwrite` `kso.file.readwrite` `kso.file_search.readwrite` `kso.doclib.readwrite` `kso.dbsheet.readwrite` `kso.airpage.readwrite` `kso.airsheet.readwrite` `kso.user_base.read`。

## 云文档 API（官方 OpenClaw 插件源码实证）

- 盘列表 `GET /v7/drives?allotee_type=user&page_size=N`
- 子文件 `GET /v7/drives/{drive_id}/files/{parent_id}/children`
- 新建 `POST /v7/drives/{drive_id}/files/{parent_id}/create`
- 上传 `POST .../request_upload` + `.../commit_upload`
- 读内容 `GET /v7/drives/{drive_id}/files/{file_id}/content`
- 元信息 `GET /v7/files/{file_id}/meta`
- 搜索 `GET /v7/files/search?keyword=&type=all&page_size=N`（**type 必填**；中文 keyword 必须 URL 编码否则 400）
- 鉴权：`Authorization: Bearer <delegated_token>`；私网环境另加 KSO-1 签名（算法见 references/wps-api-notes.md）

## MCP（Agent 通用接入）

`https://openapi.wps.cn/mcp/v2/<tool>/message` + `Authorization: Bearer <token>`（Streamable HTTP，JSON-RPC）。工具域：kso-yundoc（云文档：搜索/提取内容）、kso-calendar、kso-dbsheet(-app)、kso-message(-app)、kso-mail、kso-meeting、kso-airpage、kso-todo、kso-scenario。文档在 open.wps.cn/documents 的 mcp-server 集合。

## AirScript 脚本令牌（个人级零付费通道）⭐ 企业文档被挡时的出路

企业文档接口（`interface_company_doc` / MCP 企业白名单）需要付费开通时，**个人订阅用户**可以用 AirScript 脚本令牌走 kdocs 个人通道读写云文档（纯 HTTP API，非本地同步）：

- **创建**：WPS 多维表格 → 脚本编辑器 → 工具栏「脚本令牌」→ 创建（需实名认证，个人产品零费用）。
- **调用**：`POST https://www.kdocs.cn/api/v3/ide/file/{file_id}/script/{script_id}/sync_task`，Header `AirScript-Token: <token>`，Body `{"Context":{"argv":{...}}}`。file_id + script_id 从脚本编辑器侧边栏脚本「更多」菜单复制的 webhook 链接里拿。
- **脚本内 KSDrive API**：`KSDrive.listFiles({includeExts:['et','ksheet','db','ap'], offset, count, dirUrl})` 列文件；`KSDrive.openFile(url)` → `file.Application.ActiveSheet.Range('A1').Text` 读 / `.Value = x` 写，用完 `file.close()`；`KSDrive.createFile(KSDrive.FileType.ET|KSheet|DB|AP, {name, dirUrl, source})` 创建/另存。
- **桥接脚本模板**：`templates/wps-bridge-script.js`（list/read/write/create 四操作，argv 传参），部署到脚本编辑器后外部通过 webhook + AirScript-Token 调用；详见 `references/airscript.md`。
- 注意：KSDrive FileType 覆盖表格/多维表/智能文档（AP）；传统 docx 文字文档未确认支持。

## WPS-key（AI 助理身份）⚠️ 别浪费时间探测

WPS 客户端 工作台→智能体管理 创建的「AI 助理身份」：ID `ag_*`，密钥 `apik:*`，授权满配（云文档/云盘/IM/会议/表单）。**截至 2026-08 外部 API 通道未开放**：openapi.wps.cn（REST+MCP）、agentspace.wps.cn、kdocs 系网关全部 401/403「凭证无效」。真正可用的是「开放平台应用 + 用户 OAuth」。

## 文档/源码侦察技巧

- open.wps.cn/documents 是 SPA；markdown 源在 `open-docs.wpscdn.cn/docs-md/zh/<path>.md`；文档树 API：`open.wps.cn/docs/api/collections` 和 `open.wps.cn/docs/api/collections/<id>?lang=zh`（拿全部文档路径）。
- 官方 OpenClaw 插件 npm 包 `@wps365/openclaw-wpsxiezuo`（npmmirror 下载 tarball 看 dist/ 源码）可实证真实 API 端点、鉴权头、scope 依赖。
- GitHub：org `wps365-open`（cli）、org `openclaw`（openclaw.ai）；OpenClaw 插件文档短链在 365.kdocs.cn（需登录态）。

## Pitfalls

- raw.githubusercontent.com 下载超时 → 用 GitHub Releases 或 codeload.github.com。
- macOS 无 `timeout` 命令；交互流程（config init / auth login）用 background + process poll 拿链接。
- CLI `api get` 传中文参数要 URL 编码（用 `--query key=value` 可重复传），否则 400。
- 设备码 5/10 分钟过期，过期重跑即可；`--device` 是 headless 友好的（链接可在其他设备打开）。
- oauth2/token 必须 `application/x-www-form-urlencoded`（JSON 报 415）。

详细端点、KSO-1 签名算法、OAuth 细节、错误码表：`references/wps-api-notes.md`
AirScript 脚本令牌完整工作流（官方文档提炼 + 调用示例）：`references/airscript.md`
OpenClaw 官方插件指南要点（fastapp 一键建应用、回调地址、事件订阅、channel 配置）：`references/openclaw-plugin.md`
云文档桥接脚本（可粘贴到多维表格脚本编辑器）：`templates/wps-bridge-script.js`
