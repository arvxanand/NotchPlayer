#!/bin/bash
# Load the LaunchAgent, substituting this checkout's path into the template.
#
# The plist in the repo carries __DIR__ rather than an absolute path, because
# matchnotch's has /Users/aravmanand/side-projects/matchnotch baked into two
# keys and there is no install script -- so the repo copy and the loaded copy
# are kept identical by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$(pwd)"
AGENT="com.aravmanand.spotifynotch"
GUI="gui/$(id -u)"
DEST="$HOME/Library/LaunchAgents/$AGENT.plist"

[ -x "SpotifyNotch.app/Contents/MacOS/SpotifyNotch" ] || { echo "./make_app.sh release first"; exit 1; }

sed "s|__DIR__|$DIR|g" "LaunchAgent/$AGENT.plist" > "$DEST"

# bootout then bootstrap, not kickstart: kickstart reuses the cached job
# definition, so a changed plist would not take effect.
launchctl bootout "$GUI/$AGENT" 2>/dev/null || true
launchctl bootstrap "$GUI" "$DEST"
echo "loaded $AGENT from $DIR"
