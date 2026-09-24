#!/bin/bash
# Every recording in recordings/raw/ -> assets/demo/*.gif.
#
# Naming is the contract: NN-name.mov becomes name.gif. Every clip, hero
# included, is cropped around the notch -- a MacBook lid just shrinks it.
set -euo pipefail
cd "$(dirname "$0")/.."

RAW="recordings/raw"
OUT="assets/demo"
[ -d "$RAW" ] || { echo "FAIL  $RAW does not exist -- record the clips first (see "Rebuilding the demo GIFs" in README.md)" >&2; exit 1; }

shopt -s nullglob
movs=("$RAW"/*.mov)
[ ${#movs[@]} -gt 0 ] || { echo "FAIL  no .mov files in $RAW" >&2; exit 1; }

mkdir -p "$OUT"
failed=0
for src in "${movs[@]}"; do
    base="$(basename "$src" .mov)"
    name="${base#[0-9][0-9]-}"          # 01-hero -> hero
    flag=--no-bezel                     # ponytail: every clip is a tight crop now, --bezel stays opt-in
    echo
    echo "---- $base ($flag)"
    ./scripts/make-demo.sh "$flag" "$src" "$OUT/$name.gif" || { failed=1; echo "FAIL  $base" >&2; }
done

echo
if [ "$failed" -ne 0 ]; then echo "some clips failed" >&2; exit 1; fi
echo "all demos built:"
ls -lh "$OUT"/*.gif | awk '{printf "  %-28s %s\n", $9, $5}'
total=$(find "$OUT" -name '*.gif' -exec stat -f%z {} + | awk '{s+=$1} END {print s}')
echo "  total: $((total / 1024 / 1024))MB  (GitHub clones this every time -- keep it lean)"
