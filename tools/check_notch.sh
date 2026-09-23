#!/bin/bash
# Nothing legible may be drawn behind the camera housing, in any state, ever.
#
# **One process, parked out of the way.** The first version launched the app
# once per state, put a window over the menu bar for 2.4s and killed it --
# nineteen times, about a minute of panels flashing across the top of the
# screen of whoever is using the machine, which is exactly where they are
# trying to work. Now a single `--capture-server` process takes state names on
# stdin, and `--offscreen` parks its window at the bottom-right corner.
#
# **Captures the panel's own window, not a screen rect.** matchnotch's version
# screen-captures the housing's coordinates and asserts they are black -- but a
# screen capture over the menu-bar strip does not contain the panel at all, so
# it reports CLEAN whenever the menu bar happens to be dark, including when the
# app is not running. See docs/BUGS.md #2.
#
# Parking is safe because the assertion is in **window-local** coordinates: the
# housing is a fixed offset inside the window, so where the window sits has no
# bearing on what is being checked. Parking it fully off-screen is not safe --
# macOS drops the backing store and the capture returns something else.
set -uo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
[ -x ".build/$CONFIG/SpotifyNotch" ] || CONFIG=debug
BIN=".build/$CONFIG/SpotifyNotch"
[ -x "$BIN" ] || { echo "build first: swift build"; exit 1; }

# A stale binary is rule 2 in a new costume, and it bit here twice: a flag was
# added, the script run without rebuilding, and it hung waiting on output
# from a binary that did not know the flag. Then **it rebuilt the wrong one**
# -- `swift build` is debug, `$BIN` was release -- so it checked a stale
# release binary that did not know a new preview state, and passed
# (TRAPS #45).
# Build the configuration that is about to run.
if [ -n "$(find Sources -name '*.swift' -newer "$BIN" -print -quit)" ]; then
    echo "sources are newer than $BIN -- building $CONFIG"
    swift build -c "$CONFIG" >/dev/null 2>&1 || { echo "build failed"; exit 1; }
fi

OUT="$(mktemp -d)"
FIFO="$OUT/in"
mkfifo "$FIFO"
server_pid=""

# A handler runs and *returns*; it does not end the script (TRAPS #61). So:
# cleanup on EXIT only, and signals merely ask for an exit.
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
    wait 2>/dev/null || true
    rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM PIPE

# Hold the fifo open so the server does not see EOF between states and
# terminate itself.
#
# **`3<>`, not `3>`.** Opening a fifo write-only blocks until something opens
# the read end -- and the read end here is the server, launched on the *next*
# line. That is a deadlock with a window on somebody's screen, and it happened
# twice before this comment existed.
exec 3<> "$FIFO"
"$BIN" --capture-server --offscreen < "$FIFO" > "$OUT/log" 2>&1 &
server_pid=$!

# Wait for the window id rather than sleeping a guessed amount.
for _ in $(seq 1 60); do
    WID=$(awk '/^window /{print $2; exit}' "$OUT/log" 2>/dev/null)
    [ -n "${WID:-}" ] && break
    sleep 0.1
done
[ -n "${WID:-}" ] || { echo "capture server never reported a window"; cat "$OUT/log"; exit 1; }
SIZE=$(awk '/^size /{print $2; exit}' "$OUT/log")
HOUSING=$(awk '/^housing /{print $2; exit}' "$OUT/log")

# **Not `mapfile`.** macOS ships bash 3.2, where `mapfile` does not exist --
# it fails, the array stays empty, and with the fifo held open the server never
# sees EOF, so the whole thing hangs with a window on somebody's screen.
SPECS=()
while IFS= read -r spec; do
    [ -n "$spec" ] && SPECS+=("$spec")
done < <("$BIN" --check-states)
[ "${#SPECS[@]}" -gt 0 ] || { echo "no states to check"; exit 1; }
echo "checking $(( ${#SPECS[@]} + 1 )) states"

fail=0
capture() { # label  state-line  mode  expected-shell
    printf "%-34s " "$1"
    local png="$OUT/shot.png" before after
    before=$(wc -l < "$OUT/log")
    printf '%s\n' "$2" >&3
    for _ in $(seq 1 40); do
        after=$(wc -l < "$OUT/log")
        [ "$after" -gt "$before" ] && break
        sleep 0.05
    done
    local shell_size
    shell_size=$(tail -1 "$OUT/log" | awk '/^ready /{print $2}')
    if [ -z "$shell_size" ]; then
        echo "FAIL  server did not answer: $(tail -1 "$OUT/log")"; fail=1; return
    fi
    screencapture -x -o -l "$WID" "$png" 2>/dev/null
    [ -f "$png" ] || { echo "FAIL  could not capture window $WID"; fail=1; return; }
    local checks=(--bounds "$shell_size")
    [ "$3" = both ] && checks=(--unlit "$HOUSING" "${checks[@]}")
    local out
    out=$(/usr/bin/python3 tools/pixel_check.py "$png" --size "$SIZE" "${checks[@]}" 2>&1) || fail=1
    if echo "$out" | grep -q FAIL; then
        echo "FAIL"; echo "$out" | sed 's/^/    /'; fail=1
    else
        echo "OK    $(echo "$out" | grep '^shell' | sed 's/^shell //')"
    fi
}

# Bounds only: it fills the shell white so the shape can be measured at all,
# so of course it lights the housing. It is the check that the concave
# shoulders exist; every state below is the check that nothing legible sits
# behind the camera.
capture "--probe" "probe" bounds

for spec in "${SPECS[@]}"; do
    # `--preview playing --expanded` -> `playing expanded`
    line=$(printf '%s' "$spec" | sed 's/--preview //; s/--expanded/expanded/')
    capture "$spec" "$line" both
done

exec 3>&-
exit $fail
