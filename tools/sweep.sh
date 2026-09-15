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
# A leaked preview cannot be quit by the user: no dock icon, no menu bar item,
# no Quit. Run this after anything that launches previews.
set -uo pipefail

fail=0
# Match the **executable**, not the command line. `ps -o command` includes
# arguments, so any shell whose own invocation mentions the binary -- this
# script's caller, for one -- was reported as a leak. `comm` is the executable
# path alone.
ours=$(ps -eo pid=,etime=,comm= | awk '$3 ~ /\/SpotifyNotch$/ { print }')
if [ -n "$ours" ]; then
    echo "LEAKED -- these have no Dock icon and no Quit, so the user cannot close them:"
    printf '%s\n' "$ours" | sed 's/^/    /'
    echo "    kill them by pid. Never 'pkill -f SpotifyNotch'."
    fail=1
else
    echo "ok    no SpotifyNotch processes"
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
