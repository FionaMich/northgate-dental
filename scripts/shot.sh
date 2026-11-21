#!/usr/bin/env bash
# Screenshot of a web page for the portfolio: scripts/shot.sh <url> <out.png> [desktop|phone|WIDTHxHEIGHT]
# Uses Playwright's headless Chromium (CHROME overrides the path).
set -euo pipefail
url="$1"; out="$2"; size="${3:-desktop}"
chrome="${CHROME:-$(ls -d "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell | tail -1)}"
case "$size" in phone) win=390,844; scale=3 ;; desktop) win=1440,900; scale=2 ;; *x*) win="${size/x/,}"; scale=2 ;; esac
mkdir -p "$(dirname "$out")"
"$chrome" --headless --hide-scrollbars --force-device-scale-factor="$scale" --window-size="$win" \
  --screenshot="$(realpath -m "$out")" "$url" >/dev/null 2>&1
echo "saved $out"
