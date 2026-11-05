---
name: wps-cloud-docs
description: "Use when 用户要读写 WPS 云文档/金山文档（个人账号、无需企业付费）。"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [wps, kdocs, 金山文档, 云文档, airscript, api, 多维表格]
---

# WPS 云文档接入

## 核心结论（先读，省掉整轮试错）

| 通道 | 状态 | 说明 |
|---|---|---|
| **AirScript 脚本令牌 (APIToken)** | ✅ **个人可用，已验证** | 读写 WPS 云文档，零企业费用，纯 HTTP API |
| WPS 365 CLI (`wps365-cli`) | ✅ 企业账号可用 | 需企业文档服务开通（`interface_company_doc`，可能付费）|
| MCP 云文档端点 | ⚠️ 需企业白名单 | `openapi.wps.cn/mcp/v2/kso-yundoc/message` |
| WPS-key（AI 助理身份）| ❌ 外部 API 未开放 | 40+ 鉴权组合全 401，是给 WPS 自家/OpenClaw 插件用的 |

**关键坑**：`openapi.wps.cn` 的企业文档接口（`/v7/drives`、`/v7/files/*`）需要企业级特权 `interface_company_doc`——企业没开通时**一律 403**，与 scope、数据权限、IP 白名单、接口签名都无关（安全设置解决不了）。企业 web 端能看云文档 ≠ 开放接口可用。MCP 端点同理（企业白名单）。个人订阅用户直接走方案 A。

## 方案 A：AirScript 脚本令牌（个人账号，推荐）

### 原理
WPS 多维表格的脚本编辑器支持「脚本令牌」，外部系统通过 HTTP 执行脚本；脚本内可用全局对象 `KSDrive`（云文档 API）和 `Application`（表格对象）读写文档。

### 接入步骤
1. **创建令牌**：WPS 多维表格 → 脚本编辑器 → 工具栏「脚本令牌」→ 创建（需实名认证）。令牌保存到 `~/.hermes/secrets/airscript.token`（chmod 600）。
2. **部署桥接脚本**：新建脚本，粘贴 `templates/wps-bridge-script.js`（action 分发：list/read/write/create），**必须**在脚本编辑器「服务」菜单添加「云文档API」服务（每个脚本单独添加！），保存。
3. **复制 webhook**：脚本侧边栏「更多」菜单 → 复制 webhook 链接，格式 `https://www.kdocs.cn/api/v3/ide/file/{file_id}/script/{script_id}/sync_task`。
4. **调用**：
```bash
TOKEN=$(cat ~/.hermes/secrets/airscript.token)
curl -s -X POST "$WEBHOOK" \
  -H "AirScript-Token: ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"Context":{"argv":{"action":"list","count":5}}}'
```
返回 `data.result` 为脚本 `return` 的对象；脚本报错在 `data.result.error`（不是顶层 error）。

**调用技巧**：中文文件名/内容多时，用 Python `json.dumps(body, ensure_ascii=False)` 构造 body 再 `subprocess.run(["curl", ...])`，避免 shell 引号/中文编码转义问题（execute_code 内直接 subprocess 调 curl，比 terminal heredoc 稳）。

### 推荐工作流：按文件名定位读取（find_read）

脚本 v3+ 提供 `find_read` action：**webhook 调用只需 `dirUrl`（文件夹 mine 链接）+ `name`（文件名）**，脚本内部 list→按名匹配→openFile(完整 FileInfo)→读 UsedRange.Value，一次完成定位+读取，**无需用户分享文件**：

```bash
curl -s -X POST "$WEBHOOK" -H "AirScript-Token: ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"Context":{"argv":{"action":"find_read","dirUrl":"https://www.kdocs.cn/mine/494061728081","name":"智能餐饮设备对比表.xlsx","sheet":"参数对比表"}}}'
```

**文件夹定位**：dirUrl 需**数字 parentid 的 mine 链接**（`https://www.kdocs.cn/mine/{数字}`），FileInfo 不含 dirUrl、加密 fileId 无法反推——让用户从 kdocs 地址栏复制文件夹链接（每深入一层要一次）。拿到后保存复用，不必每次问。

