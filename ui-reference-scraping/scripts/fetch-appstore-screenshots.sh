#!/usr/bin/env bash
# Fetch official App Store screenshots via the public iTunes Search API (no key).
# Usage: bash fetch-appstore-screenshots.sh "notion things3" [shots-per-app]
# Output: ./appstore-screenshots/<term>-<n>.<ext>  (resolution-bumped, verified)
set -u
TERMS="${1:-notion things3}"
SHOTS_PER_APP="${2:-3}"
OUT="${OUT:-appstore-screenshots}"
mkdir -p "$OUT"
SIZE="640x960bb"   # bump from the default 320x480bb thumbnail (also valid: 600x1200bb, 750x1334bb)

for term in $TERMS; do
  echo "=== $term ==="
  urls=$(curl -fsSL --max-time 20 "https://itunes.apple.com/search?term=$term&entity=software&country=cn&limit=1" \
    | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin).get('results', [{}])[0]
    for u in r.get('screenshotUrls', [])[:$SHOTS_PER_APP]:
        print(u)
except Exception as e:
    print('ERR', e, file=sys.stderr)
")
  [ -z "$urls" ] && { echo "  (no screenshots)"; continue; }
  n=0
  for u in $urls; do
    n=$((n+1))
    # slash-free pattern on purpose: '/pat/' inside double quotes leaves a literal backslash -> 400
    hi="${u/320x480bb/$SIZE}"
    ext="${hi##*.}"; ext="${ext%%\?*}"
    out="$OUT/${term}-${n}.$ext"
    if curl -fsSL --max-time 30 -o "$out" "$hi" && [ -s "$out" ]; then
      echo "  OK ${term}-${n}.$ext ($(file -b "$out" | cut -c1-40))"
    else
      echo "  FAIL $u"
    fi
  done
done
echo "---"
echo "TOTAL: $(ls "$OUT" | wc -l | tr -d ' ') files in $OUT"
