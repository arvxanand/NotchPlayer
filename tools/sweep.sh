#!/bin/bash
# Is anything of ours still on the user's notch, and is their own app still up?
#
# **Both of the checks this replaces were wrong, and both reported "fine" for
# hours.** `pgrep -fl 'spotifyNotch/\.build'` never matched, because the
# processes are launched as `.build/debug/SpotifyNotch` with no directory
# prefix in argv. And `launchctl list | grep -c matchnotch` counts a *line*,
# which exists whether or not the job has a live PID -- the reference app was
# down and the check kept saying 1.
#
# A leaked **preview** cannot be quit by the user: no dock icon, no menu bar
# item, no Quit. Run this after anything that launches one. The installed
# bundle is a different matter -- since the menu-bar item exists, the user can
# quit that one themselves -- so the two are reported separately and only the
# preview is a failure.
set -uo pipefail

fail=0
# Match the **executable**, not the command line. `ps -o command` includes
# arguments, so any shell whose own invocation mentions the binary -- this
# script's caller, for one -- was reported as a leak. `comm` is the executable
# path alone.
ours=$(ps -eo pid=,etime=,comm= | awk '$3 ~ /\/SpotifyNotch$/ { print }')
# Anything whose executable lives in the app bundle is the real app, which has
# a menu-bar item and a Quit. Everything else is a build product somebody left
# running.
strays=$(printf '%s\n' "$ours" | grep -v 'SpotifyNotch\.app/Contents/MacOS/SpotifyNotch' | grep -v '^$')
app=$(printf '%s\n' "$ours" | grep 'SpotifyNotch\.app/Contents/MacOS/SpotifyNotch')

if [ -n "$strays" ]; then
    echo "LEAKED -- these have no Dock icon and no Quit, so the user cannot close them:"
    printf '%s\n' "$strays" | sed 's/^/    /'
    echo "    kill them by pid. Never 'pkill -f SpotifyNotch'."
    fail=1
elif [ -z "$app" ]; then
    echo "ok    no SpotifyNotch processes"
fi
if [ -n "$app" ]; then
    echo "ok    SpotifyNotch.app is running (quittable from its menu bar item):"
    printf '%s\n' "$app" | sed 's/^/          /'
fi

# The user's own notch app. Ask for the PID, not for the line.
agent=$(launchctl list | awk '$3 == "com.aravmanand.matchnotch" { print $1 }')
if [ -z "$agent" ]; then
    echo "ok    matchnotch agent is not loaded on this machine"
elif [ "$agent" = "-" ]; then
    echo "DOWN  matchnotch is loaded but not running."
    echo "      launchctl kickstart -k gui/\$(id -u)/com.aravmanand.matchnotch"
    fail=1
else
    echo "ok    matchnotch running as pid $agent"
fi
exit $fail
