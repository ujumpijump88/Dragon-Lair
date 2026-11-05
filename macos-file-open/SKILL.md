---
name: macos-file-open
description: "Use when a file won't open or needs a default app on macOS."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [macos, file-association, markdown, launchservices, textedit, open]
---

# macOS: Open Files / Set Default Apps

User-side truth from real sessions: when a user says "文件打不开" on macOS, the file is usually **fine** — the problem is (a) a tool misjudged it, or (b) no default app is associated with the extension. Follow this order; do NOT jump to "install Typora/Obsidian".

## 1. Verify the file is actually intact FIRST

Never trust a "corrupted/binary" verdict without byte-level proof:

```bash
file ~/path/file.md                       # "UTF-8 Unicode text" = good
python3 -c "open('f.md', encoding='utf-8').read()"   # decodes OK = good
xxd -l 128 file.md                        # inspect raw bytes
```

**Pitfall**: Hermes `read_file` can misjudge a perfectly valid file as `Binary file - cannot display as text` when it starts with emoji + variation selector (e.g. `# 🍽️`). If `file` says UTF-8 and python decodes, the file is fine — read it with python/terminal instead. Don't report "corrupted" to the user on read_file's say-so.

## 2. Find an app: probe BOTH app directories

System apps live in `/System/Applications`, NOT `/Applications` — a grep of user dir only misses **TextEdit**, the built-in viewer that opens .md fine (shows source, Chinese OK, editable).

```bash
ls /Applications /System/Applications | grep -iE "textedit|typora|obsidian|visual studio|chrome|safari"
```

User's machine (verified): TextEdit + Chrome + Safari, **no** Typora/Obsidian/VS Code, **no Homebrew**.

## 3. Open it

```bash
open -a TextEdit file.md          # specific app
open file.md                      # default association (double-click simulation)
```

User preference: use the native app that already exists — do not propose installing a viewer before checking TextEdit/browser.

## 4. Render .md as HTML (when a rendered view is wanted)

Use `scripts/md2html.py` (zero-dependency converter, handles the common syntax subset: headers, lists, tables, fenced code, inline code/bold/links; self-contained styled HTML):

```bash
python3 scripts/md2html.py README.md /tmp/readme.html && open /tmp/readme.html
```

Do NOT rely on the `markdown` pip package — the hermes venv's copy was broken (missing `importlib_metadata`).

## 5. Set a default association WITHOUT Homebrew (no brew, no duti)

Compile & run `scripts/set_default_handler.swift`:

```bash
swiftc scripts/set_default_handler.swift -o /tmp/set-default-handler
/tmp/set-default-handler md com.apple.TextEdit /Users/xiebojun/CanteenMenu/README.md
# last arg = sample file → script prints current default app + RESULT: SUCCESS
open ~/CanteenMenu/README.md      # end-to-end: double-click now opens TextEdit
```

Technique: `LSSetDefaultRoleHandlerForContentType` sets the handler for candidate UTIs (derived from extension via `UTType`, plus `public.plain-text` fallback for md-like text); `LSCopyDefaultApplicationURLForURL` verifies on a real file. Takes effect immediately, no daemon restart needed.

## Verification checklist (user insists tools actually work)

1. `file` + python decode → file intact
2. association script prints `RESULT: ✅ SUCCESS`
3. `open file` (no `-a`) actually opens the right app

## Support files

- `scripts/md2html.py` — zero-dep markdown → styled HTML converter
- `scripts/set_default_handler.swift` — set/verify default app for an extension via LaunchServices
