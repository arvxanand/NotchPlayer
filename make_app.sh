#!/bin/bash
# Assemble NotchPlayer.app, and -- unlike matchnotch's equivalent -- restart
# the running copy if there is one.
#
# That second half is not a convenience. `swift build` does not update the
# running notch, and a whole week can go into testing a binary that is not the
# one on screen. matchnotch's CLAUDE.md carries that as rule 3 because the
# build script left the kickstart to the human. This one does not.
#
# SwiftPM cannot produce a bundle, and a bundle is required for LSUIElement
# (no dock icon), a stable bundle identifier, and the two usage-description
# strings TCC shows the user.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
# The release workflow passes the tag (`v0.2` -> `VERSION=0.2`). Releases
# start at 0.2, so a local build's 0.1 never matches a published one.
VERSION="${VERSION:-0.1}"
APP="NotchPlayer.app"
LABEL="io.github.arvxanand.notchplayer"
AGENT="com.aravmanand.notchplayer"
GUI="gui/$(id -u)"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/NotchPlayer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchPlayer"

# The icon used to be left out on purpose: it is a second way to launch the
# app, and a second instance stacks a second panel on the same notch. The
# guard in main.swift was then tested against a real second launch
# (`docs/BUGS.md` #15), and a downloaded app with a blank icon in Applications
# and Spotlight looks broken. Redraw it with `swift tools/make-icon.swift`.
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>NotchPlayer</string>
	<key>CFBundleIdentifier</key><string>$LABEL</string>
	<key>CFBundleExecutable</key><string>NotchPlayer</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<!-- Agent app: notch only, no dock icon, no menu bar item. -->
	<key>LSUIElement</key><true/>
	<key>NSAppleEventsUsageDescription</key><string>NotchPlayer reads the track Spotify is playing, and sends play, pause and skip when you use the controls in the notch.</string>
	<!-- Typed by hand: Xcode does not offer this key in its dropdown. -->
	<key>NSAudioCaptureUsageDescription</key><string>NotchPlayer listens to Spotify's own audio to draw the waveform beside the notch. Nothing is recorded or sent anywhere.</string>
</dict>
</plist>
PLIST

# Hardened runtime, unsandboxed on purpose: App Sandbox blocks Apple Events
# without a temporary exception for com.spotify.client, and this is not going
# to the App Store.
#
# Signed with the owner's self-signed "NotchPlayer" certificate when the
# keychain has it (CI loads it from a secret), so macOS keeps the permissions
# across builds and updates, and the updater can check a download is ours.
# Without it the build is ad-hoc: a new identity every build, so macOS
# re-asks for Automation and Audio Capture (`tools/reset-permissions.sh`).
# Found by its exact name and signed by its hash, because `codesign --sign
# NAME` matches any certificate whose name contains NAME.
SIGN_ID="${SIGN_ID:-$(security find-identity -p codesigning | awk '/"NotchPlayer"/ {print $2; exit}')}"
#
# **The hardened runtime blocks Apple Events unless the app says it sends
# them.** Without this entitlement every event fails with -1743 and macOS
# never prompts -- so it looks exactly like a user who denied Automation, and
# `tccutil reset` changes nothing because there was no TCC decision to reset.
# Cost: an afternoon, and `docs/TRAPS.md` #34.
ENTITLEMENTS="$(mktemp -t notchplayer-entitlements).plist"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.automation.apple-events</key><true/>
</dict>
</plist>
ENT
if [ -n "$SIGN_ID" ]; then
    # No fallback: a release signed any other way can't update itself.
    codesign --force --sign "$SIGN_ID" --options runtime --entitlements "$ENTITLEMENTS" "$APP"
    echo "signed with $SIGN_ID"
else
    codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP" >/dev/null 2>&1 \
        || echo "warn  codesign failed; the app will still run unsigned"
fi
rm -f "$ENTITLEMENTS"

echo "built $APP"

EXE="$PWD/$APP/Contents/MacOS/NotchPlayer"
# Every running copy of this bundle's executable. `comm` is the executable
# path alone -- see tools/sweep.sh for why not `command`.
bundle_pids() { ps -eo pid=,comm= | awk -v exe="$EXE" '{ p = $1; sub(/^ *[0-9]+ /, ""); if ($0 == exe) print p }'; }
old=$(bundle_pids)

# **The LaunchAgent is gone**, replaced by Launch at Login in the menu-bar
# item (SMAppService). Both at once would launch two copies at login, so an
# old agent is removed here, once. Its KeepAlive would also respawn the copy
# stopped below.
PLIST="$HOME/Library/LaunchAgents/$AGENT.plist"
if launchctl print "$GUI/$AGENT" >/dev/null 2>&1 || [ -f "$PLIST" ]; then
    launchctl bootout "$GUI/$AGENT" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed the old LaunchAgent $AGENT; use Launch at Login in the menu bar item"
fi

if [ -z "$old" ]; then
    echo "not running; open $APP to start it"
    exit 0
fi

# Stop every copy by pid, then start the new build with `open`: the audio
# tap only works when LaunchServices launches the app (`docs/TRAPS.md` #30).
# A copy left running would meet the fresh build's duplicate guard and keep
# the old binary on the notch (`docs/TRAPS.md` #42).
for pid in $old; do kill "$pid" 2>/dev/null || true; done
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -z "$(bundle_pids)" ] && break
    sleep 0.5
done
open "$APP"
# Believe the pid, not open's exit code.
for _ in $(seq 1 20); do
    now=$(bundle_pids)
    if [ -n "$now" ] && [ "$(echo "$now" | wc -l)" -eq 1 ] && ! echo "$old" | grep -qx "$now"; then
        echo "restarted as pid $now"
        exit 0
    fi
    sleep 0.5
done
echo "FAIL  the new build did not come up as the only copy"
bundle_pids | sed 's/^/      running: /'
exit 1
