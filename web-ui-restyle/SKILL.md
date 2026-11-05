---
name: web-ui-restyle
description: Restyle existing web UI to a design system safely.
---

# Web UI Restyle

Restyle an existing web app's frontend (Flask/static/any server-rendered app) to a target design system — e.g. iOS 26 Liquid Glass — **without breaking existing behavior**. Proven on the CanteenMenu Flask app (87-recipe canteen planner).

## When to Use

- User asks to re-theme / redesign / restyle an existing web app's UI
- User provides a design system (or reference images) and wants it applied to a running app
- You must prove frontend edits work end-to-end but the project has no test suite

## Core Workflow

### 1. Extract the DOM contract FIRST
Read the frontend JS completely. Extract every `getElementById('...')` id and every `querySelector(All)` class it depends on. **These are the contract — never rename/remove them.** Strategy that worked:
- Rewrite `style.css` completely (design tokens + component styles)
- Extend `index.html` minimally (background layers, theme button, container wrappers — keep all ids/classes)
- Touch JS only for inline colors that break dark mode (`#2c4a78` on dark bg) and chart palette — replace hex with `var(--token)` (inline `style` supports `var()`).

### 2. Design tokens as CSS variables
All colors/radii/shadows/blur via `var(--x)` defined in `:root`, overridden in `[data-theme="dark"]`. Rule of thumb: no hardcoded hex outside the token block. Semantic palette: `--text-1/2/3`, `--glass-bg/-border/-highlight`, `--accent`, `--green/--red/--amber`.

### 3. Dual-mode theme toggle
`data-theme` attribute on `<html>` + localStorage persistence + a `#btn-theme` toggle. Verify with computed style, not eyeballs: `getComputedStyle(el).color === 'rgb(255,255,255)'` in dark mode.

### 4. Glass/material design needs a busy background
`backdrop-filter` is invisible on flat colors — the glass has nothing to blur. Use a gradient + animated blurred blobs (`filter: blur(90px)` colored circles) as the background layer. "Content is the background; glass only works over content."

## file:// Compatibility Pitfalls (user-correction: "双击打开不显示效果")

Two independent reasons a page renders as unstyled naked HTML when opened directly:

1. **Absolute asset paths break under file://** — `/static/style.css` resolves to `file:///static/style.css` (disk root) → 404, zero styling. Fix: **relative paths** `../static/style.css` (index.html in `templates/` needs `../static/`). Relative paths also resolve correctly at http root `/`. Verify no `/static/...` literals remain.
2. **Backend data doesn't exist under file://** — `fetch('/api/...')` fails. Show a preview banner when `location.protocol === 'file:'` ("静态预览模式：完整功能请访问 http://..."). Test BOTH modes with puppeteer.

## Verification Workflow (ad-hoc, fresh evidence)

The Hermes runtime repeatedly demands fresh verification after edits. Standardize it:

- **Canonical persistent entry**: `scripts/verify.sh` + `scripts/verify_ui.mjs` committed in the repo (`bash scripts/verify.sh`). A one-shot tempfile script gets deleted and the "fresh evidence" demand loops forever — persist it.
- **DOM contract check**: regex `getElementById\('([^']+)'\)` from JS vs `id="..."` in HTML — assert zero missing.
- **Behavior asserts via puppeteer** (not just HTTP 200): DOM counts (table rows, day-cards), computed styles (background gradient, backdrop-filter), request-failure listeners. Assert both `file://` and `http://` modes.
- **Pixel-stat sanity check caveat**: average luminance/percentile stats on **resized** screenshots give false "blank page" readings — resize+interpolation dilutes thin text into mid-tones, and glass UI is low-contrast by design. DOM assertions are ground truth; pixel stats are only a hint. Use LANCZOS at ≥1024px width and read dark/bright percentiles, never a raw <20 std-dev threshold.
- Ad-hoc runs: tempfile script with `hermes-verify-` prefix, run, then clean up.
- Per house style: don't commit until the user confirms visual satisfaction (creative work), and say explicitly when the check is ad-hoc, not suite green.

## Design-Reference Sourcing (when restyling to a reference style)

- **iTunes Search API** (public, no key): `https://itunes.apple.com/search?term=X&entity=software&country=cn&limit=1` → `results[0].screenshotUrls` = official App Store screenshots. Bump resolution by string-replacing `/320x480bb` → `/640x960bb`. Great source for iOS-style UI reference images.
- **Apple official pages**: `apple.com.cn/ios/` returns an empty 345-byte shell to curl (bot protection); `apple.com/ios/` works with a desktop UA. Images live in srcset — grep `/v/.../_large_2x.jpg`.
- Wikipedia times out from CN networks (en.wikipedia.org).

## Pitfalls (tool gotchas hit this session)

- **bash associative arrays**: keys containing `/` break `"${arr[$k]}"` — bash parses the key as arithmetic → `division by 0`. Use parallel indexed arrays (`"path|name"` pairs).
- **bash parameter expansion in double quotes**: `${u/\/old/\/new}` keeps a literal `\` in the replacement → invalid URL. Use patterns WITHOUT slashes: `${u/old/new}`.
- **react-icons v5**: subpath is `react-icons/lu` (not `./lucide`), icon names are `Lu`-prefixed (`LuBrain`, not `Brain`); exports map rejects unknown subpaths.
- **Puppeteer on machines without Chromium download**: install with `PUPPETEER_SKIP_DOWNLOAD=true npm install`, run with `PUPPETEER_EXECUTABLE_PATH=/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`. When puppeteer isn't installed locally, import it via absolute path into another project's `node_modules` ESM entry.

## References

- `references/canteenmenu-liquid-glass.md` — full case study: applying iOS 26 Liquid Glass to the Flask CanteenMenu app (DOM contract list, exact verification script content, screenshot workflow).
