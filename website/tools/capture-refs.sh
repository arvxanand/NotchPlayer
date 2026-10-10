#!/bin/bash
# Captures the real app's states as reference PNGs for matching the site's notch.
#
# Same method as tools/check_notch.sh (NotchPlayer has no `--behind`): ONE
# `--capture-server --offscreen` process fed `<state> [expanded]` lines on stdin,
# each state captured by *window id* with `screencapture -l`, so nothing is drawn
# over the screen of whoever is using the machine. Output is gitignored
# (design/refs/).
#
# Rules that bit before, kept here (see docs/TRAPS.md in the app):
#  - hold the fifo open with `3<>`, never `3>` (deadlock);
#  - bash 3.2 has no `mapfile`;
#  - clean up on EXIT only; kill just the pid launched here, never `pkill -f`;
#  - rebuild the *release* binary when sources are newer (a stale binary lacks flags).
# If every capture is refused, Screen Recording permission is missing for this terminal.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=website/design/refs
mkdir -p "$OUT"

CONFIG=release
BIN=".build/$CONFIG/NotchPlayer"
if [ ! -x "$BIN" ] || [ -n "$(find Sources -name '*.swift' -newer "$BIN" -print -quit)" ]; then
    echo "building $CONFIG"
    swift build -c "$CONFIG" >/dev/null 2>&1 || { echo "build failed"; exit 1; }
fi

TMP="$(mktemp -d)"
mkfifo "$TMP/in"
server_pid=""
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM PIPE

exec 3<> "$TMP/in"
"$BIN" --capture-server --offscreen < "$TMP/in" > "$TMP/log" 2>&1 &
server_pid=$!
for _ in $(seq 1 60); do
    WID=$(awk '/^window /{print $2; exit}' "$TMP/log")
    [ -n "${WID:-}" ] && break
    sleep 0.1
done
[ -n "${WID:-}" ] || { echo "capture server never reported a window"; cat "$TMP/log"; exit 1; }
SIZE=$(awk '/^size /{print $2; exit}' "$TMP/log")
HOUSING=$(awk '/^housing /{print $2; exit}' "$TMP/log")

# `--preview playing --expanded` -> `playing expanded`; the two states that draw
# nothing are captured collapsed only.
SPECS=()
while IFS= read -r spec; do
    [ -n "$spec" ] && SPECS+=("$(printf '%s' "$spec" | sed 's/--preview //; s/--expanded/expanded/')")
done < <("$BIN" --check-states)
SPECS+=("stopped" "notrunning")

ok=0; failed=0
echo '[' > "$OUT/refs.json"; first=1
capture() { # "state [expanded]"
    local spec="$1" name png before after shell
    name="${spec// /-}"; png="$OUT/$name.png"
    rm -f "$png"  # a double failure must not leave a stale reference behind
    before=$(wc -l < "$TMP/log")
    printf '%s\n' "$spec" >&3
    for _ in $(seq 1 40); do
        after=$(wc -l < "$TMP/log")
        [ "$after" -gt "$before" ] && break
        sleep 0.05
    done
    shell=$(tail -1 "$TMP/log" | awk '/^ready /{print $2}')
    [ -n "$shell" ] || return 1
    sleep 1.5  # animation is off in the server; this is for the cover image to land
    screencapture -x -o -l "$WID" "$png" 2>/dev/null && [ -s "$png" ] || return 1
    [ "$first" = 1 ] || echo ',' >> "$OUT/refs.json"; first=0
    printf '{"name":"%s","file":"%s.png","window":"%s","shell":"%s","housing":"%s"}' \
        "$name" "$name" "$SIZE" "$shell" "$HOUSING" >> "$OUT/refs.json"
}
for spec in "${SPECS[@]}"; do
    if capture "$spec" || capture "$spec"; then  # one retry: captures flake now and then
        echo "ok   $spec"; ok=$((ok + 1))
    else
        echo "FAIL $spec"; failed=$((failed + 1))
    fi
done
echo ']' >> "$OUT/refs.json"
exec 3>&-

# Single views, rendered by the app itself.
for subject in mark peek artwork waveform progress; do
    rm -f "$OUT/render-$subject.png"
    "$BIN" --render "$subject" "$OUT/render-$subject.png" --side 240 2>/dev/null \
        && echo "ok   render $subject" || { echo "FAIL render $subject"; failed=$((failed + 1)); }
done

echo "captured $ok states, $failed failed"
[ "$ok" -gt 0 ] || { echo "nothing captured: give this terminal Screen Recording permission"; exit 1; }
[ "$failed" -eq 0 ]
