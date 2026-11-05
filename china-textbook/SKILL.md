---
name: china-textbook
description: "Use when 需引用教材原文或下载教材PDF。从 ChinaTextbook 教材库按学科/年级/版本定位下载。"
---

# 教材库调用（TapXWorld/ChinaTextbook）

辅导/教学任务需**精确引用教材定义、定理、例题、习题原文**时（避免凭记忆讲错），从 GitHub 开源教材库 `TapXWorld/ChinaTextbook`（81k★，覆盖小学/初中/高中/大学 PDF 教材）按需定位并下载 PDF。

- 仓库主页：https://github.com/TapXWorld/ChinaTextbook
- 配套工具库：https://github.com/TapXWorld/ChinaTextbook-tools （mergePDFs 合并拆分文件）
- 内地网络重新下载：https://github.com/happycola233/tchMaterial-parser

## 目录结构

```
仓库根/
  小学/ 初中/ 高中/ 大学/
    初中/<科目>/<版本>/<年级>/义务教育教科书·<科目><年级><上|下册|全一册>.pdf
```

- 年级目录名：`七年级` / `八年级` / `九年级`（小学 `一年级`…`六年级`）。
- 物理通常只有八、九年级（初二开课）；化学通常只有九年级（初三开课）。
- 语文常为「统编版」，其他科多为「人教版」——务必先列目录确认版本名，不要猜。
- 已实测的初三五科→版本→九年级映射见 `references/chu-san-renjiao-mapping.md`。

## 定位方法（首选 GitHub API 列目录，不猜路径）

路径含中文和 `·`，必须先 URL 编码。用 `jq` 提取文件名：

```bash
enc(){ python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"; }
e=$(enc "初中/数学/人教版-人民教育出版社/九年级")
curl -s "https://api.github.com/repos/TapXWorld/ChinaTextbook/contents/$e" | jq -r '.[].name'
```

有 `gh` 且已登录时更省事（自动处理编码，限速 5000/h）：

```bash
gh api "repos/TapXWorld/ChinaTextbook/contents/初中/数学/人教版-人民教育出版社/九年级" --jq '.[].name'
```

## 下载方法

raw 直链：`https://raw.githubusercontent.com/TapXWorld/ChinaTextbook/master/<URL编码路径>`（默认分支 `master`）：

```bash
e=$(enc "初中/物理/人教版-人民教育出版社/九年级/义务教育教科书·物理九年级全一册.pdf")
curl -sL "https://raw.githubusercontent.com/TapXWorld/ChinaTextbook/master/$e" -o "物理九年级全一册.pdf"
```

- 下载后存固定目录（如 `~/textbooks/`）复用，避免重复下载。
- 教材为扫描/电子 PDF，用 `pdf` 或 `ocr-and-documents` 技能提取文字后再引用。
- 只下所需年级的册，不要整库 clone（整库数 GB）。

## 拆分文件处理（>50MB 的文件）

GitHub 单文件限 100MB、超 50MB 警告，故大文件被拆成 35MB 块，命名 `xxx.pdf.1`、`xxx.pdf.2`。定位到目录若见 `.1/.2` 后缀，先合并再用：

```bash
# macOS/Linux：按顺序 cat 拼接即可（简单二进制 split）
cat "xxx.pdf.1" "xxx.pdf.2" > "xxx.pdf"
```

Windows 环境才用配套 `mergePDFs-windows-amd64.exe`（放同目录双击自动合并）；macOS 直接 `cat`，无需该 exe。

## 注意事项

- 中文路径 + `·` 特殊字符务必 URL 编码，否则 404。
- GitHub API 未认证限速 60 次/小时，`gh auth login` 后 5000 次/小时；批量操作优先用 gh。
- 教材为公开开源资源，仅供学习辅导引用，注意版权合规使用。
