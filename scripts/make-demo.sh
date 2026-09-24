#!/bin/bash
# One .mov in, one README-ready GIF out, guaranteed under the size budget.
#
# GitHub strips <video> and ignores ![](x.mp4) in a README, so an animated GIF
# is the only thing that reliably plays inline. That forces the whole design:
# 256 colours per frame, no inter-frame compression worth the name, and a file
# that has to stay small enough that the page still loads.
#
#   ./scripts/make-demo.sh --bezel recordings/raw/01-hero.mov assets/demo/hero.gif
#   ./scripts/make-demo.sh --no-bezel recordings/raw/02-media.mov assets/demo/media.gif
set -euo pipefail

MAX_BYTES=$((5 * 1024 * 1024))   # 5MB hard ceiling
# Only used if auto-detection misses. This machine is a 15" MacBook Air M4
# (Mac16,13, native 2880x1864), which frames matches as "MacBook Air M5 15".
# A 14" Pro frame here would be the wrong lid and the wrong aspect.
DEVICE="MacBook Air M5 15"
BACKGROUND="#0d0d0d"

bezel=0
case "${1:-}" in
    --bezel)    bezel=1; shift ;;
    --no-bezel) bezel=0; shift ;;
    *) echo "usage: $0 --bezel|--no-bezel <input.mov> <output.gif>" >&2; exit 2 ;;
esac

src="${1:?input .mov required}"
out="${2:?output .gif required}"
[ -f "$src" ] || { echo "FAIL  no such file: $src" >&2; exit 1; }

[ "$bezel" -eq 0 ] || command -v frames >/dev/null || { echo "FAIL  frames not on PATH (~/.local/bin)" >&2; exit 1; }
command -v gifski   >/dev/null || { echo "FAIL  gifski not installed (brew install gifski)" >&2; exit 1; }
command -v gifsicle >/dev/null || { echo "FAIL  gifsicle not installed (brew install gifsicle)" >&2; exit 1; }

mkdir -p "$(dirname "$out")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ---------------------------------------------------------------- bezel stage
# Only the hero shot gets a lid. The close-ups are already cropped tight, and
# wrapping a 1200x400 crop in a MacBook frame just shrinks the thing you are
# trying to show.
stage="$src"
if [ "$bezel" -eq 1 ]; then
    echo "== probing $src"
    info="$(frames --json video-info "$src" 2>/dev/null || true)"

    # Single quotes inside Python, double quotes around it for the shell: an
    # f-string with escaped quotes silently blows up here on older pythons.
    detected="$(printf '%s' "$info" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('device') or '')
except Exception:
    print('')
" 2>/dev/null || true)"

    printf '%s' "$info" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print('   source     ' + str(d.get('dimensions')))
    print('   duration   ' + str(d.get('duration')) + 's @ ' + str(d.get('fps')) + 'fps')
    print('   detected   ' + str(d.get('device') or '(no match)'))
    print('   canvas     ' + str(d.get('frame_size')))
except Exception as e:
    print('   (could not parse video-info: ' + str(e) + ')')
" || true

    # Trust auto-detection when it already found a Mac; only force -d if it
    # whiffed, which is what a scaled (non-"Default for display") capture does.
    if printf '%s' "$detected" | grep -qi "macbook"; then
        echo "   using auto-detected frame: $detected"
        frames video --background "$BACKGROUND" --preset compact --strip-audio \
                     -o "$work/framed.mp4" "$src" >/dev/null
    else
        echo "   no Mac auto-match -- forcing -d \"$DEVICE\""
        echo "   (record full screen at Default for display so this auto-detects)"
        frames video -d "$DEVICE" --background "$BACKGROUND" --preset compact \
                     --strip-audio -o "$work/framed.mp4" "$src" >/dev/null
    fi
    stage="$work/framed.mp4"
fi

