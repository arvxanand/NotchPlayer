#!/bin/bash
# Pack NotchPlayer.app into NotchPlayer.dmg: the app next to an Applications
# shortcut, so the download opens as the usual "drag it across" window.
# The release workflow runs this, and so does a local test of the download, so
# the two can't drift. Run ./make_app.sh release first.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# ditto, not cp: it keeps the signature's extended attributes intact.
ditto NotchPlayer.app "$STAGE/NotchPlayer.app"
ln -s /Applications "$STAGE/Applications"

rm -f NotchPlayer.dmg
# hdiutil fails now and then on GitHub's macOS runners with "Resource busy";
# a second try is enough.
hdiutil create -volname NotchPlayer -srcfolder "$STAGE" -format UDZO -ov NotchPlayer.dmg \
    || { sleep 5; hdiutil create -volname NotchPlayer -srcfolder "$STAGE" -format UDZO -ov NotchPlayer.dmg; }
echo "built NotchPlayer.dmg"