### KSDrive 速查（脚本内）
- `KSDrive.listFiles({includeExts:['et','ksheet','db','otl','wps','wpp'], count, offset, dirUrl})` → `{files:[{fileName,fileId,createTime,updateTime}], nextOffset}`；**根目录下列出的是文件夹**，深入需 `dirUrl`（`https://www.kdocs.cn/mine/xxx`）
- includeExts 类型：`ksheet`=表格, `et`=WPS表格, `db`=多维表, `otl`=文档, `wps`=WPS文字, `wpp`=演示（无 `ap`）
- `KSDrive.openFile(url或FileInfo)` → File；**两种方式都行**：①分享链接 URL（`https://www.kdocs.cn/l/xxx`）②**完整 FileInfo**（`{fileId, fileName, createTime, updateTime}`，来自 listFiles 的原始对象）——**推荐**，无需用户分享
- **读文件必须用 `.Value`（返回二维数组）**，`.Text` 只返回区域首单元格（封面标题会漏掉整表）；多 sheet 文件默认 ActiveSheet 常是「封面」，**读数据要指定 sheet**（如 `file.Application.Sheets("参数对比表")`，webhook 调用传 argv.sheet）
- **批量写入用 `Range(r).Value = 二维数组`**（write_grid action，一次调用建表，别逐单元格写）
- 真文件 fileId 打开失败的两种真因：①只传了部分 FileInfo 字段（`{fileId,fileName}` 会「权限被拒绝+fileId 乱码」）②目标是**文件夹**（根目录 list 出的多是文件夹，openFile 必败「不支持的文件类型」）
- `file.Application` 只支持 et/ksheet/dbt；**文字文档（doc/docx/wps/otl）内容不可读**（openFile 报「不支持的文件类型」，只能 list 定位）；`file.close()` 必须调用
- `KSDrive.createFile(KSDrive.FileType.KSheet, {name, dirUrl, source})` → 新文件 URL

## 方案 B：WPS 365 CLI（企业账号）

- 安装：GitHub Releases 手动下载二进制（中国网络下 `raw.githubusercontent.com` 常超时；`install.sh` 可从 codeload 源码包提取）
- `wps365-cli config init --new --force`：设备码绑定应用（浏览器 5 分钟），成功输出 `OK: 应用配置成功! App ID: AK...`
- `wps365-cli auth login --device --scopes "..."`：设备码授权，**不依赖回调地址**（回调 localhost:18365 冲突时用 --device）
- scope 需在开发者后台申请 + 发布版本 + 企业管理员审核后才可请求（否则 `invalid_scope: not allowed`）
- `wps365-cli auth token` 可打印当前 access_token（可当 Bearer 直接调 API/MCP）
- CLI spec 本地化在 `~/Library/Application Support/wps365-cli/spec/api.yaml`（含全部 v7 端点与 security scope，查参数/枚举用它）

## 方案 C：kdocs-cli 二进制（个人账号，已验证可上传 PDF）

本机已配置 `kdocs-cli v2.4.0`（路径 `~/.local/bin/kdocs-cli`），个人账号下 **read 与 write 均可**，不依赖企业特权（`interface_company_doc`）。本会话实测可用动作：`search-files`、`drive get-file-info`、`drive upload-file`、`drive move-file`。比 AirScript 更轻，适合"给文件名+目录就存盘"的场景。

### 上传 PDF 的关键坑（400100）
- **新建 PDF 不能带 `parent_id`/`drive_id`**：`drive upload-file` 一传这两个字段就报 `400100 请求参数不支持`。必须**先不带任何目录参数上传到默认位置**，再用 `move-file` 移入目标文件夹。
- 上传最小可用参数：`{"name":"xxx.pdf","content_base64":"<完整PDF的Base64>"}`（不带 drive_id/parent_id）。**二进制 PDF 不要传 `content_format`**（那是给 markdown 源转 docx/pdf 用的；传了反而 400100）。
- 大 base64 内联命令行会被 shell 解析截断/转义出错，**用 `@params.json` 文件传入最稳**：`kdocs-cli drive upload-file @/tmp/p.json`。
- 成功后返回 `data.data.id`（新文件 file_id）、`link_url`。

### 定位「学习」目录并移动（mine 链接数字 ≠ 文件夹 file_id）
- 用户给的 `https://www.kdocs.cn/mine/{数字}` 里的**数字是 mine-link 编号，不是文件夹 file_id**。
- `drive get-file-info '{"file_id":"<mine数字>"}'` → 返回真正的 `id`（形如 `vAEgkYtETxMP...`，即文件夹 file_id）和 `drive_id`。
- `drive move-file` 的 `dst_parent_id` 必须填**文件夹的 file_id（vAEgk...）而非 mine 数字**，否则 400100：
  ```bash
  kdocs-cli drive move-file '{"drive_id":"622596371","file_ids":["<新文件id>"],"dst_drive_id":"622596371","dst_parent_id":"<文件夹file_id>"}'
  ```
  返回 `task_ids:[]` 即成功（同步移动）。
- `drive list-files` 返回结构是 `data.data.items[]`（不是 `files[]`）；必填 `drive_id`+`parent_id`+`page_size`，`parent_id` 用文件夹 file_id（根目录 `"0"`）。
- `search-files` 只需 `keyword`（可选 drive_id/parent_id），返回 `items[]`；子文件 drive_id 可能与文件夹 drive_id 不同，但 move/upload 用文件夹的 drive_id 即可。

### 生成 PDF 的无 pandoc 方案（本机 macOS）
本机无 pandoc/weasyprint/wkhtmltopdf，但装了 **Google Chrome** → 走 `markdown→HTML(CSS 内联)→Chrome --headless --print-to-pdf`：
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --no-sandbox --disable-gpu --no-pdf-header-footer --print-to-pdf=out.pdf "file:///tmp/x.html"
```
HTML 用 Python 正则把 `#/##/###、|表格|、- 列表、**粗**、\`代码\`` 转成带 `@page{size:A4}` 与中文字体的样式即可；CSS 引 `"PingFang SC","Microsoft YaHei"` 保证中文不缺字。