# ------------------------------------------------------------- encode + budget
# Escalating tiers. Each is "sample_fps gif_fps width lossy"; first one under
# the ceiling wins. lossy=0 skips gifsicle's lossy pass (-O3 alone is lossless).
# Width is a cap, never an upscale. Resolution goes before frame rate: judder
# reads worse than softness.
#
# GIF delays are whole centiseconds, so only 100/N fps is exact (50, 33.3, 25,
# 20). screencapture records a true 60fps. 50 takes the nearest real frame
# (one in six is skipped); minterpolate was tried and warps text mid-expand.
# The 33 tier is every 2nd frame at 3cs, ~11% fast but evenly spaced.
tiers=(
    "50 50 1200 0"
    "50 50 1000 0"
    "50 50 900 0"
    "50 50 900 40"
    "30 33.34 800 60"
)

encode() {  # sample_fps gif_fps width lossy -> writes $work/candidate.gif
    local sfps="$1" gfps="$2" width="$3" lossy="$4"
    ffmpeg -nostdin -v error -i "$stage" \
           -vf "fps=$sfps,setpts=N/($gfps*TB),scale='min(iw,$width)':-2:flags=lanczos" \
           -r "$gfps" -f yuv4mpegpipe - 2>/dev/null \
      | gifski -o "$work/raw.gif" --fps "$gfps" \
               --quality 100 --motion-quality 100 - >/dev/null 2>&1
    if [ "$lossy" -gt 0 ]; then
        gifsicle -O3 --lossy="$lossy" "$work/raw.gif" -o "$work/candidate.gif" 2>/dev/null
    else
        gifsicle -O3 "$work/raw.gif" -o "$work/candidate.gif" 2>/dev/null
    fi
}

landed=""
for tier in "${tiers[@]}"; do
    read -r sfps fps width lossy <<<"$tier"
    echo "== encoding ${fps}fps ${width}px lossy=${lossy}"
    encode "$sfps" "$fps" "$width" "$lossy"
    bytes=$(stat -f%z "$work/candidate.gif")
    printf '   %s\n' "$(du -h "$work/candidate.gif" | cut -f1 | tr -d ' ') ($bytes bytes)"
    if [ "$bytes" -le "$MAX_BYTES" ]; then
        landed="${fps}fps ${width}px lossy=${lossy}"
        cp "$work/candidate.gif" "$out"
        break
    fi
    echo "   over budget, escalating"
done

if [ -z "$landed" ]; then
    echo "FAIL  still over 5MB at the most aggressive tier (33fps 800px lossy=60)." >&2
    echo "      The clip is too long or too busy. Shorten it to 6-10s, or record" >&2
    echo "      against a flat dark wallpaper -- a photo wallpaper eats the" >&2
    echo "      256-colour palette and doubles the file." >&2
    exit 1
fi

echo "ok    $out"
echo "      tier: $landed  size: $(du -h "$out" | cut -f1 | tr -d ' ')"
[ "$landed" = "50fps 1200px lossy=0" ] || echo "      (fell back from the top tier -- fine, just noting it)"
# Read the numbers back out of the file, not out of what we asked for.
info="$(gifsicle --info "$out")"
echo "      canvas: $(printf '%s' "$info" | sed -n 's/.*logical screen \([0-9x]*\).*/\1/p' | head -1)" \
     " frames: $(printf '%s' "$info" | sed -n 's/.* \([0-9]*\) images.*/\1/p' | head -1)"
echo "      delays: $(printf '%s' "$info" | grep -o 'delay [0-9.]*s' | sort | uniq -c | tr -s ' ' | paste -sd, -)"
# gifski merges pixel-identical frames into one longer frame, so a hold shows
# up as a whole multiple of the base delay and is fine. Anything that isn't a
# multiple means frames were spaced unevenly: that is the judder, so fail.
printf '%s' "$info" | grep -o 'delay [0-9.]*s' | awk '
    { cs[NR-1] = int($2 * 100 + 0.5); n[cs[NR-1]]++ }
    END {
        for (d in n) if (n[d] > best) { best = n[d]; base = d }
        for (i = 0; i < NR; i++) if (cs[i] % base) bad = bad " " i "(" cs[i] "cs)"
        printf "      base delay %dcs on %d/%d frames (%.0f%%); longer ones are merged identical frames\n", base, best, NR, 100 * best / NR
        if (bad != "") { print "FAIL  delays that are not a multiple of " base "cs at frames:" bad > "/dev/stderr"; exit 1 }
        print "PASS  timing is even"
    }'
