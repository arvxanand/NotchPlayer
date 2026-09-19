#!/bin/bash
# Do the transport buttons take a click across their whole 44pt target, or
# only where the glyph is drawn?
#
# **This is the check for the single most-repeated mistake in the reference
# project.** `.contentShape(Rectangle())` uses the bounds of the view it is
# applied to, so a `.frame()` placed *after* it enlarges the layout and leaves
# the live area where it was. matchnotch had it backwards at six call sites,
# each with a comment claiming a 44pt target; the worst was a 12pt glyph in a
# 22x44 frame, where four clicks in five did nothing. It was found from a phone
# video of clicks that did nothing, because nothing in the code looks wrong and
# no unit test can see it.
#
# Only play/pause is probed, and only because it is reversible: prev and next
# would change the track and there is no way to put a queue back. All three
# come from the same `TransportButton`, so one button's live area is evidence
# about the pattern rather than about that button.
#
# It clicks real buttons, so it changes playback -- position and state are
# recorded first and restored at the end. Not part of `verify.sh` for that
# reason; run it after touching the panel's layout.
set -uo pipefail
cd "$(dirname "$0")/.."

# **Refuse to run while the installed agent is up.** Both panels sit at the
# same place on the same window level, so the clicks this posts land on
# whichever is on top -- and the answer comes back as a dead hit target rather
# than as an error. That looked exactly like a regression in the panel, and
# cost an hour of hunting one. With the agent stopped the same probe passes
# every check.
if pgrep -f 'SpotifyNotch\.app/Contents/MacOS/SpotifyNotch' >/dev/null; then
    echo "the installed app is running, and its panel is in the way."
    echo "Hide it from the menu bar item, or:"
    echo "    launchctl bootout gui/\$(id -u)/com.aravmanand.spotifynotch"
    echo "    ./tools/hit_probe.sh && ./tools/install-agent.sh"
    exit 1
fi

BIN=".build/debug/SpotifyNotch"
[ -n "$(find Sources -name '*.swift' -newer "$BIN" -print -quit 2>/dev/null)" ] && swift build >/dev/null
[ -x "$BIN" ] || { echo "swift build first"; exit 1; }

TOOLS="$(mktemp -d)"
read -r _ CX CY W _ < <("$BIN" --hit-rects | grep '^playpause ')
HALF=$((W / 2))

cat > "$TOOLS/act.swift" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
func warp(_ x: Double, _ y: Double) {
    CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
    CGAssociateMouseAndMouseCursorPosition(1)
}
switch a[1] {
case "save":
    let p = NSEvent.mouseLocation
    guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { exit(1) }
    print("\(p.x) \(s.frame.maxY - p.y)")
case "move":
    warp(Double(a[2])!, Double(a[3])!)
case "click":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    warp(p.x, p.y); usleep(250_000)
    for t in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p,
                mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
default: exit(1)
}
SWIFT
swiftc -O "$TOOLS/act.swift" -o "$TOOLS/act" 2>/dev/null

state() { osascript -e 'tell application "Spotify" to return player state as text'; }
HOME_XY=$("$TOOLS/act" save)
POS=$(osascript -e 'tell application "Spotify" to return player position')
STATE0=$(state)
app_pid=""
cleanup() {
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null
    wait 2>/dev/null
    # shellcheck disable=SC2086
    "$TOOLS/act" move $HOME_XY 2>/dev/null
    osascript -e "tell application \"Spotify\" to $([ "$STATE0" = playing ] && echo play || echo pause)" >/dev/null 2>&1
    osascript -e "tell application \"Spotify\" to set player position to $POS" >/dev/null 2>&1
    rm -rf "$TOOLS"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM PIPE

if [ "$STATE0" != playing ] && [ "$STATE0" != paused ]; then
    echo "Spotify must be playing or paused to probe play/pause (is: $STATE0)"; exit 1
fi

"$BIN" > /dev/null 2>&1 &
app_pid=$!
sleep 3
# Open the panel the only way it opens: by putting the pointer on the cutout.
"$TOOLS/act" move "$CX" 18
sleep 1.0

fail=0
probe() { # label x expected(HIT|DEAD)
    local before after got
    before=$(state)
    "$TOOLS/act" click "$2" "$CY"
    sleep 1.0
    after=$(state)
    [ "$before" != "$after" ] && got=HIT || got=DEAD
    if [ "$got" = "$3" ]; then printf "ok    %-44s x=%-5s %s\n" "$1" "$2" "$got"
    else printf "FAIL  %-44s x=%-5s got %s, wanted %s\n" "$1" "$2" "$got" "$3"; fail=1; fi
}

echo "play/pause target: ${W}x${W} centred at $CX,$CY"
probe "the glyph itself"                      "$CX"                    HIT
probe "inside the frame, right of the glyph"  "$((CX + HALF - 4))"     HIT
probe "inside the frame, left of the glyph"   "$((CX - HALF + 4))"     HIT
probe "past the frame, in the gap"            "$((CX + HALF + 6))"     DEAD
probe "past the frame, left gap"              "$((CX - HALF - 6))"     DEAD

[ "$fail" -eq 0 ] && echo "the whole target is live, and only the target" \
                  || echo "the drawn size and the live size disagree -- see docs/TRAPS.md"
exit $fail