## 文字文档（doc/docx/wps/otl）读取——已穷尽所有个人通道（2026-08 实测）

**结论：个人免费通道下 doc/docx 内容直读无官方 API。** KSDrive 只支持表格类；除 AirScript 外所有 openapi 通道都被企业级限制挡住：

| 路径 | 阻塞 | 详情 |
|---|---|---|
| openapi 企业域 `/v7/drives`、`/v7/files`（含 CLI drive 命令、`drive file-content get` 文档内容抽取）| `interface_company_doc` | 企业文档特权，付费开通 |
| MCP 云文档 `extract_yundoc_content`（Markdown 提取）| 企业白名单 | `Company ID ... not in MCP company whitelist` |
| aiopen AI 文档处理域（`/v7/aiopen/*`：doc_operate_tasks table_extraction/summarize/content_extraction/file_parse、drives/qa、ref_files/parse）| drive_id 卡点 | app token 鉴权**可通过**（`--token-type app` 返回参数错误而非 403），但所有文件接口要 `drive_id`，其获取通道（`/v7/drives`）被企业特权挡；部分端点（ref_files/parse、resource/files/request_upload、drives/qa）网关 404 未注册；`/v7/aiopen/files/search` 已注册但需 drive_ids |
| kdocs 分享链接下载（`/api/v3/office/file/download`）| 需授权 token | 端点存在（403 非 404）但分享页是登录壳，需逆向 grant_token 授权链，成本高 |
| AirScript KSDrive | 类型限制 | `File.Application` 只支持 et/ksheet/dbt |

**务实替代（用户接受，一次手动永久自动化）**：
1. **docx→表格「搬家」**：用户 kdocs 打开 docx → 全选复制 → 新建智能表格/表格粘贴 → 保存 → 之后全自动读写（同《智能餐饮设备对比表》工作流）
2. **本地解析 + 云端写回**：用户下载 docx 到本地 → python-docx 解析 → 分析 → AirScript `write_grid` 写回云文档表格

## 常见错误速查

| 错误 | 含义 | 处理 |
|---|---|---|
| `ErrPrivileges: interface_company_doc` | 企业未开通文档开放服务 | 换方案 A 或让企业付费开通 |
| `not in the MCP company whitelist` | 企业不在 MCP 白名单 | 企业填 MCP 试用表单，或换方案 A |
| `invalid_scope: ... not allowed` | 应用没申请/没审核该 scope | 开发者后台申请+发布+管理员审核 |
| `高级服务:云文档 未添加!` | 脚本没添加云文档API服务 | 脚本编辑器→服务→添加云文档API→保存 |
| `不支持的文件类型` | openFile 目标是**文件夹**或**文字文档**（doc/docx/wps/otl），或传了纯 fileId 字符串 | 文件夹/文字文档本就不可开；真文件用完整 FileInfo 或分享链接 |
| `权限被拒绝, fileId: <乱码>` | FileInfo 字段不全（只传 fileId+fileName）| 用完整 FileInfo（listFiles 原始对象）或分享链接 |
| `access token validation failed` | Bearer 不是有效 token | 用 CLI `auth token` 或 OAuth 换 token |

## 研究捷径（下次不用重新挖）
- 文档站 markdown 源：`https://open-docs.wpscdn.cn/docs-md/zh/<文档路径>.md`（SPA 页面正文抓不到时直接拼这个）
- 文档树 API：`https://open.wps.cn/docs/api/collections/{guide|wps365|mcp-server|...}?lang=zh`（返回完整目录树）
- OpenClaw 官方插件 `@wps365/openclaw-wpsxiezuo`（npm，npmmirror 下载）源码 = 官方 API 调用逻辑（KSO-1 签名 + OAuth Bearer + v7 端点），可逆向参考
- KSO-1 签名：`X-Kso-Date`(RFC1123) + `X-Kso-Authorization: KSO-1 {app_id}:{hmac_sha256_hex("KSO-1"+method+uri+contentType+date+sha256(body), appSecret)}`

## 支持文件
- `templates/wps-bridge-script.js` — 已验证的桥接脚本 **v4.2**（actions：list / **find_read** / read / write / **write_grid** / create；读取用 .Value 二维数组，支持 sheet 参数）
- `scripts/kdocs_upload_pdf.sh` — 一键把本地 PDF 上传到指定 mine 数字目录（自动 get-file-info 取 file_id、upload-file 不带目录、move-file 进目标文件夹），避免 400100 坑
- `scripts/ocr_vision.swift` — macOS Swift+Vision 截图 OCR（zh-Hans，vision_analyze 不可用时读中文截图）
- `references/api-research.md` — WPS 开放平台调研笔记（端点、权限模型、插件发现）
