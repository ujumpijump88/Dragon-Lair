---
name: ppt-generation
description: Generate .pptx decks via qoderwork-ppt / powerpoint skill.
---

# PPT Generation (本机工作流)

生成/编辑 .pptx 演示文稿。触发：用户要求做 PPT、演示文稿、deck、slides。

## 工具链决策（本机已实测）

| 场景 | 用哪个 |
|------|--------|
| 快速生成精美中文 PPT（默认） | **qoderwork-ppt**（~/.hermes/skills/qoderwork-ppt，14 模板，HTML→Puppeteer→pptx） |
| 深度定制/品牌色/特殊图表/编辑现有模板 | bundled **powerpoint** 技能（pptxgenjs） |
| 金融场景模型绑定 deck | pptx-author（未装，用户无此需求） |

对比详情与决策依据见 `references/ppt-skill-comparison.md`。

## 环境准备（一次性，已装好）

```bash
# npm 依赖用 npmmirror（registry.npmjs.org 国内不稳）
npm install --registry=https://registry.npmmirror.com
# Puppeteer：跳过 Chromium 下载（~150MB），用系统 Chrome
PUPPETEER_SKIP_DOWNLOAD=true npm install
# 运行任何 puppeteer 脚本前：
export PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

## qoderwork-ppt 工作流（主力）

1. **输出目录**：项目根建 `output/`（含 `output/images/`）
2. **content.md**：按 `rules/content-rules.md` 生成结构化内容（封面/目录/正文/致谢，防空防溢）
3. **slides.json**：按 `templates/manifest.json` 槽位约束填 `{templateId, slots}`，模板匹配规则见 `rules/template-matching.md`
4. **生成**：⚠️ **cwd 必须是 output/ 所在的项目根**（slides.json 里的图片路径是相对 cwd 的）
   ```bash
   node ~/.hermes/skills/qoderwork-ppt/scripts/run-pipeline.js output/slides.json output/presentation.pptx
   ```

**坑（实测）**：
- **目录页 5 槽位占位符泄漏**：`contents` 模板每行内嵌 `0X I am the chapter name`，fill-template 不清理未填/空串槽位。目录 <5 章时把 chapter4/5 也填实际内容，别留空
- **图片槽位**（content-left-text-right-image / full-image 的 image）必须填真实图片，fill-template 会**内联为 base64**（grep 文件名找不到，要 grep `data:image/`）
- **配图源**：`curl -fsSL -o output/images/x.jpg https://picsum.photos/1600/900` 可达；pixabay CDN 403，unsplash 直链不稳
- 封面背景 / section-divider 插图：**勿填**，用模板默认
- 图标槽位用 `lucide:<icon-name>`

## 备选：bundled powerpoint 技能（pptxgenjs）

- 生成：写 pptxgenjs 脚本（LAYOUT_WIDE 13.3×7.5"，颜色不带 #，每形状独立 options 对象）
- 图标：react-icons **v5 变化**——`react-icons/lucide` 子路径不存在！Lucide 图标在 `react-icons/lu`，**图标名带 `Lu` 前缀**（`LuBrain` 等）；renderToStaticMarkup 输出 SVG → sharp 转 PNG → `addImage({path})`
- 验证：`python scripts/office/validate.py deck.pptx`（需 defusedxml，本机 .venv 已有）
- ⚠️ 本机**无 LibreOffice/PowerPoint**：技能要求的 soffice 渲染 QA 不可用 → 用下方替代方案

## QA / 验证（无 LibreOffice 替代方案）

1. **Schema 校验**（必做）：
   ```bash
   ~/Hermes/.venv/bin/python ~/.hermes/skills/productivity/powerpoint/scripts/office/validate.py deck.pptx
   ```
2. **ZIP 完整性**：`unzip -t deck.pptx`
3. **内容完整性**：zipfile 提取 `ppt/slides/slideN.xml` 的 `<a:t>` 文本 + 统计 `<p:sp>/<p:pic>`，检查每页非空
4. **视觉**：`qlmanage -t -s 1200 -o out/ file.pptx`（Quick Look，**只渲染第一页**）；qoderwork 可用 puppeteer 直接截图 `output/filled/*.html`（1920×1080，即模板真实渲染）
5. **回归脚本**：把重建+校验固化为 `npm run test` → `scripts/verify.sh`（重建两条流水线 → schema → zip → 内容分析）

## 参考

- `references/ppt-skill-comparison.md` — 三技能实测对比表（同主题 11 页双生成）、坑清单、验证命令
