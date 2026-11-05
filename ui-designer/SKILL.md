---
name: ui-designer
description: Extract design systems from reference UI images and generate implementation-ready UI design prompts. Use when users provide UI screenshots/mockups and want to create consistent designs, generate design systems, or build MVP UIs matching reference aesthetics.
---

# UI Designer

## Overview

This skill enables systematic extraction of design systems from reference UI images through a multi-step workflow: analyze visual patterns → generate design system documentation → create PRD → produce implementation-ready UI prompts.

## When to Use

- User provides UI screenshots, mockups, or design references
- Need to extract color palettes, typography, spacing from existing designs
- Want to generate design system documentation from visual examples
- Building MVP UI that should match reference aesthetics
- Creating multiple UI variations following consistent design principles

## Workflow

### Step 1: Gather Inputs

Request from user:
- **Reference images directory**: Path to folder containing UI screenshots/mockups
- **Project idea file**: Document describing the product concept and goals
- **Existing PRD** (optional): If PRD already exists, skip Step 3

### Step 2: Extract Design System from Images

**Use Task tool with general-purpose subagent**, providing:

**Prompt template** from `assets/design-system.md`:
- Analyze color palettes (primary, secondary, accent, functional colors)
- Extract typography (font families, sizes, weights, line heights)
- Identify component styles (buttons, cards, inputs, icons)
- Document spacing system
- Note animations/transitions patterns
- Include dark mode variants if present

**Attach reference images** to the subagent context.

**Output**: Complete design system markdown following the template format

**Save to**: `documents/designs/{image_dir_name}_design_system.md`

### Step 3: Generate MVP PRD (if not provided)

**Use Task tool with general-purpose subagent**, providing:

**Prompt template** from `assets/app-overview-generator.md`:
- Replace `{项目背景}` with content from project idea file
- The template guides through: elevator pitch, problem statement, target audience, USP, features list, UX/UI considerations

**Interact with user** to refine and clarify product requirements

**Output**: Structured PRD markdown

**Save as variable** for Step 4 (optionally save to `documents/prd/`)

### Step 4: Compose Final UI Implementation Prompt

Combine design system and PRD using `assets/vibe-design-template.md`:

**Substitutions:**
- `{项目设计指南}` → Design system from Step 2
- `{项目MVP PRD}` → PRD from Step 3 or provided PRD file

**Result**: Complete, implementation-ready prompt containing:
- Design aesthetics principles
- Project-specific color/typography guidelines
- App overview and feature requirements
- Implementation tasks (multiple UI variations, component structure)

**Save to**: `documents/ux-design/{idea_file_name}_design_prompt_{timestamp}.md`

### Step 5: Verify React Environment

Check for existing React project:
```bash
find . -name "package.json" -exec grep -l "react" {} \;
```

If none found, inform user:
```bash
npx create-react-app my-app
cd my-app
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
npm install lucide-react
```

### Step 6: Implement UI

Use the final composed prompt from Step 4 to implement UI in React project.

The prompt instructs to:
- Create multiple design variations (3 for mobile, 2 for web)
- Organize as separate components: `[solution-name]/pages/[page-name].jsx`
- Aggregate all variations in showcase page

## Template Assets

### assets/design-system.md

Template for extracting visual design patterns. Includes sections for:
- Color palette (primary, secondary, accent, functional, backgrounds)
- Typography (font families, weights, text styles)
- Component styles (buttons, cards, inputs, icons)
- Spacing system (4dp-48dp scale)
- Animations (durations, easing curves)
- Dark mode variants

Use this template when analyzing reference images to ensure comprehensive design system coverage.

### assets/app-overview-generator.md

Template for collaborative PRD generation. Guides through:
- Elevator pitch
- Problem statement and target audience
- Unique selling proposition
- Platform targets
- Feature list with user stories
- UX/UI considerations per screen

Designed for interactive refinement with user to clarify requirements.

### assets/vibe-design-template.md

Final implementation prompt template combining design system and PRD. Includes:
- Aesthetic principles (minimalism, whitespace, color theory, typography hierarchy)
- Practical requirements (Tailwind CSS, Lucide icons, responsive design)
- Task specifications (multiple variations, component organization)

This template produces prompts ready for UI implementation without further modification.

## Best Practices

### Image Analysis

- Read all images before starting analysis
- Look for patterns across multiple screens
- Note both explicit styles (colors, fonts) and implicit principles (spacing, hierarchy)
- Capture dark mode if present in references

### Design System Extraction

- Be systematic: cover all template sections
- Use specific values (hex codes, px sizes) not generic descriptions
- Document the "why" for design choices when inferable
- Include variants (hover states, disabled states)

### PRD Generation

- Engage user interactively to clarify ambiguities
- Suggest features based on problem understanding
- Ensure MVP scope is realistic
- Document UX considerations per screen/interaction

### Output Organization

- Save design system with descriptive filename (based on image dir name)
- Save final prompt with timestamp for version tracking
- Keep all outputs in `documents/` directory for easy reference
- Preserve intermediate outputs for iteration

## Notes from practice

- **无视觉工具时**：如果环境没有 vision/图像分析能力，不要从像素硬猜设计系统——优先查官方规范（如 Apple HIG、Material Design）构建设计系统，参考截图作为佐证。产出更权威且可解释。
- **iOS 风格截图来源**：Apple iTunes Search API（`https://itunes.apple.com/search?term=X&entity=software&country=cn&limit=1`）无需 key，返回 App Store 官方截图 URL；把 URL 中 `320x480bb` 换成 `640x960bb` 得高清版。iOS 26 液态玻璃官方渲染图可从 `apple.com` 官网 iOS 页面抓取（`/v/os/f/images/ios/..._large_2x.jpg`，需浏览器 UA）。
- **bash 坑**：关联数组键含 `/` 会触发算术求值错误（division by 0）；字符串替换 `${u/\/pat/\/rep}` 在双引号内会残留字面反斜杠——用不含斜杠的模式 `${u/320x480bb/640x960bb}`。
- **玻璃 UI 的像素验证假阴性**：backdrop-blur 玻璃与背景融合导致对比度低，小尺寸 resize 后文字像素被插值稀释，dark/bright 像素统计会误报"空白"——以 DOM 断言（行数/文本长度/computed style）为准，像素分析仅作辅助。
- **file:// 兼容**：给 Web 应用做静态预览时，CSS/JS 用相对路径（`../static/`），并检测 `location.protocol === 'file:'` 显示提示条；fetch 的 API 在 file:// 下必然失败，属预期。
- **验证入口**：UI 重构后固化为 `scripts/verify.sh`（行为级：file:// 兼容 + http:// 模式 + DOM 契约断言），比每次临时脚本可靠。

## Example Usage

**User provides:**
- `reference-images/saas-dashboard/` (5 screenshots)
- `ideas/project-management-app.md` (project concept)

**Execute workflow:**

1. Read 5 images from `reference-images/saas-dashboard/`
2. Use Task tool → design-system.md template → analyze images
3. Save to `documents/designs/saas-dashboard_design_system.md`
4. Use Task tool → app-overview-generator.md with project concept
5. Refine PRD through user interaction
6. Combine design system + PRD using vibe-design-template.md
7. Save to `documents/ux-design/project-management-app_design_prompt_20251025_153000.md`
8. Check React environment, inform user if setup needed
9. Implement UI using final prompt

## Notes

- This is a **high freedom** workflow—adapt steps based on context
- Templates provide structure but encourage thoughtful analysis over rote filling
- User interaction during PRD generation is critical for quality
- Final prompt quality directly impacts UI implementation success
- Preserve all intermediate outputs for iteration and refinement
