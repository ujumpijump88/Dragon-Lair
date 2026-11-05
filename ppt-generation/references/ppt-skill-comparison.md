# PPT 技能实测对比（2026-08，本机验证）

同一主题「AI 大模型应用实践」11 页，分别用 qoderwork-ppt 与 bundled powerpoint 技能实际生成、schema 校验、渲染对比。

## 实测结果表

| 维度 | qoderwork-ppt | powerpoint（bundled） |
|------|--------------|----------------------|
| 安装 | OSS zip → ~/.hermes/skills；npm 185 包 2s（npmmirror） | 内置；需另装 pptxgenjs + react-icons + sharp |
| 生成流程 | 一次成功：validate→fill→pptx 三步（含 11 页 HTML 填充） | 手写 JS 脚本，调试 3 轮（react-icons v5 API 变化） |
| 文件有效性 | ZIP 有效 + validate.py PASSED | ZIP 有效 + validate.py PASSED |
| 内容完整性 | 11 页全，字符数与输入一致 | 11 页全（注意：圆圈编号+文字里重复章节号会显得冗余） |
| 视觉质量 | 模板化统一风格（14 模板，1920×1080），中文原生（PingFang/雅黑）；文件 ~4.9MB（内嵌高清背景） | 自绘，质量取决于脚本设计；文件 ~250KB |
| 已知缺陷 | 目录页 <5 章泄漏英文占位符 `0X I am the chapter name`（空串也无法清除） | 本机无 LibreOffice → 技能要求的 soffice 视觉 QA 链路不可用 |
| 定制能力 | 固定绿色风格，改样式需改 HTML 模板 | 任意主题色/布局，完全可控 |
| 图片 | 规则要求左文右图/全图页必须真实配图；fill-template 将图片**内联为 base64** | 需自行准备图片 |

## 决策

- **主力 = qoderwork-ppt**：开箱即用、模板精美、流程自动化、一次成功；适合"快速生成好看的中文 PPT"。
- **powerpoint 技能保留**为深度定制场景（品牌色、特殊图表、编辑模板）；本机缺 LibreOffice 是其主要短板。
- pptx-author（`hermes skills install official/finance/pptx-author`）：金融场景专用，未装。

## 验证命令模式（固化为 npm run test → scripts/verify.sh）

```bash
# 1. 语法
node --check generate-deck.js && python3 -m py_compile analyze-decks.py
# 2. 重建 qoderwork（⚠️ cwd = output/ 所在项目根）
( cd project && node ~/.hermes/skills/qoderwork-ppt/scripts/run-pipeline.js output/slides.json output/presentation.pptx )
grep -qiE "not found|error" log && fail   # 图片路径警告检测
grep -q 'data:image/jpeg;base64' output/filled/slide-05-*.html && pass  # 内联图片检测（勿 grep 文件名）
# 3. 重建 pptxgenjs deck
node render-icons.mjs && node generate-deck.js
# 4. schema 校验（两份）
~/Hermes/.venv/bin/python ~/.hermes/skills/productivity/powerpoint/scripts/office/validate.py deck.pptx | grep PASSED
# 5. zip + 产物清点
unzip -t deck.pptx && [ "$(ls output/filled/*.html | wc -l)" = "11" ]
# 6. 内容分析：zipfile 提取每页 <a:t> 文本 + <p:sp>/<p:pic> 计数，断言 11 页且 slide5 pics=1
```

## 相关坑速查

- react-icons v5：`react-icons/lucide` 不存在 → `react-icons/lu`，图标名 `Lu` 前缀
- puppeteer 在 skill 目录装：ESM import 需绝对路径指向 `node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js`
- qlmanage 只渲染 pptx 第一页；多页视觉 = 截图 qoderwork 的 filled HTML
- 本机无 Microsoft PowerPoint / Keynote / LibreOffice（有第三方 "Keynote Creator Studio.app"，不可用）
