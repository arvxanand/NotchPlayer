#!/bin/bash
# One command. Everything that can be checked without eyes.
#
# What this CANNOT prove, and it matters:
#   - that the layout is *right*, only that nothing is drawn behind the camera
#   - that an animation looks good mid-flight
#   - that the collapsed peek looks right to a human. `screencapture -R` over
#     the menu-bar strip does not contain the panel at all (measured: an A/B
#     with the panel on and off differed in zero columns over 520pt), which is
#     why `check_notch.sh` captures the panel's own window instead. That gets
#     the pixels; it does not get how they sit against the hardware. For that,
#     ask for a phone photo.
set -uo pipefail          # no -e, on purpose: every stage should run
cd "$(dirname "$0")/.."

fail=0
step() { printf "\n\033[1m%s\033[0m\n" "$1"; }
bad()  { printf "\033[31mFAIL\033[0m  %s\n" "$1"; fail=1; }
ok()   { printf "\033[32mok\033[0m    %s\n" "$1"; }

step "Build (warnings are treated as failures here)"
# Touch every source first: an incremental build says nothing about files it
# did not recompile, which reads as a false clean. And capture the output
# ONCE -- matchnotch runs `swift build` twice and `check_notch.sh` twice, which
# is where most of its three minutes goes.
find Sources Tests -name '*.swift' -exec touch {} +
build_out=$(swift build 2>&1)
errors=$(printf '%s' "$build_out" | grep -c 'error:')
warnings=$(printf '%s' "$build_out" | grep -c 'warning:')
[ "$errors" -eq 0 ] || bad "$errors build error(s)"
if [ "$warnings" -eq 0 ]; then ok "no warnings"; else
    bad "$warnings warning(s)"
    printf '%s\n' "$build_out" | grep 'warning:' | sed 's/^/      /' | head -10
fi

step "Tests"
test_out=$(swift test 2>&1)
summary=$(printf '%s' "$test_out" | grep -E "Test Suite 'All tests'" -A1 | grep -E 'Executed [0-9]+ test' | tail -1)
# The exit code, not a grep for "0 failures" -- a per-suite line reports zero
# failures for a suite that passed while a sibling was red, and grepping for it
# made a mutation run report six fake tests that were all genuinely fine.
if printf '%s' "$test_out" | grep -q 'error:.*XCTAssert\|Test Suite .All tests. failed'; then
    bad "${summary:-tests failed}"
    printf '%s\n' "$test_out" | grep 'error:' | sed 's/^/      /' | head -10
elif [ -z "$summary" ]; then
    bad "no test output"
else
    ok "$(printf '%s' "$summary" | sed 's/^[[:space:]]*//')"
fi

step "Notch footprint (nothing drawn behind the camera housing)"
notch_out=$(./tools/check_notch.sh 2>&1)
# awk, not `sed s///p`: that substitutes the matched part and keeps the rest,
# so "checking 19 states in one window" came out as "19 in one window" and the
# integer comparison below blew up.
total=$(printf '%s' "$notch_out" | awk '/^checking /{print $2; exit}')
okcount=$(printf '%s' "$notch_out" | grep -c '^\S.*  *OK ')
if [ -n "$total" ] && [ "$okcount" -eq "$total" ]; then
    ok "$okcount/$total states clean"
else
    bad "$okcount/${total:-?} clean -- ./tools/check_notch.sh shows which"
    printf '%s\n' "$notch_out" | sed 's/^/      /'
fi

step "Colour contrast (HIG)"
checker="$HOME/.claude/skills/apple-hig-expert/scripts/hig_checker.py"
if [ -f "$checker" ]; then
    .build/debug/SpotifyNotch --audit > hig-audit.json
    audit=$(python3 "$checker" batch hig-audit.json 2>&1)
    score=$(printf '%s' "$audit" | sed -n 's/.*"score": \([0-9]*\).*/\1/p')
    n=$(grep -c '"type"' hig-audit.json)
    if [ "$score" = "100" ]; then ok "100/100 over $n checks"; else
        bad "score ${score:-?}"
        printf '%s\n' "$audit" | sed 's/^/      /'
    fi
