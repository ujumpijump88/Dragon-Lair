# iOS 26 Liquid Glass — 设计系统速查（可直接套用的设计 token）

来源：Apple HIG 官方规范 + 官网界面渲染图（`~/Hermes/ui-ref/ios26-liquid-glass/`）。适合"做成 iOS 26 风格"的 UI 改版，含 Web/Tailwind 对应写法。

## 核心材质：液态玻璃

- 多层玻璃面板：背景 → 玻璃层 → 内容层；`backdrop-blur` 20-40px + 半透明着色
- 边缘高光：1px 白 20% 渐变描边；控件悬浮时"浮起"阴影
- 圆角用**连续曲率**（squircle）：大面板 34-40pt，小控件 10-12pt，胶囊按钮全圆
- **关键**：背景必须有内容可模糊（渐变/图片/壁纸），纯色背景 + 玻璃 = 无效
- Web 写法：`backdrop-filter: blur(26px) saturate(170%)` + `background: rgba(255,255,255,.32)`（浅色）/ `rgba(255,255,255,.08)`（深色）+ `border: 1px solid rgba(255,255,255,.5)` + `inset 0 1px 0 rgba(255,255,255,.75)` 高光 + `0 8px 32px rgba(0,0,0,.14)` 阴影

## 色彩（浅色 / 深色）

| 语义 | 浅色 | 深色 |
|---|---|---|
| 主文字 | `#1C1C1E` | `#FFFFFF` |
| 次文字 | `#3C3C43` 60% | 白 65% |
| 页面背景 | `#F2F2F7` | `#000000` |
| 系统蓝 | `#007AFF` | `#0A84FF` |
| 系统绿 | `#34C759` | `#30D158` |
| 系统红 | `#FF3B30` | `#FF453A` |
| 系统橙 | `#FF9500` | `#FF9F0A` |

## 字体（SF Pro / 苹方 PingFang SC）

Large Title 34 / Title1 28 / Title2 22 / Title3 20 / Headline 17(600) / Body 17 / Callout 16 / Subheadline 15 / Footnote 13 / Caption1 12 / Caption2 11。数字用 `font-variant-numeric: tabular-nums`。

## 组件规格

- 触控目标 ≥ 44×44pt
- 主按钮：系统蓝填充、胶囊、按压态透明度 50-60%（无位移）
- 列表：Inset Grouped 分组圆角卡片、行高 44pt+、分隔线缩进 16pt
- 导航栏/TabBar：blur + 底色 50% 透明（浅色 `#F9F9F9` 50% / 深色 `#1C1C1E` 80%）
- 搜索框：胶囊高 36pt、底 `#767680` 12%
- 间距：8pt 网格，页面边距 16-20pt

## 动效

- 弹性出现：`cubic-bezier(0.34, 1.56, 0.64, 1)`（卡片、弹窗）
- 标准过渡：`cubic-bezier(0.25, 0.1, 0.25, 1)` 200-300ms
- 玻璃模糊过渡：blur 值渐变动画是 iOS 26 标志性交互

## 设计原则（检查清单）

1. 玻璃优先：导航、面板、卡片、按钮都要有材质层
2. 背景丰富（渐变/壁纸），纯色+玻璃无效
3. 系统蓝主强调，功能色语义化，其余靠文字色阶
4. 深浅双模式全适配（CSS 变量 + `data-theme`）
5. 8pt 网格 + 连续曲率贯穿
6. 层级：背景 → 玻璃 → 内容 → 悬浮控件，滚动分层位移
