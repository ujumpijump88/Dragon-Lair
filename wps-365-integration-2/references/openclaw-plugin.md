# WPS 协作 OpenClaw 官方插件（调研记录）

来源：官方插件指南文档（kdocs 短链 cnO3PU3devdH，公开分享）+
npm 包 `@wps365/openclaw-wpsxiezuo` v1.12.0 源码（npmmirror 下载 tarball）。

## 定位

OpenClaw（开源 AI Agent 框架，openclaw.ai）的官方 channel 插件：让 OpenClaw 通过
WPS 协作机器人收发消息，并附带 skills（云文档/多维表/智能表格/日历/待办/会议室）。
**其云文档 skills 调用的就是 openapi.wps.cn 标准 v7 端点** —— 印证「应用凭证 + 用户 OAuth」模型，
插件能做的 CLI/API 都能直接做，无需装 OpenClaw。

## 安装（文档版）

```bash
npx -y @wps365/openclaw-wpsxiezuo install
npx -y @wps365/openclaw-wpsxiezuo install --app-id <APP_ID> --app-secret <APP_SECRET> --yes
npm install -g @wps365/openclaw-wpsxiezuo --registry=https://registry.npmmirror.com
# 卸载
npx -y @wps365/openclaw-wpsxiezuo uninstall
```
装完需 `openclaw gateway restart`。

## 应用准备（fastapp 一键）

- 一键创建/配置应用：`https://365.kdocs.cn/woa/openclaw/fastapp`（自动申请插件所需权限点）
- 或开发者后台创建，手动申请权限 + 事件：
  - 事件（必须）：`kso.app_chat.message.create`（机器人接收消息）、`kso.developer.application.auth_code.create`（应用授权码创建）
  - 用户授权回调地址（V1.10.1 起）：`https://365.kdocs.cn/woa/openclaw/callback`
- 应用需企业管理员审核通过才生效（自动申请发布）。

## channel 配置（~/.openclaw/openclaw.json）

```json
"channels": { "wps-xiezuo": {
  "enabled": true,
  "appId": "<APP_ID>", "appSecret": "<APP_SECRET>",
  "baseUrl": "https://openapi.wps.cn",
  "defaultAccountId": "default",
  "accounts": { "default": {}, "wps-xiezuo-1": { "appId": "...", "appSecret": "..." } },
  "dmPolicy": "pairing"   // pairing|allowlist|open|disabled，与 Hermes DM policy 同概念
}}
```
多机器人 → 多 agent：`agents.list` 定义多 agent + `bindings` 按 accountId 路由，
`session.dmScope: "per-account-channel-peer"` 隔离会话。

## 插件源码要点（dist/tools/oapi/*）

- 云文档端点与 SKILL.md 主文一致（/v7/drives、children、create、request_upload+commit_upload、content、meta、/v7/files/search）
- 鉴权 Provider：公网 `AppAuthProvider`（Bearer 用户/应用 token）+ `UserAuthProvider`（用户 delegated token，回调拿 access_token/refresh_token，自动续期）；私网 `KsoAuthProvider` / `PrivateNetworkAuthProvider`（KSO-1 签名）
- 用户 token 按 `accountId:wpsUserId` 隔离存储，过期前 5 分钟自动 refresh

## 更新日志要点（skills 演进）

- V1.6.1：云文档（创建/查询/搜索/读内容）、日历、待办；新增用户授权（/wpsxiezuo auth）
- V1.8.1：智能文档编辑、多维表、会议室、**本地文件上传为云文档**；npm 安装方式
- V1.9.0：智能表格；V1.11.x：多机器人多 agent 修复、原生指令、超时移除