else
    printf "skip  no checker at %s\n" "$checker"
fi

step "Nothing left running"
sweep=$(./tools/sweep.sh 2>&1)
if [ $? -eq 0 ]; then ok "$(printf '%s' "$sweep" | tr '\n' ';' | sed 's/ok    //g')"
else bad "see below"; printf '%s\n' "$sweep" | sed 's/^/      /'; fi

step "Docs"
# matchnotch's trap numbering collided three times, once with 43-46 each
# existing twice for weeks. One grep, run every time, instead.
for doc in docs/TRAPS.md docs/BUGS.md; do
    [ -f "$doc" ] || continue
    nums=$(grep -oE '^[0-9]+\.' "$doc" | tr -d '.')
    dupes=$(printf '%s\n' "$nums" | sort -n | uniq -d)
    # Contiguous from 1, too: a gap means an entry was deleted, and an entry
    # that stops existing takes its cross-references with it.
    expected=$(seq 1 "$(printf '%s\n' "$nums" | wc -l | tr -d ' ')")
    if [ -n "$dupes" ]; then
        bad "$doc has duplicate numbers: $(printf '%s' "$dupes" | tr '\n' ' ')"
    elif [ "$(printf '%s\n' "$nums" | sort -n)" != "$expected" ]; then
        bad "$doc numbering is not contiguous from 1"
    else
        ok "$(basename "$doc") numbering is unique and contiguous ($(printf '%s\n' "$nums" | wc -l | tr -d ' ') entries)"
    fi
done

# Every TRAPS/BUGS cross-reference must point at an entry that exists.
# `while read`, not `for` over command substitution: the refs contain a space
# and word-splitting turned each one into two, which made the first version of
# this check report every reference in the repo as dangling.
missing=""
while read -r doc num; do
    [ -n "$num" ] || continue
    grep -qE "^$num\\. " "docs/$doc" 2>/dev/null || missing="$missing $doc#$num"
done <<< "$(grep -ohE '(TRAPS|BUGS)\.md` #[0-9]+' docs/*.md *.md 2>/dev/null \
            | tr -d '`#' | sed 's/ \+/ /')"
if [ -z "$missing" ]; then ok "every cross-reference resolves"
else bad "dangling cross-references:$missing"; fi

# DECISIONS.md carries its own index, and an index nobody checks is an index
# that rots: one entry pointed at an anchor two characters different from the
# heading it names, and a heading added without an index line is invisible.
index_report=$(/usr/bin/python3 - <<'PYCHECK'
import pathlib, re, sys
text = pathlib.Path('docs/DECISIONS.md').read_text()
index = re.findall(r'^- \[(.+?)\]\(#(.+?)\)$', text, re.M)
titles = re.findall(r'^## (.+)$', text, re.M)
# GitHub's rule: lowercase, drop everything but word characters, spaces and
# hyphens, then spaces to hyphens. Backticks go; leading hyphens stay.
def anchor(t):
    return re.sub(r'[^a-z0-9 _-]', '', t.lower()).replace(' ', '-')
problems  = ["index link -> #%s names no heading" % a for _, a in index
             if a not in {anchor(t) for t in titles}]
problems += ["heading %r is missing from the index" % t for t in titles
             if t not in {label for label, _ in index}]
print("\n".join(problems) if problems else "ok %d entries" % len(index))
PYCHECK
)
if [[ "$index_report" == ok* ]]; then ok "DECISIONS.md index matches its headings (${index_report#ok })"
else bad "DECISIONS.md index: $index_report"; fi

if [ "$fail" -eq 0 ]; then
    printf "\n\033[32mAll automated checks passed.\033[0m Anything visual still needs eyes.\n"
else
    printf "\n\033[31mSomething failed.\033[0m\n"
fi
exit $fail
