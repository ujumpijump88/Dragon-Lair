---
name: ui-restyle
description: Restyle a web UI to match a reference design style.
---

# UI Restyle (design-system-driven frontend redesign)

Use when the user wants an existing web app restyled to match a reference aesthetic (e.g. iOS 26 Liquid Glass), wants reference UI screenshots sourced for a design workflow, or wants a design system built from references + official specs. Covers the full chain: source imagery → design system → DOM-safe restyle → headless verification.

## 1. Source reference screenshots (works with no web-search tool)

- **App Store official screenshots** — iTunes Search API is public, no key:
  `curl "https://itunes.apple.com/search?term=<term>&entity=software&country=cn&limit=1"`
  → JSON `results[0].screenshotUrls[]` (official App Store marketing screenshots, ~6-8 per app).
  Bump resolution by string-replacing `320x480bb` → `640x960bb` in the URL.
- **Apple marketing renders** — `https://www.apple.com/ios/` (US site) HTML carries `srcset` entries with `/v/os/f/images/ios/<section>/<name>_large_2x.jpg`; grep `_large_2x` for hi-res official UI renders. Note: `apple.com.cn` returns a ~345-byte empty shell to curl (bot guard); Wikipedia times out from CN networks. Prefer US apple.com + iTunes API.
- **Bash pitfall**: `${u/\/320x480bb/\/$SIZE}` inside double quotes keeps a literal backslash → curl 400. Use a pattern with no slashes: `${u/320x480bb/$SIZE}`.
- Save into a per-style dir, e.g. `~/Hermes/ui-ref/<style>/`, with a fetch script kept alongside for re-runs.

## 2. Build the design system (no vision tool on this machine)

When `vision_analyze` is unavailable, do NOT pixel-guess a design system. Build it from the vendor's **official design-language spec** (Apple HIG for iOS, Material for Android, etc.) and use the downloaded screenshots as visual corroboration only. Record: materials (blur/glass recipes), colors (light AND dark), typography scale, radius system, spacing grid, motion (spring/easing), component specs. See `references/liquid-glass-design-system.md` for a ready-made iOS 26 example.

## 3. Restyle preserving the DOM contract (safest path)

- Read the app's JS first; extract EVERY `getElementById('x')` id and `querySelector(All)('.y')` class the logic depends on.
- Keep `index.html` structure and all ids/classes; change only CSS plus additive HTML (background layer div, theme-toggle button).
- Replace inline hex colors in JS-rendered template strings with `var(--token)` so dark mode works with zero logic changes.
- Wire the theme toggle as a small inline `<script>` (sets `data-theme` on `<html>` + localStorage), not inside app.js.
- Verify the contract mechanically: regex-extract ids from JS vs ids in HTML; regex-extract `var(--x)` refs from JS/HTML vs CSS definitions.

## 4. Verify with headless Chrome (puppeteer)

- Start the server, then screenshot + DOM-assert in one script: click each tab, wait, count rendered rows/cards/canvases, assert detail text length, check `getComputedStyle` colors in dark mode.
- Chrome: set `PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"` (system Chrome; install deps with `PUPPETEER_SKIP_DOWNLOAD=true`). Import puppeteer by absolute path into the skill's `node_modules` when running from another dir.
- **PITFALL — pixel-statistics false negatives on glass UIs**: average-luminance / dark-pixel-ratio analysis reports "blank page" on translucent designs — thin text lines get diluted by resize interpolation and glass blends into the background. Trust DOM assertions + computed styles + the actual screenshots, not pixel histograms. If a pixel check contradicts a DOM assertion, the pixel check is wrong.
- Ad-hoc verification: tempfile script (`hermes-verify-` prefix) asserting DOM contract + CSS var completeness + server 200s + `node --check`; report as ad-hoc, not suite green. Run it with the project's own venv python (Flask may live there, not in ~/Hermes/.venv).

## Pitfalls

- **Market-downloaded skill zips may omit referenced assets** (ui-designer shipped only SKILL.md, missing its `assets/*.md` templates). After installing a skill, verify every path the SKILL.md references exists. If the SKILL.md describes the templates in detail, rebuild them — the description is usually enough.
- **Reconstructing requirements from a past project**: use `session_search` to locate the session, then read the project's COMPLETED.md / README for the authoritative feature list; treat the session transcript as context, the committed docs as truth.
- Report visual results to the user with MEDIA: screenshots and let them pick light/dark before committing (creative work: no commit until user confirms).
