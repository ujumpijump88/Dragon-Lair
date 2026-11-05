---
name: macos-vision-ocr
description: "Use when extracting text from images/screenshots on macOS."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [ocr, vision, screenshot, text-extraction, macos, swift, chinese]
---

# macOS Vision OCR (zero-install)

Extract text from PNG/JPG screenshots or scans on macOS **without installing tesseract / marker-pdf / easyocr**. Uses the OS-bundled Vision framework through `/usr/bin/swift` (Xcode Command Line Tools). Handles **Chinese (zh-Hans)** out of the box.

**When to use:** user shares a screenshot and no image-vision tool is available in the session; need to read UI dialogs, documents, or any image text fast; marker-pdf's ~5GB install is overkill.

## Usage

```bash
swift scripts/ocr_image.swift /path/to/image.png
```

Prints recognized text in reading order (top→bottom, left→right).

## How it works

VNRecognizeTextRequest with:
- `.accurate` recognition level
- `recognitionLanguages = ["zh-Hans", "en-US"]`, `usesLanguageCorrection = true`
- Results sorted by `boundingBox.midY` descending, then `minX` — **Vision uses bottom-left-origin, y-up coordinates; invert midY for reading order**
- Image loaded via ImageIO `CGImageSource` (handles PNG/JPG, no AppKit needed)

## Pitfalls

- **First `swift` run compiles the script** (10–60 s); subsequent runs are fast.
- Requires `/usr/bin/swift` — check `which swift` first (present with Command Line Tools).
- Poor-contrast/noisy images: `.accurate` + language correction beats `.fast`; add `"zh-Hant"` for Traditional Chinese.
- Text-only OCR — cannot describe layout, colors, or non-text content; use an image-vision model for visual understanding when one is available in the toolset.
- Overlaps with the bundled `ocr-and-documents` skill (PDF-focused); this skill covers arbitrary images with zero dependencies.

## Verified

2026-08-08: extracted a 1224×1328 Chinese UI dialog (WPS "AI助理能力说明") with clean full-text output on first run.
