---
name: pages-to-text
description: 从 Apple Pages 文档（.pages，iWork IWA 二进制格式）中提取正文纯文本，用于合同审查、文档分析等场景。当用户提供 .pages 文件、需要读取 Pages 内容、或 Read 工具无法解析 .pages 时使用。
agent_created: true
---

# Pages 文档提取纯文本

## 适用场景

用户给了 `.pages` 文件（Apple Pages），需要读取其中的正文——尤其是合同、报告、协议等长文档的分析场景。
`.pages` 不是纯文本，Read 工具读不了，`textutil` 也不支持新格式。

## 前置判断

```bash
file xxx.pages        # 期望输出: Zip archive data
```

如果输出是 `Apple binary property list` 或目录，说明是老版本 Pages '09 包格式，走 `textutil -convert txt` 兜底。

## 一行命令

```bash
/Users/xiebojun/.workbuddy/binaries/python/versions/3.13.12/bin/python3 \
  ~/.workbuddy/skills/pages-to-text/scripts/pages_text.py a.pages b.pages
```

脚本会在同目录生成 `a.txt`、`b.txt`，打印字符数。无第三方依赖，纯标准库。

## 原理（改脚本时需要知道）

`.pages` 是 zip，正文在 `Index/Document.iwa` 里：

1. **IWA 容器**：文件头 4 字节魔术 `00 67 78 00`，**其后整个文件是一个完整的 raw-snappy 流**（注意：不是「4 字节长度 + 一块块 snappy」，实测这里是单流。写解析器时先按「整体单流」试，解压出的长度应接近文件大小的 1.5~2 倍）。
2. **raw snappy**：手写解压约 40 行，不需要 `python-snappy`。要点：开头是 varint 形式的「解压后总长度」，之后是 tag 字节，type 0 = literal，1 = 1字节偏移 copy，2 = 2字节偏移 copy，3 = 4字节偏移 copy。**必须校验 `len(out) == length`**，否则说明偏移错了。
3. **protobuf 抽文本**：
   - 正确做法：遍历解压后的字节，凡是 `b & 0x07 == 2`（length-delimited）就试读 varint 长度，切出 chunk 试 `utf-8` 严格解码，只保留含 CJK 的 chunk；然后**外层优先去重**（按起点排序，被前一个已选区间包含的丢弃）。
   - 错误做法（踩过的坑）：边扫边跳到 `j+vl`。这样会在第一个误判的「假字段」处跳过一大段真实内容，导致正文全部丢失。必须先收集候选再筛选。
4. **噪声过滤**：`Document.iwa` 开头有约 40 行日期/月份本地化字符串（一月、二月、星期日、第一季度…）和 `zh_CN`、`gregorian` 等，属正常现象，直接从正文开始读即可。

## 其他文件的作用

| 文件 | 内容 |
|---|---|
| `Index/Document.iwa` | 正文（要的就是这个） |
| `Index/Metadata.iwa` | 文档属性、样式名 |
| `Index/DocumentStylesheet.iwa` | 样式定义 |
| `Index/ViewState.iwa` | 视图状态 |
| `preview.jpg` | 首页缩略图（无 Pages/LibreOffice 时可 OCR 兜底，但信息不全） |

## 环境限制

- macOS 上若无 Pages.app、无 LibreOffice（`soffice`）、无 pandoc，就**只能**用本方案。
- 不要尝试 `pip install snappy` 或 `pyobjc` 走弯路；纯 Python 方案 1 秒内出结果。

## 输出后必做

抽出文本后**先读一遍**确认是完整正文（看开头是否直接进入标题、结尾是否有落款），再开始分析。若字符数明显偏小（例如只有几百字），说明 snappy 流解析有问题，检查 `len(out)==length` 校验。
