---
name: wps-airscript-bridge
description: "读写 WPS 云文档用 AirScript 桥接（list/read/write/create，个人免付费）。"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [wps, kdocs, airscript, cloud-doc, apitoken, bridge]
---

# WPS 云文档桥接（AirScript 脚本令牌）

用 WPS 多维表格的 **AirScript 脚本令牌（APIToken）** 通过 HTTP API 读写 WPS 云文档（kdocs）。
个人级方案：WPS 会员 + 实名认证即可，**无需企业付费**（企业开放平台接口 `interface_company_doc` 需企业开通 WPS 365 企业文档服务，个人不适用）。

## 何时使用

- 用户要求读取/写入/创建 WPS 云文档（kdocs）内容
- 用户没有 WPS 365 企业文档服务（403 `interface_company_doc` / MCP company whitelist）
- 明确排除本地同步文件夹方案

## 前置条件（一次性配置）

1. **脚本令牌**：WPS 多维表格 → 脚本编辑器 → 工具栏「脚本令牌」→ 创建（需实名认证）→ 保存到 `~/.hermes/secrets/airscript.token`
2. **桥接脚本**：`wps-bridge-script.js`（本技能 scripts/ 下）粘贴到脚本编辑器，添加「云文档 API」服务（KSDrive），保存
3. **webhook 链接**：脚本侧边栏「更多」→ 复制 webhook 链接（`https://www.kdocs.cn/api/v3/ide/file/{file_id}/script/{script_id}/sync_task`），保存到 `~/.hermes/secrets/airscript-webhook.txt`

## 调用方式

```bash
TOKEN=$(cat ~/.hermes/secrets/airscript.token)
WEBHOOK=$(cat ~/.hermes/secrets/airscript-webhook.txt)
curl -s -X POST "$WEBHOOK" \
  -H "AirScript-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"Context":{"argv":{"action":"list","count":5}}}'
```

返回 `data.result`（JSON 字符串，需二次 parse）。

## 桥接脚本操作（argv 参数）

| action | 参数 | 说明 |
|---|---|---|
| `list` | exts(可选,默认 et,ksheet,db,ap), count, offset, dirUrl | 列出目录文件（dirUrl 为 `https://www.kdocs.cn/mine/{数字id}` 文件夹链接，需用户从地址栏复制；FileInfo 无 dirUrl）|
| `find_read` | dirUrl + name(+sheet/range可选) | **按文件名在目录定位并读取**（脚本内 list→匹配→openFile 完整 FileInfo），免分享链接 |
| `read` | url(分享链接) 或 fileId+name, range(可选,默认 UsedRange) | 读取内容，`UsedRange.Value` 返回**二维数组**（.Text 只返回首单元格）|
| `write` | url 或 fileId + range + value | 写入单单元格（value 可为空字符串清空）|
| `write_grid` | url 或 fileId + range + grid(二维数组) | **批量写入整个区域**（一次调用写全表）|
| `create` | type(ET/KSheet/DB/AP), name, dirUrl, source | 创建新文档，返回 url；dirUrl 指定存放文件夹 |

## 关键坑（实测）

- **openFile 用完整 FileInfo 或分享链接 URL**：`find_read`（list→匹配→openFile(完整 FileInfo)）实测可行；fileId 字符串直接 openFile 报「不支持的文件类型」；字段不全的 FileInfo 报「权限被拒绝+乱码 fileId」
- **读取用 `.Value`（二维数组）**，`.Text` 只返回区域首单元格（之前误读成标题行）
- includeExts 支持：ksheet(表格), et(WPS表格), db(多维表), **otl(文档), wps(WPS文字), wpp(演示)**——AP 不在官方列表
- `File.Application` 操作对象只支持 et/ksheet/dbt；**doc/docx/wps 文字文档内容读取不支持**（只能列出）
- list 根目录/文件夹返回的是**文件夹+文件混合**（无类型标记，需 openFile 试）；文件夹 openFile 失败
- **文件夹定位需要用户提供 dirUrl**（`https://www.kdocs.cn/mine/{数字parentid}` 地址栏链接），FileInfo 无 dirUrl、fileId 是加密 id 无法转换
- 脚本改动后必须保存（webhook 执行已保存版本）；服务（云文档API）需在脚本编辑器「服务」按钮添加，每个脚本单独添加
- 响应 `data.result` 是字符串化的 JSON，解析时先 json.loads
- 脚本执行返回 `status: finished` + `data.result`；`error` 字段非空表示执行错误

## 验证流程

1. `list` → 确认能列出文件
2. `find_read`（dirUrl+name）→ 确认读到二维数组
3. `write_grid`（新表格 A1:C21 写入）→ `read` 回读验证 → 清理
4. `create` → 返回 url → `read` 该 url 确认可打开

全部流程已实测通过（2026-08-08）：list/find_read/read/write/write_grid/create ✅

## 参考

- 官方文档：`open.wps.cn/documents/app-integration-dev/guide/dbsheet/AirScript/script-token/AirScript-apitoken-api`（接口）、`AirScript-advanced-KSDrive`（云文档 API）
- 相关：WPS 365 CLI（`wps365-cli`，~/.wps365-cli/bin）企业通道可用但云文档接口受 `interface_company_doc` 限制
