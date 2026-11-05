---
name: ui-reference-scraping
description: Use when gathering design ref images or app screenshots.
---

# UI Reference Scraping

Gather UI/design reference images — app screenshots, OS design-language renders, placeholder photos — from public web sources using only `curl` + `python3` (no API keys, no browser). Works in China-based networks.

## When to Use

- User wants iOS/Android app UI screenshots as design references ("find iOS-style UI screenshots", "iOS 26 Liquid Glass style")
- Need reference images to feed a design-system extraction workflow (e.g. the ui-designer skill)
- Need placeholder/hero images for slides or mockups

## Method 1: App Store screenshots via iTunes Search API (no key)

The public iTunes Search API returns **official App Store screenshots** — the most authoritative "real app UI" reference.

```bash
curl -fsSL "https://itunes.apple.com/search?term=notion&entity=software&country=cn&limit=1" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['results'][0]; [print(u) for u in r['screenshotUrls']]"
```

- `term` = app name (English names work well; `country=cn` for CN store)
- `screenshotUrls` are thumbnail URLs with a default `/320x480bb.jpg` size suffix
- **Resolution bump**: replace `320x480bb` with `640x960bb` (also `600x1200bb`, `750x1334bb`) — validated working
- Extension quirk: PNG source URLs still carry the size suffix (`foo.png/320x480bb.jpg`); keep the suffix style you received

## Method 2: Apple official site (design-language renders)

For OS-level styles (e.g. iOS Liquid Glass) the official renders are the authoritative reference.

- `https://www.apple.com/ios/` works with a desktop browser UA. **`apple.com.cn` returns an empty ~345-byte shell to curl (bot protection) — skip the CN site**
- Images live under `/v/os/f/images/<product>/...` with `_large_2x.jpg` (highest res), `_medium`, `_small` variants
- Extract from srcset: `grep -oE '/v/[a-z]+/f/images/[^"]*_large_2x\.jpg' page.html | sort -u`
- Absolute URLs: `grep -oE 'https://www\.apple\.com/[^"]*\.(jpg|png)[^"]*'`
- Note: Apple retires old iOS pages — `/ios/ios-26/` 404s once iOS 27 ships; current `/ios/` page shows the latest release (design language carries over)

## Method 3: Generic placeholder images

- `https://picsum.photos/1600/900` — random JPEG of requested size, works in CN networks (used as slide/hero placeholders)

## Pitfalls

- **bash `${var/\/pat/\/repl}` inside double quotes leaves a literal backslash** → URL becomes invalid (`...png\/640x960bb.jpg`) and curl returns 400. Use a slash-free pattern: `${u/320x480bb/640x960bb}`.
- **Associative arrays with `/` in keys break bash** ("division by 0" arithmetic error, e.g. key `banner/recap__x`). Use paired arrays with a separator: `PAIRS=("path|name")`, then `${p%%|*}` / `${p##*|}`.
- **Verify downloads**: `file x.jpg` (content type may differ from URL extension); `sips -g pixelWidth -g pixelHeight` on macOS for dimensions.
- Wikipedia/Wikimedia time out from CN networks; Apple newsroom/release URLs 404 once guessed wrong — probe candidates with `curl -s -o /dev/null -w "%{http_code}"` before committing.
- No web-search tool available in this environment: public no-key APIs (iTunes Search, OSS direct URLs) beat scraping search engines.

## Reusable script

`scripts/fetch-appstore-screenshots.sh "notion things3" 3` — downloads N official screenshots per app search term into `appstore-screenshots/` with resolution bump + file verification.
