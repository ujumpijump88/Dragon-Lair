# AirScript 脚本令牌（APIToken）— 个人级 WPS 云文档读写

官方文档来源：open.wps.cn/documents 的 guide/dbsheet/AirScript/script-token 系列
（markdown 源：open-docs.wpscdn.cn/docs-md/zh/app-integration-dev/guide/dbsheet/AirScript/script-token/*.md）

## 是什么

脚本令牌（APIToken）= 外部系统执行 AirScript 脚本的 HTTP 凭证。创建于 **WPS 多维表格**（个人产品，无需企业版），**实名认证后即可创建，零费用**。脚本可读取/写入多维表格数据，并通过 KSDrive 对象读写云文档（表格/智能表格/多维表/智能文档）。

## 创建步骤

1. 打开 WPS 多维表格 → 脚本编辑器
2. 工具栏点「脚本令牌」→ 勾选「我已知晓」→ 创建脚本令牌（未实名认证会先要求实名）
3. 复制令牌值妥善保存（即 `AirScript-Token` 请求头的值）

## 外部调用（同步执行）

```
POST https://www.kdocs.cn/api/v3/ide/file/{file_id}/script/{script_id}/sync_task
Header:
  Content-Type: application/json
  AirScript-Token: <脚本令牌>
Body:
  {"Context":{"argv":{"action":"read","url":"...","range":"A1"}}}
```

- `file_id` + `script_id`：脚本编辑器侧边栏 → 脚本「更多」菜单 → 复制 webhook 链接，形如
  `https://www.kdocs.cn/api/v3/ide/file/caEkI6K5RDG2/script/V2-5rSiBiN7y5xdOd5x5ZYI2r/sync_task`
- `Context.argv`：任意 JSON 对象，脚本内通过 `Context.argv.xxx` 读取（这是桥接脚本的入参通道）
- 另有异步接口 `async_task`（返回 task_id 后轮询 logs），耗时脚本用
- 返回：`{data:{result, logs[]}, status}`；`result` 是脚本 `return` 的对象

## KSDrive 云文档 API（脚本内）

先要在脚本编辑器「服务」菜单添加「云文档API」服务。

| 能力 | API |
|---|---|
| 列文件 | `KSDrive.listFiles({includeExts:['et','ksheet','db','ap'], offset, count, dirUrl})` → `{files:[{fileName,url,fileId}], nextOffset}`（options 省略 = 我的云文档目录） |
| 打开文档 | `KSDrive.openFile('https://www.kdocs.cn/l/xxx')` → File 对象，用完必须 `file.close()` |
| 读内容 | `file.Application.ActiveSheet.Range('A1').Text`（选表：`file.Application.Sheets(name)`） |
| 写内容 | `file.Application.ActiveSheet.Range('A1').Value = 'x'` |
| 创建/另存 | `KSDrive.createFile(KSDrive.FileType.ET, {name, dirUrl, source})` → 返回新文件 url |
| 文件类型 | `KSDrive.FileType` = AP(智能文档)/KSheet(智能表格)/ET(表格)/DB(多维表) |

多维表格自身数据：`Application.ActiveView.RecordRange(r,c).Value`（脚本运行所在表）；argv 传 `sheet_name` / `range` 指定上下文。

## 桥接脚本（模板 templates/wps-bridge-script.js）

argv 协议（通过 `{"Context":{"argv":{...}}}` 传入）：

| action | 参数 | 说明 |
|---|---|---|
| `list` | exts?/count?/offset?/dirUrl? | 列云文档（默认 et,ksheet,db,ap） |
| `read` | url + range? + sheet? | 读单元格/区域文本 |
| `write` | url + range + value + sheet? | 写单元格 |
| `create` | type?(ET/KSheet/DB/AP) + name? + dirUrl? | 新建文档，返回 url |

脚本结构注意：AirScript 是顶层语句 + `return {...}` 风格（不是 function main 包装），`Context` 是全局对象。

## 状态

- 截至 2026-08：桥接脚本已写好（~/Hermes/wps-bridge-script.js）待用户部署（粘贴到脚本编辑器 + 提供令牌/webhook 后实测）。方案基于官方接口文档，端点/Header/Body 均来自官方文档，尚未端到端验证。
