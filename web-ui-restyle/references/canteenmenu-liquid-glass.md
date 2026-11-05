# Case Study: iOS 26 Liquid Glass on CanteenMenu (Flask)

Applying the iOS 26 Liquid Glass design system to the existing Flask app `~/CanteenMenu` (87-recipe canteen planner, SQLite + REST API, vanilla JS frontend). Result: full glass restyle + dark mode, all behavior preserved.

## Context

- App: Flask (`app.py`) serving `templates/index.html` + `static/style.css` + `static/app.js` (541-line vanilla JS, Chart.js for reports)
- User asked to re-design its UI with the iOS 26 Liquid Glass design system (extracted earlier via the `ui-designer` skill from Apple official renders)
- Constraint discovered mid-way: **user opened the HTML file directly (file://) and saw unstyled naked HTML** — "为什么我在浏览器打开html文件不显示这个效果木讷"

## Root cause of the file:// failure (the key lesson)

Diagnosed with puppeteer request-failure listeners:

```
[reqfail] file:///static/style.css  net::ERR_FILE_NOT_FOUND
[reqfail] file:///static/app.js     net::ERR_FILE_NOT_FOUND
bodyBg = "none", poolRows = 0
```

1. Absolute paths `/static/...` resolve to `file:///static/...` (disk root) under file:// → 404 → zero styling
2. Even with styles, `fetch('/api/...')` has no backend under file:// → no data

Fix:
- `<link href="../static/style.css">` and `<script src="../static/app.js">` — relative, works for both `file:///.../templates/index.html` and `http://host/` (root)
- Inline guard script: `if (location.protocol === 'file:')` → insert a glass `#preview-bar` div: "静态预览模式：样式可见，但数据需通过服务访问 → 启动 Flask 后打开 http://127.0.0.1:5050/"

## Verification approach that satisfied the "fresh evidence" loop

The Hermes runtime demands fresh verification after every edit. One-shot tempfile scripts get deleted and the demand loops. Solution: **persist a canonical verify entry in the repo**:

- `scripts/verify.sh` — `PUPPETEER_EXECUTABLE_PATH=... node scripts/verify_ui.mjs`
- `scripts/verify_ui.mjs` — 15 checks:

```
A. static contract: rel CSS/JS paths, file: guard present, preview-bar logic,
   no /static/ literals left, DOM contract (all getElementById ids exist in HTML)
B. file:// behavior: gradient bg loaded (computed style), preview bar shown,
   3 blobs, header backdrop-filter active, zero css/js load failures
C. http:// behavior: 87 table rows, no preview bar, zero failed requests
```

## DOM contract extraction (from app.js — keep these untouched)

`getElementById` ids: pool-tbody, pool-count, filter-category, filter-cook, filter-health, btn-add-recipe, btn-edit-pricing, btn-export-snapshot, btn-import-snapshot, import-file, week-select, plan-grid, plan-stats, btn-regen, btn-export-xlsx, btn-export-csv, chart-kcal, chart-na, chart-protein, report-summary, recipe-input, recipe-ids, btn-show-recipe, recipe-detail, toast, recipe-input...

Classes: .nav-btn[data-tab], .tab/#tab-*, .day-card (h3/.day-nut/.dish-list>li[data-id][data-type][data-cook]>.badge/.name/.swap-btn), .nut-grid>.nut-cell>.v/.l, .health-tag, .op-edit/.op-del, .toolbar, .filters

Global functions referenced by inline handlers: `editPrice(id)`.

## Liquid Glass token block (abridged)

```css
:root {
  --glass-bg: rgba(255,255,255,.32); --glass-bg-strong: rgba(255,255,255,.55);
  --glass-border: rgba(255,255,255,.5); --glass-highlight: rgba(255,255,255,.75);
  --blur: 26px; --radius-lg: 24px; --radius-pill: 999px;
  --accent: #007aff; --green: #34c759; --red: #ff3b30; --amber: #ff9500;
  --text-1: #1c1c1e; --text-2: rgba(28,28,30,.62); --text-3: rgba(28,28,30,.34);
  --shadow: 0 8px 32px rgba(80,50,20,.14);
}
[data-theme="dark"] { --glass-bg: rgba(255,255,255,.07); --text-1:#fff; --accent:#0a84ff; ... }
```

Key rules:
- Background: `linear-gradient(135deg, ...)` + 3 animated `.blob` divs (`filter: blur(90px)`, `animation: drift`) — glass needs busy content behind it
- `.glass` utility: `background: var(--glass-bg); backdrop-filter: blur(var(--blur)) saturate(170%); border: 1px solid var(--glass-border); box-shadow: var(--shadow), inset 0 1px 0 var(--glass-highlight);`
- Buttons: pill (999px), gradient fill + inner highlight + colored shadow; row-action buttons glass-outlined
- Chart.js palette: `#FF9500` (kcal), `#FF3B30` (Na), `#34C759` (protein) — inside `.chart-wrap` glass containers
- JS inline colors that break dark mode were converted to `var(--text-1)` / `var(--text-2)` (inline style supports CSS vars)

## Verification result

15/15 checks ALL OK via `bash scripts/verify.sh`; 5 screenshots (4 tabs light + plan dark) produced with puppeteer at 1360×900 deviceScaleFactor 1.5. Committed only after user confirms visual satisfaction (house style for creative work).
