#!/bin/bash
# Install GitHub CLI (gh) without Homebrew on macOS arm64.
# Validated 2026-08: downloads the latest release binary, installs to ~/.hermes/bin/gh.
set -euo pipefail

VER=$(curl -sIL -o /dev/null -w "%{url_effective}" --max-time 20 https://github.com/cli/cli/releases/latest \
      | sed -E 's#.*/tag/##' | tr -d '\r')
echo "Latest gh version: $VER"

cd /tmp
curl -sL --max-time 120 -o gh.zip \
  "https://github.com/cli/cli/releases/download/${VER}/gh_${VER#v}_macOS_arm64.zip"
unzip -o -q gh.zip -d gh-pkg

mkdir -p "$HOME/.hermes/bin"
install -m 755 "gh-pkg/gh_${VER#v}_macOS_arm64/bin/gh" "$HOME/.hermes/bin/gh"
rm -rf gh.zip gh-pkg

"$HOME/.hermes/bin/gh" --version
echo "Done. Add to PATH if needed: export PATH=\"\$HOME/.hermes/bin:\$PATH\""
