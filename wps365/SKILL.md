---
name: wps365
description: "Use when integrating WPS 365 / 金山文档 via wps365-cli."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [wps, wps365, kdocs, 金山文档, cloud-docs, cli, oauth2, enterprise]
    related_skills: [google-workspace, notion, hermes-agent]
---

# WPS 365 开放平台接入

## When to use
- 读写 WPS 云文档 / 金山文档内容（读取分析、上传写入）
- 操作多维表格 (dbsheet)、云盘 (drive)、文档库 (doclib)、日历、邮件、IM、会议
- 用户有 WPS 365 企业账号时接入官方能力；无企业账号时说明个人账号走不通官方通道

## Key facts (verified 2026-08)
- **官方为 AI Agent 设计了两条通道**：WPS 365 CLI（推荐，Rust 实现）和 WPS 365 MCP Server（企业试用申请制）
- **硬门槛：必须 WPS 365 企业账号**——个人账号无法在 open.wps.cn 创建「企业自建应用」，权限须企业管理员在 work.wps.cn 审批
- CLI 仓库: `github.com/wps365-open/cli`，安装到 `~/.wps365-cli/bin`；子命令覆盖 7 域: user / calendar / im / mail / drive / dbsheet / meeting，另有 auth / api / spec / provider
- 回调地址固定: `http://localhost:18365/callback`（须在应用安全设置里预注册）

## Onboarding flow（企业账号）
1. **安装 CLI**（见 Pitfalls 的网络 fallback）；`export PATH="$HOME/.wps365-cli/bin:$PATH"` 并持久化到 ~/.zshrc
2. **用户浏览器操作**（唯一暂停点，约 5 分钟）：
   - open.wps.cn/developer 用企业账号登录 → 「企业自建应用」→ 创建应用
   - 基础信息 → 应用凭证：记下 client_id / client_secret
   - 开发配置 → 安全设置 → 回调配置加 `http://localhost:18365/callback`
   - 开发配置 → 权限管理 → 能力权限：申请所需 scope
   - 应用发布 → 版本管理 → 创建版本并提交发布
   - 企业管理员在 work.wps.cn → 应用市场 → 应用审核 审批
3. `wps365-cli auth setup --client-id <id> --client-secret <secret>`（**非交互 flag，直接用，别用 pty**；secret 存系统钥匙串，明文不落盘）
4. `wps365-cli auth login --scopes "<s1>,<s2>"`（本地授权）或 `--device`（设备码流程，headless 可用，自动开浏览器/输出链接）
5. 验证: `wps365-cli auth status` + `wps365-cli user me`（应输出姓名/邮箱）

## 云文档常用 scope
| Scope | 用途 |
|---|---|
| `kso.file.readwrite` | 云文档读写（**含上传下载**）— 核心 |
| `kso.file_search.readwrite` | 按名搜索文件 |
| `kso.drive.readwrite` | 云盘 |
| `kso.doclib.readwrite` | 文档库 |
| `kso.dbsheet.readwrite` | 多维表格增删改查 |
| `kso.file_permission.readwrite` / `kso.file_link.readwrite` / `kso.file_version.readwrite` | 权限 / 分享链接 / 版本 |
| `kso.contact.read` / `kso.calendar.readwrite` / `kso.chat_message.readwrite` / `kso.mail.readwrite` / `kso.meeting.readwrite` | 通讯录 / 日历 / IM / 邮件 / 会议 |

授权类型: **[双]**=用户与应用身份均可用，**[用户]**=仅用户授权，**[应用]**=仅应用身份。同功能 read 与 readwrite 都需时只申请 readwrite（已含读）。

## Pitfalls
- **install.sh（raw.githubusercontent.com）在中国网络常超时/0 bytes**：直接从 GitHub Releases 下载二进制（Apple Silicon 用 `wps365-cli-aarch64-apple-darwin.tar.gz`），解压到 ~/.wps365-cli/bin 并 chmod +x。官方 FAQ 同样推荐此 fallback
- auth setup/login 默认交互式，但**全部支持 flag**——自动化时用 flag，避免后台 pty 无法接收输入
- 权限申请后必须走完「创建版本 → 提交发布 → 管理员审批」，否则一直「待提交审核」不生效
- 通讯录等部分 API 除能力权限外还需配置「可用范围 / 数据权限」
- client_secret 泄露 → 开发者后台立即重置（旧密钥即刻失效）
- 文档站 markdown 源可直接抓取：`https://open-docs.wpscdn.cn/docs-md/zh/<doc-path>.md`（含最新 scope 全表与安装指南）

## References
- `references/open-platform-recon.md` — 开放平台 SPA 侦察方法与已验证的端点/文档 URL（含 MCP 广场、OAuth2 网关行为）
