#!/bin/bash
# How many frames the expand animation actually renders, measured on the
# **running agent** rather than on a terminal build.
#
# That distinction is the whole point. matchnotch measured the same binary at
# 25-50fps under launchd's default `Standard` process type and 55-59fps with
# `ProcessType = Interactive`; a number taken from a `swift run` is a number
# about a different scheduling class. So this drives whatever instance is
# already on the notch and reads the answer out of its log.
#
# It moves the real pointer, because the panel is click-through and hover is
# polled -- there is no event to synthesise. The pointer is put back.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN=".build/debug/SpotifyNotch"
[ -x "$BIN" ] || { echo "swift build first"; exit 1; }
LOG="$HOME/Library/Logs/SpotifyNotch.log"

pgrep -f 'SpotifyNotch.app/Contents/MacOS/SpotifyNotch' >/dev/null || {
    echo "no running app -- open SpotifyNotch.app"; exit 1; }
[ -f "$LOG" ] || { echo "no $LOG -- the probe reads the app's log, which it only"
                   echo "writes when LaunchServices started it (open SpotifyNotch.app)"; exit 1; }

TOOLS="$(mktemp -d)"
trap 'rm -rf "$TOOLS"' EXIT
cat > "$TOOLS/act.swift" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { exit(1) }
switch a[1] {
case "save":
    let p = NSEvent.mouseLocation
    print("\(p.x) \(screen.frame.maxY - p.y)")
case "notch":
    // Middle of the cutout, a couple of points down from the very top edge:
    // the hover region is the cutout itself, and y=0 is the screen boundary.
    print("\(screen.frame.midX) 6")
case "away":
    print("\(screen.frame.midX) \(screen.frame.height / 2)")
case "move":
    CGWarpMouseCursorPosition(CGPoint(x: Double(a[2])!, y: Double(a[3])!))
    CGAssociateMouseAndMouseCursorPosition(1)
default: exit(1)
}
SWIFT
swiftc -O "$TOOLS/act.swift" -o "$TOOLS/act" 2>/dev/null || { echo "could not build the pointer helper"; exit 1; }

HOME_XY=$("$TOOLS/act" save) || { echo "no notched display"; exit 1; }
# shellcheck disable=SC2064
trap "\"$TOOLS/act\" move $HOME_XY 2>/dev/null; rm -rf \"$TOOLS\"" EXIT
trap 'exit 130' INT
trap 'exit 143' TERM PIPE

BEFORE=$(wc -l < "$LOG")
"$BIN" --probe-signal start
sleep 0.4
# shellcheck disable=SC2086
"$TOOLS/act" move $("$TOOLS/act" notch)   # expand
sleep 1.2
# shellcheck disable=SC2086
"$TOOLS/act" move $("$TOOLS/act" away)    # collapse
sleep 1.2
"$BIN" --probe-signal report
sleep 0.5

echo "measured on pid $(pgrep -f 'SpotifyNotch.app/Contents/MacOS/SpotifyNotch' | head -1):"
tail -n +$((BEFORE + 1)) "$LOG" | grep '^probe:' | sed 's/^/    /'
