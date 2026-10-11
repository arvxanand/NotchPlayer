#!/bin/bash
# One-off: photograph the dev-only /og page into public/og.png (committed), the picture link
# previews show (Messages, Slack, social). Needs the dev server running: npm run dev.
set -euo pipefail
cd "$(dirname "$0")/.."
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
  --window-size=1200,630 --virtual-time-budget=4000 --screenshot="$PWD/public/og.png" "http://localhost:4321/og" >/dev/null 2>&1
sips -g pixelWidth -g pixelHeight public/og.png | tail -2
ls -la public/og.png
