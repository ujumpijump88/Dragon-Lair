---
name: node-pptx-authoring
description: Author .pptx with Node/pptxgenjs; QA without LibreOffice.
---

# Node PPTX Authoring

Use when building a .pptx from scratch or with deep customization using Node tooling —
the bundled `powerpoint` skill's pptxgenjs path — especially on machines **without
LibreOffice/PowerPoint** where that skill's visual-QA chain (soffice) is unavailable.
For quick, template-grade presentations use the `qoderwork-ppt` skill instead (it is
the primary on this machine; this skill is the verified fallback/companion).

## Setup (China-network macOS, verified)

```bash
npm install pptxgenjs react-icons react react-dom sharp --registry=https://registry.npmmirror.com
# schema validator needs defusedxml in the python env used for validation:
<venv>/bin/pip install defusedxml
```

Puppeteer (used by some pipelines for rendering): install deps with
`PUPPETEER_SKIP_DOWNLOAD=true` to skip the ~150MB Chromium download, then run with
`PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`.

## Workflow

1. Write the generator script with pptxgenjs. Follow the bundled `powerpoint` skill for
   design guidance (palettes, typography, layout, QA checklist) — it is the canonical
   design reference; this skill adds the machine-verified specifics it lacks.
2. Icons: react-icons v5 changed import paths and export names (old docs are wrong now)
   — see `references/react-icons-v5.md` before writing any icon code.
3. Generate: `node generate-deck.js` (or run the pipeline the deck script belongs to).
4. Validate: `python <powerpoint-skill>/scripts/office/validate.py deck.pptx`.
5. Visual QA without LibreOffice:
   - **HTML-based pipelines** (e.g. qoderwork-ppt `output/filled/*.html`): screenshot
     the filled HTML at 1920×1080 with Chrome headless — that rendered HTML IS the slide.
     `page.goto('file://'+abs, {waitUntil:'networkidle0'})` → settle → `page.screenshot()`.
   - **.pptx files**: `qlmanage -t -s 1200 -o dir deck.pptx` renders ONLY the first page —
     use as a smoke check, never full-deck QA. Final judgment = user opens the file.
6. Wire a regression harness: `"test": "bash scripts/verify.sh"` in package.json.

## Pitfalls (all hit in production)

- react-icons v5 renamed every export (see reference) — verify names before importing.
- pptxgenjs mutates option objects in place — build a fresh shadow/options object per shape.
- Hex colors: no `#`, never 8 digits (`color: "FF0000"`).
- This machine has NO LibreOffice/Homebrew/PowerPoint — do not attempt soffice-based QA;
  do not install LibreOffice for one-off QA (heavy, network-unstable).
- `qlmanage` first-page-only limitation is a trap for "did all slides render?" checks.

## Regression harness pattern

`package.json` → `"test": "bash scripts/verify.sh"`. The script rebuilds all artifacts
from source, then checks: `node --check` syntax, `validate.py` schema (grep for PASSED),
`unzip -t` integrity, artifact counts, and per-slide content via regex extraction of
`<a:t>` text from `ppt/slides/slideN.xml` inside the zip. This turned ~50 lines of
manual re-verification into one command and caught a cwd-relative-path bug that a
passing first run had silently hidden.

## Key files

- `references/react-icons-v5.md` — verified icon pipeline: imports, naming, sharp rasterization
