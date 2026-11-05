# UI 实现 Prompt 模板（最终交付物）

> 用途：Step 4 合成——把设计系统 + PRD 组合成可直接交给实现代理/工程师的完整 Prompt。
> 替换：`{项目设计指南}` → Step 2 设计系统文档；`{项目MVP PRD}` → Step 3 PRD。

---

## 角色

你是一名资深前端工程师，负责实现 `{项目名称}` 的 MVP UI。参考设计系统与 PRD 进行开发，产出**多套视觉变体**供选择。

## 一、设计美学原则

### 整体风格
- 视觉基调：{项目设计指南 → 第 7 节设计原则总结}（如简约/卡片式/活力/专业）
- 设计哲学：
  - **极简主义**：去除装饰性元素，信息即界面；空白是设计的一部分
  - **留白**：页面左右安全边距 `__px`，区块间距遵循 4dp 网格
  - **色彩理论**：主色承担 60-70% 视觉权重，强调色仅用于关键动作/状态（每屏 ≤ 2 个强调点）
  - **层级**：标题 → 正文 → 辅助信息字号递减，用字重与颜色（而非下划线）区分层级

### 色彩规范（直接引用设计系统）
- Primary `#______` / Secondary `#______` / Accent `#______`
- 功能色：Success `#______` / Warning `#______` / Danger `#______`
- 背景 `#______` / 卡片 `#______` / 文字 `#______` / 次文字 `#______`
- 全部使用语义化 Tailwind 类或主题变量，禁止硬编码色值

### 字体规范（直接引用设计系统）
- 字体族：`________`
- 字号阶梯：Display `__px` / H1 `__px` / H2 `__px` / Body `__px` / Caption `__px`
- 行高：正文 `1.5`，标题 `1.2`

## 二、项目需求（引用 PRD）

### 产品概述
{项目MVP PRD → 第 1-4 节：电梯陈述 / 问题 / 目标用户 / USP}

### MVP 功能清单（P0 必须实现）
{项目MVP PRD → 第 6 节功能列表}

### 界面与交互要求
{项目MVP PRD → 第 7 节 UX/UI 要点}

## 三、技术实现要求

- **框架**：React（函数组件 + Hooks）
- **样式**：Tailwind CSS（用 design system 建立 theme 扩展：colors / fontFamily / borderRadius / boxShadow / spacing）
- **图标**：lucide-react（统一线性图标，尺寸 16/20/24px 三档）
- **响应式**：移动端 375px 断点优先，桌面 ≥ 1024px 自适应；移动端 3 套变体、桌面 2 套变体
- **组件化**：公共组件（Button/Card/Input/Icon/Badge 等）抽为独立文件复用
- **交互态**：每个可交互元素实现 hover / active / disabled / focus 状态

## 四、任务规格

### 变体要求
1. **移动端变体 A**：`[solution-name]/pages/home-mobile-a.jsx` —— 侧重 {变体A侧重点}
2. **移动端变体 B**：`[solution-name]/pages/home-mobile-b.jsx` —— 侧重 {变体B侧重点}
3. **移动端变体 C**：`[solution-name]/pages/home-mobile-c.jsx` —— 侧重 {变体C侧重点}
4. **桌面变体 A**：`[solution-name]/pages/home-desktop-a.jsx` —— 侧重 {变体A侧重点}
5. **桌面变体 B**：`[solution-name]/pages/home-desktop-b.jsx` —— 侧重 {变体B侧重点}

各变体在同一信息架构下变换：布局密度、卡片样式、导航形态、色彩分配比例——保持品牌一致但视觉明显可区分。

### 组件组织结构
```
[solution-name]/
├── components/          # 公共组件
│   ├── Button.jsx
│   ├── Card.jsx
│   ├── Input.jsx
│   ├── Icon.jsx
│   └── ...
├── pages/               # 变体页面
│   ├── home-mobile-a.jsx
│   ├── home-mobile-b.jsx
│   ├── home-mobile-c.jsx
│   ├── home-desktop-a.jsx
│   └── home-desktop-b.jsx
└── showcase.jsx         # 聚合展示页：所有变体汇总导航
```

### 展示页
`showcase.jsx` 聚合 5 个变体，顶部提供变体切换入口，方便对比评审。

### 完成标准
- 所有 P0 功能可用，交互态完整
- 无硬编码色值/字号；Tailwind theme 已按设计系统配置
- 变体间差异明显、风格统一
- 代码整洁、组件可复用
