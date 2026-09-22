#!/bin/bash
# Assemble SpotifyNotch.app, and -- unlike matchnotch's equivalent -- restart
# the resident agent if one is loaded.
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
APP="SpotifyNotch.app"
LABEL="local.spotifynotch"
AGENT="com.aravmanand.spotifynotch"
GUI="gui/$(id -u)"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SpotifyNotch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SpotifyNotch"

# **No CFBundleIconFile, deliberately.** An icon is a second way to launch the
# app, and a second instance stacks a second panel on the same notch with no
# dock icon and no Quit to get rid of either (TRAPS #65, which recurred in
# matchnotch after being "fixed"). main.swift guards against it anyway; not
# shipping the icon means the guard is a backstop rather than the only defence.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>SpotifyNotch</string>
	<key>CFBundleIdentifier</key><string>$LABEL</string>
	<key>CFBundleExecutable</key><string>SpotifyNotch</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<!-- Agent app: notch only, no dock icon, no menu bar item. -->
	<key>LSUIElement</key><true/>
	<key>NSAppleEventsUsageDescription</key><string>SpotifyNotch reads the track Spotify is playing, and sends play, pause and skip when you use the controls in the notch.</string>
	<!-- Typed by hand: Xcode does not offer this key in its dropdown. -->
	<key>NSAudioCaptureUsageDescription</key><string>SpotifyNotch listens to Spotify's own audio to draw the waveform beside the notch. Nothing is recorded or sent anywhere.</string>
</dict>
</plist>
PLIST

# Hardened runtime, ad-hoc signed. Unsandboxed on purpose: App Sandbox blocks
# Apple Events without a temporary exception for com.spotify.client, and this
# is not going to the App Store.
#
# The cost, and it is a real one: an ad-hoc signature changes on every build,
# so macOS may treat each build as a new app and re-ask for Automation and
# Audio Capture. `tools/reset-permissions.sh` is the way out when it does.
# **The hardened runtime blocks Apple Events unless the app says it sends
# them.** Without this entitlement every event fails with -1743 and macOS
# never prompts -- so it looks exactly like a user who denied Automation, and
# `tccutil reset` changes nothing because there was no TCC decision to reset.
# Cost: an afternoon, and `docs/TRAPS.md` #34.
ENTITLEMENTS="$(mktemp -t spotifynotch-entitlements).plist"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.automation.apple-events</key><true/>
</dict>
</plist>
ENT
codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP" >/dev/null 2>&1 \
    || echo "warn  codesign failed; the app will still run unsigned"
rm -f "$ENTITLEMENTS"

echo "built $APP"

EXE="$PWD/$APP/Contents/MacOS/SpotifyNotch"
# Every running copy of this bundle's executable, launchd's or not. `comm` is
# the executable path alone -- see tools/sweep.sh for why not `command`.
bundle_pids() { ps -eo pid=,comm= | awk -v exe="$EXE" '{ p = $1; sub(/^ *[0-9]+ /, ""); if ($0 == exe) print p }'; }
agent_pid() { launchctl list | awk -v a="$AGENT" '$3 == a { print $1 }'; }

if launchctl print "$GUI/$AGENT" >/dev/null 2>&1; then
    # **A copy launchd does not own survives the kickstart** -- one started with
    # `open` after a Quit, say. The fresh build then meets the duplicate guard,
    # prints "already running" and exits 0, and the old binary stays on the
    # notch. Stop those by pid first. `docs/TRAPS.md` #42.
    old=$(agent_pid)
    for pid in $(bundle_pids); do
        [ "$pid" = "$old" ] && continue
        echo "stopping pid $pid, a copy launchd does not own"
        kill "$pid"
    done
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -z "$(bundle_pids | grep -vx "$old")" ] && break
        sleep 0.5
    done
    launchctl kickstart -k "$GUI/$AGENT"
    # Believe the pid, not the exit code: kickstart succeeds either way.
    for _ in $(seq 1 20); do
        now=$(agent_pid)
        if [ "$now" != "-" ] && [ "$now" != "$old" ] && [ "$(bundle_pids)" = "$now" ]; then
            echo "restarted $AGENT as pid $now"
            exit 0
        fi
        sleep 0.5
    done
    echo "FAIL  $AGENT did not come back as the only copy (launchd pid: $(agent_pid))"
    bundle_pids | sed 's/^/      running: /'
    exit 1
else
    echo "agent not loaded; ./tools/install-agent.sh to load it at login"
fi
