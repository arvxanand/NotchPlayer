#!/bin/bash
# One-off: rasterise design/wallpaper.svg to public/wallpaper.jpg (committed). Blurred art
# compresses well, and a JPEG saves rendering big blurs on every frame of the scroll.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --hide-scrollbars --window-size=1512,982 --screenshot="$OUT/w.png" "file://$PWD/design/wallpaper.svg" >/dev/null 2>&1
sips -s format jpeg -s formatOptions 72 "$OUT/w.png" --out public/wallpaper.jpg >/dev/null
# Phones show the desktop at ~0.36x: a small copy keeps the wallpaper off the LCP path.
sips -Z 760 -s format jpeg -s formatOptions 60 public/wallpaper.jpg --out public/wallpaper-s.jpg >/dev/null
ls -la public/wallpaper*.jpg
