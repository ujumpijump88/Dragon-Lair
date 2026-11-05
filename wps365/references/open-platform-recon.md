# WPS 开放平台侦察备忘（2026-08 实测验证）

## 文档/门户架构
- 门户 open.wps.cn 与 developer.kdocs.cn 返回**同一 SPA 壳**（bundle: cloudcdn.qwps.cn/open/web_open-homepage/index-*.js，约 10MB；文档站 bundle: cloudcdn.qwps.cn/open/doc-app-web/assets/index-*.js，约 21MB）。curl 只能拿到壳 HTML
- **文档站 markdown 源可直接抓**：`https://open-docs.wpscdn.cn/docs-md/zh/<doc-path>.md`。文档页 HTML 的 href 里直接带 .md 源链接，例：
  - `cli/wps365-cli-installation-guide.md` — 完整安装指南（含 7 域全 scope 表、浏览器操作清单、FAQ）
  - `app-integration-dev/mcp-server/introduction.md` — MCP 介绍（企业试用申请制）
- 开发者后台: open.wps.cn/developer（应用管理）、account.wps.cn/usercenter/apps；企业管理后台: work.wps.cn
- API 网关: openapi.wps.cn
  - `/oauth2/token` 存在但 **只收 application/x-www-form-urlencoded**——发 JSON 返回 `{"code":41500001,"msg":"Content-Type unsupported"}`
  - `/oauth2/device/verify` 存在（GET 返回授权错误页，说明设备码流程已实现）
  - 常规 REST 路径探测（openapi/v1/file/list 等）均 404——端点不暴露给未认证请求

## SPA 侦察方法（可复用于其他厂商门户）
1. `curl -sL <portal>` 拿壳 HTML → `grep -oE '(src|href)="[^"]*"'` 找 js bundle URL
2. 下载 bundle（10-20MB）→ `grep -oE 'https?://[a-zA-Z0-9./_-]*' | sort -u` 提取 URL 全集
3. 关键词定位：`grep -oE '.{0,150}<keyword>.{0,200}'`（如 'mcp'、'Covers 7 business domains'）看功能入口与描述
4. 顺藤摸瓜：bundle 里的 URL → 文档页 → .md 源 → GitHub 仓库 → releases 二进制
5. 端点探测：常见路径 + 注意 405 表示端点存在但方法/Content-Type 不对

## MCP（官方）
- WPS 365 MCP Server 官方存在（文档站 /documents/mcp 广场，列表经 API 加载）
- 试用申请表单: https://f.kdocs.cn/ksform/w/write/KrrG1pwZ（企业向）
- 个人/无企业账号走不通 MCP 通道

## 已发现的资源清单
- CLI 仓库: https://github.com/wps365-open/cli（v0.3.1，Rust/Go，166 stars，2026-08 仍在更新）
- Release 二进制: github.com/wps365-open/cli/releases/download/v0.3.1/wps365-cli-{aarch64-apple-darwin|x86_64-apple-darwin|...}.tar.gz
- 能力描述原文: "Covers 7 business domains including Calendar, IM, Mail, Cloud Docs, Spreadsheets, and Meetings. Developers and AI Agents can invoke via shell directly without SDK integration."
